import CoreFoundation
import Darwin
import Foundation
import Testing
@testable import NoBadgeCore

@Test func systemSettingsUsesExplicitSourceAndMigratesLegacyJournal() async throws {
    let domain = "com.asdftq.nobadge.tests.\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.appendingPathComponent("dock-preferences.plist")
    let source = target.deletingPathExtension().path
    defer {
        UserDefaults.standard.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: folder)
    }
    let key = "AttentionPrefBundleIDs" as CFString
    // The old resolver sees zero while the actual Dock source still has nine.
    CFPreferencesSetAppValue(key, ["attention": 0] as CFDictionary, domain as CFString)
    CFPreferencesAppSynchronize(domain as CFString)
    try PropertyListSerialization.data(fromPropertyList: ["AttentionPrefBundleIDs": ["attention": 9],
        "unrelated": "keep"], format: .xml, options: 0).write(to: target)
    let payload = try JSONSerialization.data(withJSONObject: [
        "schema": 1, "owner": getuid(),
        "home": FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path,
        "adapter": "system-settings-attention-v1", "originals": ["attention": 5]
    ])
    let envelope = try JSONSerialization.data(withJSONObject: [
        "payload": payload.base64EncodedString(), "checksum": NotificationSnapshot.hash(payload)
    ])
    let journal = folder.appendingPathComponent("journal.json")
    #expect(FileManager.default.createFile(atPath: journal.path, contents: envelope,
        attributes: [.posixPermissions: 0o600]))
    let engine = SystemSettingsBadges(journal: journal, canSuppress: true, domain: domain,
                                     preferenceFile: target, notify: {})
    #expect(try await engine.reconcile(hidden: true, excepted: false) == 1)
    CFPreferencesAppSynchronize(domain as CFString)
    #expect(CFPreferencesCopyAppValue(key, domain as CFString) as? [String: Int] == ["attention": 5])
    #expect(try await engine.signature() == "attention=0")
    let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
    let encoded = try #require(saved["payload"] as? String)
    let migratedData = try #require(Data(base64Encoded: encoded))
    let migrated = try #require(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
    #expect(migrated["schema"] as? Int == 2)
    #expect(migrated["source"] as? String == source)
    #expect(migrated["originals"] as? [String: Int] == ["attention": 9])
    try await engine.restore()
    #expect(try await engine.signature() == "attention=9")
    let result = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: target), format: nil) as? [String: Any])
    #expect(result["unrelated"] as? String == "keep")
    #expect(await engine.pendingRecovery() == false)
}

@Test func systemSettingsBadgeRecoveryAndExceptionPreserveFreshSystemState() async throws {
    let domain = "com.asdftq.nobadge.tests.\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        UserDefaults.standard.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: folder)
    }
    let key = "AttentionPrefBundleIDs" as CFString
    CFPreferencesSetAppValue(key, ["first": 1, "removed": 2] as CFDictionary, domain as CFString)
    CFPreferencesSetAppValue("unrelated" as CFString, "keep" as CFString, domain as CFString)
    CFPreferencesAppSynchronize(domain as CFString)
    let url = folder.appendingPathComponent("journal.json")
    let engine = SystemSettingsBadges(journal: url, canSuppress: true, domain: domain, notify: {})
    #expect(try await engine.reconcile(hidden: true, excepted: false) == 1)
    #expect(CFPreferencesCopyAppValue(key, domain as CFString) as? [String: Int] == ["first": 0, "removed": 0])
    // Simulate a system source disappearing and a fresh alert arriving while hidden.
    CFPreferencesSetAppValue(key, ["first": 0, "new": 3] as CFDictionary, domain as CFString)
    CFPreferencesAppSynchronize(domain as CFString)
    let reopened = SystemSettingsBadges(journal: url, canSuppress: true, domain: domain, notify: {})
    #expect(await reopened.pendingRecovery())
    #expect(try await reopened.reconcile(hidden: true, excepted: true) == 0)
    #expect(CFPreferencesCopyAppValue(key, domain as CFString) as? [String: Int] == ["first": 1, "new": 3])
    #expect(CFPreferencesCopyAppValue("unrelated" as CFString, domain as CFString) as? String == "keep")
    #expect(await reopened.pendingRecovery() == false)
}

@Test func unknownSystemSettingsBadgeFormatStopsBeforeWriting() async throws {
    let domain = "com.asdftq.nobadge.tests.\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { UserDefaults.standard.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: folder) }
    CFPreferencesSetAppValue("AttentionPrefBundleIDs" as CFString, ["future": "changed-format"] as CFDictionary, domain as CFString)
    CFPreferencesAppSynchronize(domain as CFString)
    let engine = SystemSettingsBadges(journal: folder.appendingPathComponent("journal.json"), canSuppress: true, domain: domain, notify: {})
    await #expect(throws: EngineError.invalidSchema) { try await engine.reconcile(hidden: true, excepted: false) }
    #expect(await engine.pendingRecovery() == false)
    #expect(CFPreferencesCopyAppValue("AttentionPrefBundleIDs" as CFString, domain as CFString) as? [String: String] == ["future": "changed-format"])
}
