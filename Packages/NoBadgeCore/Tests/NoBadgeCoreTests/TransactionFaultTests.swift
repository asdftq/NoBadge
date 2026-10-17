import Foundation
import Testing

@testable import NoBadgeCore

private enum TransactionFault: String, CaseIterable, Sendable {
  case preparedBefore, preparedAfter, writeBefore, writeAfter, refresh
  case verifyFirst, verifySecond, appliedBefore, appliedAfter, clearBefore, clearAfter
}

private actor FaultJournal: JournalPersistence {
  let disk: FileJournalStore
  let fault: TransactionFault
  var saves = 0
  var fired = false
  init(url: URL, fault: TransactionFault) {
    disk = FileJournalStore(url: url)
    self.fault = fault
  }
  func load() async throws -> RecoveryJournal? { try await disk.load() }
  func save(_ journal: RecoveryJournal) async throws {
    saves += 1
    let before = (saves == 1 && fault == .preparedBefore)
      || (saves == 2 && fault == .appliedBefore)
    let after = (saves == 1 && fault == .preparedAfter)
      || (saves == 2 && fault == .appliedAfter)
    if before && !fired { fired = true; throw EngineError.unavailable("injected persistence failure") }
    try await disk.save(journal)
    if after && !fired { fired = true; throw EngineError.unavailable("injected lost acknowledgement") }
  }
  func clear() async throws {
    if fault == .clearBefore && !fired {
      fired = true; throw EngineError.unavailable("injected clear failure")
    }
    try await disk.clear()
    if fault == .clearAfter && !fired {
      fired = true; throw EngineError.unavailable("injected lost clear acknowledgement")
    }
  }
}

private actor FaultStore: NotificationStore {
  var snapshot: NotificationSnapshot
  let fault: TransactionFault
  var reads = 0
  var writes = 0
  var fired = false
  init(_ snapshot: NotificationSnapshot, fault: TransactionFault) {
    self.snapshot = snapshot; self.fault = fault
  }
  func read() throws -> NotificationSnapshot {
    reads += 1
    if !fired && ((fault == .verifyFirst && reads == 2)
      || (fault == .verifySecond && reads == 3)) {
      fired = true; throw EngineError.verificationFailed
    }
    return snapshot
  }
  func write(data: Data, expectedFingerprint: String) throws {
    guard snapshot.fingerprint == expectedFingerprint else { throw EngineError.concurrentModification }
    if fault == .writeBefore && !fired {
      fired = true; throw EngineError.unavailable("injected store failure")
    }
    snapshot = try NotificationSnapshot(data: data); writes += 1
    if fault == .writeAfter && !fired {
      fired = true; throw EngineError.unavailable("injected lost store acknowledgement")
    }
  }
}

private actor FaultRefresh: DaemonRefreshing {
  let shouldFail: Bool
  var fired = false
  init(_ shouldFail: Bool) { self.shouldFail = shouldFail }
  func refresh() throws {
    if shouldFail && !fired { fired = true; throw EngineError.refreshFailed(1) }
  }
}

@Test(arguments: TransactionFault.allCases)
private func everyTransactionBoundaryRecoversFromThePersistedJournal(_ fault: TransactionFault) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("recovery/active-session.json")
  let original = try fixture([
    ["bundle-id": "a", "flags": 7, "future-setting": "preserve"],
    ["bundle-id": "b", "flags": 5], ["bundle-id": "c", "flags": 11],
  ])
  let store = FaultStore(original, fault: fault)
  let journal = FaultJournal(url: url, fault: fault)
  let refresh = FaultRefresh(fault == .refresh)
  let first = BadgeEngine(
    store: store, journals: journal, refresher: refresh, version: "test", osBuild: "25F80",
    verificationDelay: .zero, refreshInterval: 0)
  let clearFault = fault == .clearBefore || fault == .clearAfter
  if clearFault {
    _ = try await first.reconcile(hidden: true, qualified: true)
    await #expect(throws: (any Error).self) { try await first.restore() }
  } else {
    await #expect(throws: (any Error).self) { try await first.reconcile(hidden: true, qualified: true) }
  }
  if fault == .preparedBefore || fault == .preparedAfter || fault == .writeBefore {
    #expect(await store.writes == 0)
  }
  // A new journal reader must recover only from durable data, with no dependence
  // on the previous engine's in-memory state or failure injection wrappers.
  let relaunched = BadgeEngine(
    store: store, journals: FileJournalStore(url: url), refresher: MemoryRefresh(),
    version: "new-process", osBuild: "25F80", verificationDelay: .zero, refreshInterval: 0)
  _ = try await relaunched.restore()
  _ = try await relaunched.restore()
  #expect(original.semanticallyEquals(await store.snapshot))
  #expect(!FileManager.default.fileExists(atPath: url.path))
}
