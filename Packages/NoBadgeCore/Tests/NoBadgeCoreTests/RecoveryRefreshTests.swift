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

/// A replacement service can apply a cached snapshot only after it has started.
private actor RestartingConsumer: DaemonRefreshing {
    let store: MemoryStore
    var rollBackAtStartup = false
    var ready = true
    init(_ store: MemoryStore) { self.store = store }
    func rollBackOnce() { rollBackAtStartup = true }
    func refresh() { ready = false }
    func waitUntilReady() async throws {
        if rollBackAtStartup {
            rollBackAtStartup = false
            try await store.externallySet(["a": false])
        }
        ready = true
    }
}

@Test func restorationDoesNotRetireOriginalsBeforeReplacementServiceLoadsItsSettings() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = try fixture([["bundle-id": "a", "flags": 7], ["bundle-id": "b", "flags": 5]])
    let store = MemoryStore(original)
    let journal = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
    let consumer = RestartingConsumer(store)
    let engine = BadgeEngine(store: store, journals: journal, refresher: consumer,
        version: "test", osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
    _ = try await engine.reconcile(hidden: true, qualified: true)
    await consumer.rollBackOnce()
    await #expect(throws: EngineError.verificationFailed) { try await engine.restore() }
    #expect(await consumer.ready)
    #expect(try await journal.load()?.entries["a"]?.originalBadgeEnabled == true)
    #expect(try await engine.pendingRecovery())
    _ = try await engine.restore()
    #expect(await consumer.ready)
    #expect(original.semanticallyEquals(await store.value))
    #expect(try await engine.pendingRecovery() == false)
}

private actor PruningIDSConsumer: DaemonRefreshing {
    let store: MemoryStore
    var prune = false
    init(_ store: MemoryStore) { self.store = store }
    func pruneOnRefresh() { prune = true }
    func refresh() async throws {
        guard prune else { return }
        prune = false
        let records = await store.value.records.filter { $0.id != "com.apple.iChat" }
        let apps: [[String: Any]] = records.map {
            var app: [String: Any] = ["bundle-id": $0.id, "flags": $0.flags]
            if let path = $0.path { app["path"] = path }
            return app
        }
        await store.replace(try fixture(apps))
    }
}

@Test func legacyIDSExecutablePruningDoesNotFailRealMessagesRestoration() async throws {
    let original = try fixture([
        ["bundle-id": "com.apple.MobileSMS", "flags": 7],
        ["bundle-id": "disabled.app", "flags": 5],
        ["bundle-id": "com.apple.iChat", "flags": 41943054,
         "path": "/System/Library/PrivateFrameworks/IDS.framework/identityservicesd.app/Contents/MacOS/identityservicesd"],
    ])
    let store = MemoryStore(original), journal = MemoryJournal()
    let consumer = PruningIDSConsumer(store)
    let engine = BadgeEngine(store: store, journals: journal, refresher: consumer,
        version: "test", osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
    _ = try await engine.reconcile(hidden: true, eligibleIDs: ["com.apple.MobileSMS"], qualified: true)
    await consumer.pruneOnRefresh()
    _ = try await engine.restore()
    #expect(await store.value.flags(for: "com.apple.MobileSMS") == 7)
    #expect(await store.value.flags(for: "disabled.app") == 5)
    #expect(try await engine.pendingRecovery() == false)
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
