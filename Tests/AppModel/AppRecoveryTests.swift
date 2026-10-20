import Foundation
import NoBadgeCore
import Testing

@Suite @MainActor struct AppRecoveryTests {
    @Test(arguments: [false, true])
    func focusOffRecoversAutomaticallyAfterTemporaryFailure(refreshFailure: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try AppRecoveryStore()
        let reader = PlatformReader(store: store)
        let consumer = AppBadgeConsumer(store: store)
        let journal = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
        let engine = BadgeEngine(store: store, journals: journal, refresher: consumer,
            version: "test", osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
        let model = AppModel(engine: engine, reader: reader, folder: folder)
        model.requestRefresh()
        await model.waitForRefresh()
        #expect(model.phase == .hidden)
        #expect(await consumer.badge == false)
        if refreshFailure { await consumer.failRefreshes(2) }
        else { await store.failWrites(2) }
        await reader.setFocus(false)
        model.requestRefresh()
        await model.waitForRefresh()
        #expect(model.phase == .recovery)
        #expect(try await engine.pendingRecovery())
        let attempts = await store.attempts
        model.requestRefresh(force: true)
        await model.waitForRefresh()
        #expect(await store.attempts == attempts) // Backoff also applies to event bursts.
        try await Task.sleep(for: .milliseconds(2200))
        await model.waitForRefresh()
        #expect(model.phase == .ready)
        #expect(model.settings.automationEnabled)
        #expect(model.settings.pauseUntil == nil)
        #expect(await consumer.badge)
        #expect(try await engine.pendingRecovery() == false)
        #expect(!model.failureDiagnostic.isEmpty)
        #expect(await model.prepareToQuit())
    }
}
