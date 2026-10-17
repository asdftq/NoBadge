import CoreFoundation
import Darwin
import Foundation

public protocol NotificationStore: Sendable {
  func read() async throws -> NotificationSnapshot
  func write(data: Data, expectedFingerprint: String) async throws
}

public actor FileNotificationStore: NotificationStore {
  public let url: URL
  public private(set) var writeCount = 0
  private let preferencesDomain: String?
  private let useContainerPreferences: Bool
  public init(url: URL, usePreferencesService: Bool? = nil, useContainerPreferences: Bool? = nil) {
    self.url = url
    self.useContainerPreferences = useContainerPreferences ?? (url == Self.currentURL)
    preferencesDomain =
      (usePreferencesService ?? (url == Self.currentURL)) ? url.deletingPathExtension().path : nil
  }
  public static var currentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"
    )
  }
  private func checkPath() throws {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard values.isSymbolicLink != true, values.isRegularFile == true,
      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    else { throw EngineError.invalidSchema }
  }
  public func read() throws -> NotificationSnapshot {
    try checkPath()
    let snapshot = try NotificationSnapshot(data: Data(contentsOf: url))
    if url == Self.currentURL && snapshot.schemaVersion != 1 { throw EngineError.invalidSchema }
    return snapshot
  }
  private func conflict(_ stage: String) -> EngineError {
    if CommandLine.arguments.contains("--trace-transactions") {
      FileHandle.standardError.write(Data(("NoBadge transaction conflict: " + stage + "\n").utf8))
    }
    return .concurrentModification
  }
  public func write(data: Data, expectedFingerprint: String) throws {
    try checkPath()
    guard try read().fingerprint == expectedFingerprint else {
      throw conflict("file-fingerprint")
    }
    if let preferencesDomain {
      try writeThroughPreferences(
        data: data, expectedFingerprint: expectedFingerprint, domain: preferencesDomain)
      writeCount += 1
      return
    }
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]!
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".nobadge-\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: nil, attributes: [.posixPermissions: permissions])
    else { throw EngineError.unavailable("Cannot prepare notification settings.") }
    let handle = try FileHandle(forWritingTo: temporary)
    try handle.write(contentsOf: data)
    try handle.synchronize()
    try handle.close()
    guard try read().fingerprint == expectedFingerprint else {
      throw conflict("file-fingerprint")
    }
    guard rename(temporary.path, url.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let fd = open(url.deletingLastPathComponent().path, O_RDONLY)
    if fd >= 0 {
      _ = fsync(fd)
      close(fd)
    }
    writeCount += 1
  }
  private func writeThroughPreferences(data: Data, expectedFingerprint: String, domain: String)
    throws
  {
    let identifier = domain as CFString
    let container = useContainerPreferences
      ? try ContainerPreferences(
        identifier: url.deletingPathExtension().lastPathComponent,
        container: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
      : nil
    func synchronize() -> Bool {
      container?.synchronize()
        ?? CFPreferencesSynchronize(identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    guard synchronize()
    else {
      throw EngineError.unavailable("Cannot synchronize notification settings.")
    }
    let before = try read()
    guard before.fingerprint == expectedFingerprint else {
      throw conflict("synchronize-changed-file")
    }
    guard
      let currentRoot = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url), format: nil) as? [String: Any],
      currentRoot["apps"] is NSArray,
      let desiredRoot = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let desiredApps = desiredRoot["apps"] as? NSArray
    else { throw EngineError.invalidSchema }
    let cachedValue: CFTypeRef?
    if let container {
      cachedValue = container.value(for: "apps")
    } else {
      cachedValue = CFPreferencesCopyValue(
        "apps" as CFString, identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
      )
    }
    guard
      let cachedApps = cachedValue as? [[String: Any]],
      try before.preferencesMatchCachedApplications(cachedApps)
    else { throw conflict("preferences-cache-mismatch") }
    // Write the fresh disk snapshot, retaining its newest registration metadata.
    // Cached src/push-token metadata can lag without representing a user edit.
    // Update only the registered-app key through cfprefsd. Direct file replacement
    // leaves its old cache live and can silently undo restoration after process exit.
    guard try read().fingerprint == expectedFingerprint else {
      throw conflict("file-fingerprint")
    }
    if let container {
      container.setValue(desiredApps, for: "apps")
    } else {
      CFPreferencesSetValue(
        "apps" as CFString, desiredApps, identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    guard synchronize()
    else {
      throw EngineError.unavailable("Cannot persist notification settings.")
    }
  }

}

public protocol DaemonRefreshing: Sendable { func refresh() async throws }
public struct UserNotificationRefresher: DaemonRefreshing {
  private let command: @Sendable (String, [String]) async throws -> Int32
  private let processIDs: @Sendable () async throws -> Set<Int32>
  private let exitAttempts: Int
  private let exitDelay: Duration
  public init() {
    command = Self.execute
    processIDs = Self.runningProcessIDs
    exitAttempts = 100
    exitDelay = .milliseconds(50)
  }
  init(
    command: @escaping @Sendable (String, [String]) async throws -> Int32,
    processIDs: @escaping @Sendable () async throws -> Set<Int32> = { [] },
    exitAttempts: Int = 100, exitDelay: Duration = .milliseconds(50)
  ) {
    self.command = command
    self.processIDs = processIDs
    self.exitAttempts = exitAttempts
    self.exitDelay = exitDelay
  }
  public func refresh() async throws {
    let user = NSUserName()
    guard !user.isEmpty else { throw EngineError.unavailable("Cannot identify the current user.") }
    let previous = try await processIDs()
    let status = try await command("/usr/bin/killall", ["-u", user, "usernoted"])
    if status == 0 {
      // Signal delivery is not process termination. A dying daemon can still
      // flush cached settings; do not verify and discard recovery before it exits.
      for _ in 0..<exitAttempts {
        if previous.isDisjoint(with: try await processIDs()) { return }
        try await Task.sleep(for: exitDelay, clock: .continuous)
      }
      throw EngineError.refreshFailed(Int32(ETIMEDOUT))
    }
    // A rapid restore can follow suppression before launchd has relaunched usernoted.
    // The new process will read our synchronized preferences; no process is a success,
    // but a still-running process (including a permission failure) must fail closed.
    let running = try await command("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "usernoted"])
    guard running == 1 else { throw EngineError.refreshFailed(status) }
  }
  private static func runningProcessIDs() async throws -> Set<Int32> {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-u", String(getuid()), "-x", "usernoted"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    return try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { p in
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        try? pipe.fileHandleForReading.close()
        guard p.terminationStatus == 0 || p.terminationStatus == 1 else {
          continuation.resume(throwing: EngineError.refreshFailed(p.terminationStatus))
          return
        }
        let identifiers = String(decoding: output, as: UTF8.self).split(whereSeparator: \.isWhitespace)
        let parsed = identifiers.compactMap { Int32($0) }
        guard parsed.count == identifiers.count, parsed.allSatisfy({ $0 > 0 }) else {
          continuation.resume(throwing: EngineError.refreshFailed(-1))
          return
        }
        continuation.resume(returning: Set(parsed))
      }
      do {
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
          if process.isRunning { process.terminate() }
        }
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
  }
  private static func execute(_ path: String, _ arguments: [String]) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    return try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
      do {
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
          if process.isRunning { process.terminate() }
        }
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
  }
}
