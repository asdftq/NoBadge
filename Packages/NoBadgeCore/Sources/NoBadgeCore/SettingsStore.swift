import Foundation

/// File work stays off the UI actor. Revisions prevent an older queued choice
/// from replacing a newer one when tasks reach this actor out of order.
public actor SettingsStore {
  private let url: URL
  private var newestRevision: UInt64 = 0

  public init(url: URL) { self.url = url }

  public func save(_ settings: UserSettings, revision: UInt64) throws {
    guard revision > newestRevision else { return }
    newestRevision = revision
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(settings).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
