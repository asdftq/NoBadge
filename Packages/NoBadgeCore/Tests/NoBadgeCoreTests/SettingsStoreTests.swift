import Foundation
import Testing
@testable import NoBadgeCore

@Test func concurrentSettingsSavesPreserveTheNewestChoice() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let url = folder.appendingPathComponent("settings.json")
  let store = SettingsStore(url: url)
  try await withThrowingTaskGroup(of: Void.self) { group in
    for revision in 1...100 {
      group.addTask {
        var settings = UserSettings()
        settings.exceptionBundleIDs = ["test.revision.\(revision)"]
        try await store.save(settings, revision: UInt64(revision))
      }
    }
    try await group.waitForAll()
  }
  let saved = try JSONDecoder().decode(UserSettings.self, from: Data(contentsOf: url))
  #expect(saved.exceptionBundleIDs == ["test.revision.100"])
  let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
  #expect(permissions == 0o600)
}

@Test func failedNewestSettingsSaveCannotBeReplacedByAnOlderChoice() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let url = folder.appendingPathComponent("settings.json")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
  let store = SettingsStore(url: url)
  var latest = UserSettings()
  latest.automationEnabled = false
  await #expect(throws: (any Error).self) { try await store.save(latest, revision: 2) }
  try FileManager.default.removeItem(at: url)
  try await store.save(UserSettings(), revision: 1)
  #expect(!FileManager.default.fileExists(atPath: url.path))
  try await store.save(latest, revision: 3)
  let saved = try JSONDecoder().decode(UserSettings.self, from: Data(contentsOf: url))
  #expect(!saved.automationEnabled)
}

@Test func focusSyncIntervalMigratesAndPersistsWithoutResettingPreferences() throws {
  var old = UserSettings()
  old.automationEnabled = true
  old.exceptionBundleIDs = ["test.keep-visible"]
  let legacy = try JSONEncoder().encode(old)
  var decoded = try JSONDecoder().decode(UserSettings.self, from: legacy)
  #expect(decoded.focusSyncInterval == .oneSecond)
  #expect(decoded.automationEnabled)
  #expect(decoded.exceptionBundleIDs == old.exceptionBundleIDs)
  decoded.focusSyncInterval = .fiveSeconds
  let saved = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(decoded))
  #expect(saved.focusSyncInterval == .fiveSeconds)
  #expect(saved.exceptionBundleIDs == old.exceptionBundleIDs)
  decoded.focusSyncIntervalSeconds = 0
  #expect(decoded.focusSyncInterval == .oneSecond)
}
