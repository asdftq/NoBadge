import Foundation
import NoBadgeCore
import Testing

extension AppRecoveryStore {
    func registerAnotherApp() throws {
        var root = try PropertyListSerialization.propertyList(from: snapshot.patched([:]), format: nil) as! [String: Any]
        var apps = root["apps"] as! [[String: Any]]
        apps.append(["bundle-id": "com.asdftq.nobadge.fixture.new", "flags": 7])
        root["apps"] = apps
        snapshot = try NotificationSnapshot(data: PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))
    }
}
@Suite @MainActor struct FocusLatencyTests {
    @Test func pollingPreemptsSuppressionCooldownWhenFocusEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try AppRecoveryStore()
        let reader = PlatformReader(store: store)
        let consumer = AppBadgeConsumer(store: store)
        // Keep the production 10-second suppression interval. Only remove readback delay.
        let engine = BadgeEngine(store: store, journals: FileJournalStore(url: folder.appendingPathComponent("active.json")),
            refresher: consumer, version: "test", osBuild: "26A434", verificationDelay: .zero)
        let model = AppModel(engine: engine, reader: reader, folder: folder)
        model.requestRefresh()
        await model.waitForRefresh()
        #expect(await consumer.badge == false)
        try await store.registerAnotherApp()
        model.requestRefresh(interrupt: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.phase == .working)
        model.observer.start(watchingFolders: [])
        let start = ContinuousClock.now
        await reader.setFocus(false)
        // Only the real one-second ChangeObserver timer may detect this change.
        await model.waitForRefresh()
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .seconds(2))
        #expect(await consumer.badge)
        #expect(model.phase == .ready)
        model.observer.stop()
        #expect(await model.prepareToQuit())
    }
}
