import CoreFoundation
import Foundation
import Testing
@testable import NoBadgeCore

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
