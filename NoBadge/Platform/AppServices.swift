import AppKit
import Darwin
import Foundation
import NoBadgeCore

struct PlatformInputs: Sendable {
  let focus: FocusObservation
  let notifications: NotificationSnapshot
  var signature: String {
    let flags = notifications.records.map { "\($0.id):\($0.flags)" }.sorted().joined(separator: "|")
    return flags + "#" + String(describing: focus)
  }
}
actor PlatformReader {
  func load() async throws -> PlatformInputs {
    let snapshot = try await FileNotificationStore(url: FileNotificationStore.currentURL).read()
    let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/DoNotDisturb/DB")
    let focus: FocusObservation
    do {
      focus = FocusDecoder.decode(
        assertions: try Data(contentsOf: db.appendingPathComponent("Assertions.json")),
        configurations: try? Data(contentsOf: db.appendingPathComponent("ModeConfigurations.json")))
    } catch {
      let ns = error as NSError
      let denied =
        (ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError)
        || (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
      focus = .unknown(denied ? "focusAccessDenied" : "focusUnavailable")
    }
    return PlatformInputs(focus: focus, notifications: snapshot)
  }
}
func currentArchitecture() -> String {
  #if arch(arm64)
    return "arm64"
  #else
    return "x86_64"
  #endif
}
func currentOSBuild() -> String {
  var size = 0
  sysctlbyname("kern.osversion", nil, &size, nil, 0)
  var bytes = [CChar](repeating: 0, count: size)
  sysctlbyname("kern.osversion", &bytes, &size, nil, 0)
  return String(
    bytes: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    ?? "unknown"
}
@MainActor final class SingleInstanceLock {
  private var descriptor: Int32 = -1
  init(folder: URL) throws {
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    descriptor = open(
      folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      if descriptor >= 0 { close(descriptor) }
      descriptor = -1
      throw EngineError.unavailable("NoBadge is already running.")
    }
  }
  func release() {
    if descriptor >= 0 {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
      descriptor = -1
    }
  }
}
@MainActor final class ChangeObserver {
  private var sources: [DispatchSourceFileSystemObject] = []
  private var timer: Timer?
  private var debounce: Task<Void, Never>?
  private var systemBadgeToken: NSObjectProtocol?
  private let systemBadges: Bool
  private let changed: @MainActor () -> Void
  init(systemBadges: Bool = false, changed: @escaping @MainActor () -> Void) {
    self.systemBadges = systemBadges
    self.changed = changed
  }
  func start() {
    stop()
    if systemBadges {
      systemBadgeToken = DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("com.apple.systempreferences.refreshdocktile"),
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.schedule() } }
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folders = [
      home.appendingPathComponent("Library/DoNotDisturb/DB"),
      FileNotificationStore.currentURL.deletingLastPathComponent(),
    ]
    for folder in folders {
      let fd = open(folder.path, O_EVTONLY)
      guard fd >= 0 else { continue }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
      source.setEventHandler { [weak self] in Task { @MainActor in self?.schedule() } }
      source.setCancelHandler { close(fd) }
      source.resume()
      sources.append(source)
    }
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.changed() }
    }
    timer?.tolerance = 5
  }
  private func schedule() {
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      self?.changed()
    }
  }
  func stop() {
    if let systemBadgeToken { DistributedNotificationCenter.default().removeObserver(systemBadgeToken) }
    systemBadgeToken = nil
    debounce?.cancel()
    debounce = nil
    sources.forEach { $0.cancel() }
    sources = []
    timer?.invalidate()
    timer = nil
  }
}
