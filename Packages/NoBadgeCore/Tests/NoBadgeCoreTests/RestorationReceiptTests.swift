import Foundation
import Testing
@testable import NoBadgeCore

@Test func restorationReceiptRetainsOriginalsAfterALateExternalRollback() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let active = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
  let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7], ["bundle-id": "b", "flags": 5]]))
  let refresh = MemoryRefresh()
  let engine = BadgeEngine(store: store, journals: active, refresher: refresh,
    version: "test", osBuild: "test", verificationDelay: .zero, refreshInterval: 0)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  _ = try await engine.restore()
  #expect(try await active.load() == nil)
  let receipt = FileJournalStore(url: folder.appendingPathComponent("last-restored-session.json"))
  // A new process can recover the narrow originals without a whole-plist backup.
  let recovered = try #require(try await receipt.load())
  #expect(recovered.entries["a"]?.originalBadgeEnabled == true)
  #expect(recovered.entries["b"] == nil)
  await store.replace(try fixture([["bundle-id": "a", "flags": 13], ["bundle-id": "b", "flags": 5]]))
  _ = try await engine.restore()
  // A completed receipt must not automatically overwrite later external edits.
  #expect(await store.value.flags(for: "a") == 13)
  try await active.save(recovered)
  let relaunched = BadgeEngine(store: store, journals: active, refresher: refresh,
    version: "test", osBuild: "test", verificationDelay: .zero, refreshInterval: 0)
  _ = try await relaunched.restore()
  #expect(await store.value.flags(for: "a") == 15)
  #expect(await store.value.flags(for: "b") == 5)
}

@Test func receiptFailureKeepsTheActiveRecoveryJournal() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let active = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
  var journal = RecoveryJournal(version: "test", osBuild: "test")
  journal.entries["test.app"] = JournalEntry(bundleID: "test.app", originalBadgeEnabled: true)
  try await active.save(journal)
  try FileManager.default.createDirectory(
    at: folder.appendingPathComponent("last-restored-session.json"), withIntermediateDirectories: false)
  await #expect(throws: (any Error).self) { try await active.finishRestoration() }
  #expect(try await active.load() == journal)
}

@Test func abandonedPreparedWriteDoesNotReplaceTheRestorationReceipt() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let active = FileJournalStore(url: folder.appendingPathComponent("active-session.json"))
  let restored = RecoveryJournal(version: "restored", osBuild: "test")
  try await active.save(restored)
  try await active.finishRestoration()
  try await active.save(RecoveryJournal(version: "abandoned", osBuild: "test"))
  try await active.clear()
  let receipt = FileJournalStore(url: folder.appendingPathComponent("last-restored-session.json"))
  #expect(try await receipt.load() == restored)
}
