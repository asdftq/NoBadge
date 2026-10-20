import Foundation
import NoBadgeCore
import Testing

@Suite @MainActor struct AppRecoveryTests {
    @Test func menuBarIconStaysSettledDuringFocusRechecks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try AppRecoveryStore()
        let reader = PlatformReader(store: store)
        let consumer = AppBadgeConsumer(store: store)
        let engine = BadgeEngine(store: store,
            journals: FileJournalStore(url: folder.appendingPathComponent("active-session.json")),
            refresher: consumer, version: "test", osBuild: "26A434",
            verificationDelay: .zero, refreshInterval: 0)
        let model = AppModel(engine: engine, reader: reader, folder: folder)
        var icon = MenuBarIcon()
        var changes = [icon.symbol]
        var workingIcons: [String] = []
        model.stateChanged = {
            if icon.update(phase: model.phase) { changes.append(icon.symbol) }
            if model.phase == .working { workingIcons.append(icon.symbol) }
        }
        await reader.setFocus(false)
        model.requestRefresh()
        await model.waitForRefresh()
        await reader.setFocus(true)
        model.requestRefresh()
        await model.waitForRefresh()
        #expect(model.phase == .hidden)
        #expect(await consumer.badge == false)
        workingIcons.removeAll()
        // Reproduce the post-write event burst, including an event queued mid-refresh.
        model.requestRefresh(force: true)
        model.requestRefresh(force: true)
        await model.waitForRefresh()
        #expect(!workingIcons.isEmpty)
        #expect(workingIcons.allSatisfy { $0 == "app.badge.checkmark" })
        await reader.setFocus(false)
        model.requestRefresh()
        await model.waitForRefresh()
        model.requestRefresh(force: true)
        await model.waitForRefresh()
        #expect(model.phase == .ready)
        #expect(await consumer.badge)
        #expect(changes == ["app", "app.badge.checkmark", "app"])
        #expect(model.settings.focusSyncInterval == .oneSecond)
        // Attention states must still replace the settled icon immediately.
        icon.update(phase: .recovery)
        icon.update(phase: .working)
        #expect(icon.symbol == "exclamationmark.circle")
        #expect(await model.prepareToQuit())
    }

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
        if refreshFailure {
            model.setFocusSyncInterval(.thirtySeconds)
            await consumer.failRefreshes(2)
        }
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
        // Changing the setting reschedules an already pending recovery, too.
        if refreshFailure { model.setFocusSyncInterval(.oneSecond) }
        try await Task.sleep(for: .milliseconds(1350))
        await model.waitForRefresh()
        #expect(model.phase == .ready)
        #expect(model.settings.automationEnabled)
        #expect(model.settings.pauseUntil == nil)
        #expect(await consumer.badge)
        #expect(try await engine.pendingRecovery() == false)
        #expect(!model.failureDiagnostic.isEmpty)
        #expect(await model.prepareToQuit())
    }
    @Test func pollingDetectsFocusOffAndUsesChangedIntervalWithoutRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try AppRecoveryStore()
        let reader = PlatformReader(store: store)
        let consumer = AppBadgeConsumer(store: store)
        let journal = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
        let engine = BadgeEngine(store: store, journals: journal, refresher: consumer,
            version: "test", osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0)
        let model = AppModel(engine: engine, reader: reader, folder: folder)
        #expect(model.settings.focusSyncInterval == .oneSecond)
        model.requestRefresh()
        await model.waitForRefresh()
        #expect(await consumer.badge == false)
        model.setFocusSyncInterval(.thirtySeconds)
        // Use the real timer, but no filesystem or distributed notifications.
        model.observer.start(watchingFolders: [])
        defer { model.observer.stop() }
        await reader.setFocus(false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.phase == .hidden)
        model.setFocusSyncInterval(.oneSecond)
        try await Task.sleep(for: .milliseconds(1350))
        await model.waitForRefresh()
        #expect(model.phase == .ready)
        #expect(await consumer.badge)
        #expect(try await engine.pendingRecovery() == false)
        #expect(await model.prepareToQuit())
        let saved = try JSONDecoder().decode(UserSettings.self,
            from: Data(contentsOf: folder.appendingPathComponent("settings.json")))
        #expect(saved.focusSyncInterval == .oneSecond)
        #expect(saved.automationEnabled)
    }

}
