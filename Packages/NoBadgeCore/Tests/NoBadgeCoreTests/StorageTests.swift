import Foundation
import Testing
@testable import NoBadgeCore

func fixture(_ apps: [[String: Any]]) throws -> NotificationSnapshot {
    try NotificationSnapshot(data: PropertyListSerialization.data(fromPropertyList: ["apps":apps,"unrelated":["color":"blue"]], format: .binary, options: 0))
}
@Test func patchesOnlyOneBadgeBitAndPreservesOtherValues() throws {
    let before = try fixture([["bundle-id":"a","flags":7,"extra":"keep"],["bundle-id":"b","flags":5]])
    let hidden = try NotificationSnapshot(data: before.patched(["a":false]))
    #expect(hidden.flags(for:"a") == 5); #expect(hidden.flags(for:"b") == 5)
    #expect(before.semanticallyEquals(hidden,excludingBadgeBitsFor:["a"]))
    let later = try fixture([["bundle-id":"a","flags":13,"extra":"keep"],["bundle-id":"b","flags":5]])
    let restored = try NotificationSnapshot(data: later.patched(["a":true]))
    #expect(restored.flags(for:"a") == 15); #expect(restored.flags(for:"b") == 5)
}
@Test func malformedAndDuplicateRecordsAreRejected() throws {
    #expect(throws: EngineError.invalidSchema) { try fixture([["bundle-id":"a","flags":true]]) }
    #expect(throws: EngineError.invalidSchema) { try fixture([["bundle-id":"a","flags":2.5]]) }
    #expect(throws: EngineError.invalidSchema) { try fixture([["bundle-id":"a","flags":2],["bundle-id":"a","flags":0]]) }
}
@Test func fileStoreRejectsConcurrentReplacement() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let before = try fixture([["bundle-id":"a","flags":7]])
    try before.patched([:]).write(to: url)
    let store = FileNotificationStore(url: url)
    let s = try await store.read()
    try before.patched(["a":false]).write(to:url)
    await #expect(throws: EngineError.concurrentModification) { try await store.write(data: s.patched(["a":true]), expectedFingerprint:s.fingerprint) }
    #expect(await store.writeCount == 0)
}
@Test func noFocusDecodesAndAmbiguityIsUnknown() throws {
    let configs = Data(#"{"header":{"version":3},"data":[{"modeConfigurations":{}}]}"#.utf8)
    let off = Data(#"{"header":{"version":8},"data":[{"storeAssertionRecords":[]}]}"#.utf8)
    #expect(FocusDecoder.decode(assertions:off,configurations:configs).activeIDs == [])
    let ambiguous = Data(#"{"header":{"version":8},"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"a"}},{"assertionDetails":{"assertionDetailsModeIdentifier":"b"}}]}]}"#.utf8)
    #expect(FocusDecoder.decode(assertions:ambiguous,configurations:configs).activeIDs == nil)
}

@Test func staleRegistrationMetadataDoesNotBlockPreferenceCacheAgreement() throws {
    let current = try fixture([["bundle-id": "a", "flags": 7, "src": [2], "push": ["token": "new"], "custom": "keep"]])
    #expect(try current.preferencesMatchCachedApplications([["bundle-id": "a", "flags": 7, "src": [1], "push": ["token": "old"], "custom": "keep"]]))
    #expect(try !current.preferencesMatchCachedApplications([["bundle-id": "a", "flags": 5, "src": [1], "push": ["token": "old"], "custom": "keep"]]))
    #expect(try !current.preferencesMatchCachedApplications([["bundle-id": "a", "flags": 7, "src": [1], "push": ["token": "old"], "custom": "changed"]]))
    #expect(try !current.preferencesMatchCachedApplications([]))
}
