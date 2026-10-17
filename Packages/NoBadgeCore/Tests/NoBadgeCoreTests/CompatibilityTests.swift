import Foundation
import Testing
@testable import NoBadgeCore

private func compatibilityManifest() throws -> CompatibilityManifest {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode(CompatibilityManifest.self,
        from: Data(contentsOf: root.appendingPathComponent("NoBadge/Resources/Compatibility.json")))
}

@Test func supportedOSFamiliesKeepPreviousBuildsAndAcceptPatchUpdates() throws {
    let manifest = try compatibilityManifest()
    for (version, build, profile) in [
        (OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1), "25F80", "macos-26"),
        (OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0), "25G72", "macos-26"),
        (OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 1), "25G100", "macos-26"),
        (OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1), "26A434", "macos-27"),
        (OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0), "26B100", "macos-27")
    ] {
        #expect(manifest.profile(for: version, osBuild: build, architecture: "arm64")?.id == profile)
    }
    let current = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
    #expect(manifest.profile(for: current, osBuild: "26A434", architecture: "x86_64") == nil)
    #expect(manifest.profile(for: current, osBuild: "250A434", architecture: "arm64") == nil)
    #expect(manifest.profile(for: .init(majorVersion: 28, minorVersion: 0, patchVersion: 0),
                             osBuild: "27A100", architecture: "arm64") == nil)
    #expect(manifest.profile(for: .init(majorVersion: 26, minorVersion: 5, patchVersion: 0),
                             osBuild: "25F70", architecture: "arm64") == nil)
}

@Test func compatibleOSUpgradeRestoresPreviousSessionWithoutChangingOtherBits() async throws {
    let manifest = try compatibilityManifest()
    let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7]]))
    let journal = MemoryJournal()
    let refresher = MemoryRefresh()
    let old = BadgeEngine(store: store, journals: journal, refresher: refresher,
                          version: "old", osBuild: "25G72", verificationDelay: .zero, refreshInterval: 0)
    _ = try await old.reconcile(hidden: true, qualified: true)
    let upgraded = BadgeEngine(store: store, journals: journal, refresher: refresher,
        version: "new", osBuild: "26A434", verificationDelay: .zero, refreshInterval: 0,
        compatibleRecoveryBuildPrefixes: manifest.recoveryBuildPrefixes(architecture: "arm64"))
    _ = try await upgraded.restore()
    #expect(await store.value.flags(for: "a") == 7)
    #expect(await journal.value == nil)
}
