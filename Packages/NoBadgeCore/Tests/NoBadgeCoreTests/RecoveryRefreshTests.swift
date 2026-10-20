import Foundation
import Testing
@testable import NoBadgeCore

private actor BadgeConsumer: DaemonRefreshing {
    let store: MemoryStore
    var failNext = false
    var badge = true
    var calls = 0
    init(_ store: MemoryStore) { self.store = store }
    func failOnce() { failNext = true }
    func refresh() async throws {
        calls += 1
        if failNext { failNext = false; throw EngineError.refreshFailed(60) }
        badge = await store.value.records[0].badgeEnabled
    }
}

@Test func restorationRetriesRefreshAfterBitsWereAlreadyWritten() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7]]))
    let journal = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
    let consumer = BadgeConsumer(store)
    func engine() -> BadgeEngine {
        BadgeEngine(store: store, journals: journal, refresher: consumer, version: "test",
                    osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
    }
    let first = engine()
    _ = try await first.reconcile(hidden: true, qualified: true)
    await consumer.failOnce()
    await #expect(throws: EngineError.refreshFailed(60)) { try await first.restore() }
    #expect(await store.value.flags(for: "a") == 7)
    #expect(await consumer.badge == false)
    #expect(try await journal.load()?.phase == "needsRecovery")
    let writes = await store.writes
    let restarted = engine()
    _ = try await restarted.restore()
    #expect(await consumer.badge)
    #expect(await consumer.calls == 3)
    #expect(await store.writes == writes)
    #expect(try await restarted.pendingRecovery() == false)
    let receipt = FileJournalStore(url: folder.appendingPathComponent("last-restored-session.json"))
    #expect(try await receipt.load()?.phase == "applied")
}

@Test func oldRetiredFailureRefreshesCurrentPreferencesWithoutReplayingOriginals() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let journal = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
    var old = RecoveryJournal(version: "0.1.42", osBuild: "26A434")
    old.entries["a"] = JournalEntry(bundleID: "a", originalBadgeEnabled: true)
    old.phase = "needsRecovery"
    try await journal.save(old)
    try await journal.finishRestoration() // Reproduce an already-retired 0.1.42 journal.
    let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 13]]))
    let consumer = BadgeConsumer(store)
    let engine = BadgeEngine(store: store, journals: journal, refresher: consumer, version: "test",
                             osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
    #expect(try await engine.pendingRecovery())
    await consumer.failOnce()
    await #expect(throws: EngineError.refreshFailed(60)) { try await engine.restore() }
    #expect(try await engine.pendingRecovery())
    _ = try await engine.restore()
    #expect(await store.writes == 0)
    #expect(await store.value.flags(for: "a") == 13)
    #expect(await consumer.badge == false)
    #expect(try await engine.pendingRecovery() == false)
}

@Test func invalidRecoveryFormatsNeverPermitAutomaticRetry() {
    #expect(!EngineError.invalidSchema.permitsAutomaticRecovery)
    #expect(!EngineError.invalidJournal.permitsAutomaticRecovery)
    #expect(!EngineError.unsupportedOS.permitsAutomaticRecovery)
    #expect(EngineError.verificationFailed.permitsAutomaticRecovery)
    #expect(EngineError.refreshFailed(60).permitsAutomaticRecovery)
}
