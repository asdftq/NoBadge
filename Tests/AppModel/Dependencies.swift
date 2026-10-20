// The test target compiles the real AppModel with isolated platform dependencies.
// It never starts the app delegate, reads accounts, or changes macOS preferences.
import AppKit
import Foundation
import NoBadgeCore
import SwiftUI

func L(_ value: String) -> String { value }
func currentOSBuild() -> String { "26A434" }
func currentArchitecture() -> String { "arm64" }
enum SettingsSection { case general }
@MainActor enum AppLocalization { static var language = AppLanguage.english }
@MainActor final class LicenseService: ObservableObject {
    var canUse = true
    var changed: (() -> Void)?
    func start() {}
}
@MainActor final class ReviewRequestCoordinator {
    init(folder: URL, labOnly: Bool) {}
    func reconciled(automatic: Bool, focusActive: Bool, hidden: Bool, restored: Bool) {}
}
struct AppEntry: Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let recordIDs: Set<String>
}
actor ApplicationCatalog {
    func load(_ records: [NotificationRecord]) -> [AppEntry] {
        records.map { AppEntry(id: $0.id, name: $0.id,
            url: URL(fileURLWithPath: "/tmp/fixture.app"), recordIDs: [$0.id]) }
    }
}
struct PlatformInputs: Sendable {
    let focus: FocusObservation
    let notifications: NotificationSnapshot
    var signature: String {
        notifications.records.map { "\($0.id):\($0.flags)" }.sorted().joined(separator: "|")
            + "#" + String(describing: focus)
    }
}
actor PlatformReader {
    var store: AppRecoveryStore?
    var observation: FocusObservation = .known(activeIDs: ["work"], modes: [])
    init(store: AppRecoveryStore? = nil) { self.store = store }
    func setFocus(_ on: Bool) { observation = .known(activeIDs: on ? ["work"] : [], modes: []) }
    func load() async throws -> PlatformInputs {
        guard let store else { throw EngineError.unavailable("Test reader not configured") }
        return PlatformInputs(focus: observation, notifications: await store.read())
    }
}
actor AppRecoveryStore: NotificationStore {
    var snapshot: NotificationSnapshot
    var writeFailures = 0
    var attempts = 0
    init() throws {
        snapshot = try NotificationSnapshot(data: PropertyListSerialization.data(fromPropertyList:
            ["version": 1, "apps": [["bundle-id": "com.asdftq.nobadge.fixture.audit", "flags": 7]]],
            format: .binary, options: 0))
    }
    func read() -> NotificationSnapshot { snapshot }
    func failWrites(_ count: Int) { writeFailures = count }
    func write(data: Data, expectedFingerprint: String) throws {
        attempts += 1
        if writeFailures > 0 {
            writeFailures -= 1
            throw EngineError.unavailable("temporary write failure")
        }
        guard snapshot.fingerprint == expectedFingerprint else { throw EngineError.concurrentModification }
        snapshot = try NotificationSnapshot(data: data)
    }
    var badge: Bool { snapshot.records[0].badgeEnabled }
}
actor AppBadgeConsumer: DaemonRefreshing {
    let store: AppRecoveryStore
    var failures = 0
    var badge = true
    init(store: AppRecoveryStore) { self.store = store }
    func failRefreshes(_ count: Int) { failures = count }
    func refresh() async throws {
        if failures > 0 { failures -= 1; throw EngineError.refreshFailed(60) }
        badge = await store.badge
    }
}
