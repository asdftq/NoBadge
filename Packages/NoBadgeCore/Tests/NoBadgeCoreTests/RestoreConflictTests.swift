import Foundation
import Testing
@testable import NoBadgeCore

private actor ConflictingStore: NotificationStore {
  var snapshot: NotificationSnapshot
  var conflicts = 0
  var attempts = 0
  init() throws { snapshot = try fixture([["bundle-id": "a", "flags": 7]]) }
  func read() -> NotificationSnapshot { snapshot }
  func fail(_ count: Int) { conflicts = count; attempts = 0 }
  func write(data: Data, expectedFingerprint: String) throws {
    attempts += 1
    if conflicts > 0 {
      conflicts -= 1
      // Simulate a concurrent user's unrelated flag change between read and write.
      snapshot = try fixture([["bundle-id": "a", "flags": (snapshot.flags(for: "a")! | 8)]])
      throw EngineError.concurrentModification
    }
    guard snapshot.fingerprint == expectedFingerprint else { throw EngineError.concurrentModification }
    snapshot = try NotificationSnapshot(data: data)
  }
}
@Test func restoreRebasesAfterConcurrentChangeAndPreservesUnrelatedFlags() async throws {
  let store = try ConflictingStore(), journal = MemoryJournal()
  let engine = BadgeEngine(store: store, journals: journal, refresher: MemoryRefresh(), version: "test", osBuild: "25F80", verificationDelay: .zero)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  await store.fail(1)
  _ = try await engine.restore()
  #expect(await store.snapshot.flags(for: "a") == 15)
  #expect(await store.attempts == 2)
  #expect(await journal.value == nil)
}
@Test func persistentRestoreConflictStopsAfterThreeAttemptsAndRetainsJournal() async throws {
  let store = try ConflictingStore(), journal = MemoryJournal()
  let engine = BadgeEngine(store: store, journals: journal, refresher: MemoryRefresh(), version: "test", osBuild: "25F80", verificationDelay: .zero)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  await store.fail(10)
  await #expect(throws: EngineError.concurrentModification) { try await engine.restore() }
  #expect(await store.attempts == 3)
  #expect(await store.snapshot.flags(for: "a") == 13)
  #expect(await journal.value != nil)
}

@Test func suppressionRebasesAfterConcurrentChangeAndPreservesUnrelatedFlags() async throws {
  let store = try ConflictingStore(), journal = MemoryJournal(), refresh = MemoryRefresh()
  let engine = BadgeEngine(store: store, journals: journal, refresher: refresh, version: "test", osBuild: "25F80", verificationDelay: .zero)
  await store.fail(1)
  let result = try await engine.reconcile(hidden: true, qualified: true)
  #expect(result.hiddenCount == 1)
  #expect(await store.snapshot.flags(for: "a") == 13)
  #expect(await store.attempts == 2)
  #expect(await refresh.count == 1)
  _ = try await engine.restore()
  #expect(await store.snapshot.flags(for: "a") == 15)
  #expect(await journal.value == nil)
}

@Test func persistentSuppressionConflictStopsWithoutOwningUntouchedBits() async throws {
  let store = try ConflictingStore(), journal = MemoryJournal(), refresh = MemoryRefresh()
  let engine = BadgeEngine(store: store, journals: journal, refresher: refresh, version: "test", osBuild: "25F80", verificationDelay: .zero)
  await store.fail(10)
  await #expect(throws: EngineError.concurrentModification) {
    try await engine.reconcile(hidden: true, qualified: true)
  }
  #expect(await store.attempts == 3)
  #expect(await store.snapshot.flags(for: "a") == 15)
  #expect(await journal.value == nil)
  #expect(await refresh.count == 0)
}

@Test func restorePreemptsSuppressionConflictRetry() async throws {
  let store = try ConflictingStore(), journal = MemoryJournal(), refresh = MemoryRefresh()
  let engine = BadgeEngine(store: store, journals: journal, refresher: refresh, version: "test", osBuild: "25F80", verificationDelay: .zero)
  await store.fail(10)
  let hiding = Task { try await engine.reconcile(hidden: true, qualified: true) }
  while await store.attempts == 0 { await Task.yield() }
  _ = try await engine.restore()
  _ = try await hiding.value
  #expect(await store.attempts == 1)
  #expect(await store.snapshot.flags(for: "a") == 15)
  #expect(await journal.value == nil)
  #expect(await refresh.count == 0)
}
