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
    return PlatformInputs(focus: loadFocus(), notifications: snapshot)
  }
  func loadFocus() -> FocusObservation {
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
    return focus
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
