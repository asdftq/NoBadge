import Foundation
import Testing

@testable import NoBadgeCore

private func assertions(_ records: [[String: Any]]?) throws -> Data {
  let group: [String: Any] =
    records.map { ["storeAssertionRecords": $0] } ?? ["storeInvalidationRecords": []]
  return try JSONSerialization.data(withJSONObject: ["header": ["version": 8], "data": [group]])
}
private func assertion(_ id: String, _ start: Any) -> [String: Any] {
  [
    "assertionStartDateTimestamp": start,
    "assertionDetails": ["assertionDetailsModeIdentifier": id],
  ]
}

@Test func scheduledFocusOverridesOlderManualAssertionRegardlessOfArrayOrder() throws {
  let older = assertion("personal", 100.0)
  let newer = assertion("sleep", 200.0)
  for records in [[older, newer], [newer, older]] {
    #expect(FocusDecoder.decode(assertions: try assertions(records)).activeIDs == ["sleep"])
  }
}
@Test func focusOffMayOmitActiveRecordsWhileRetainingInvalidationHistory() throws {
  #expect(FocusDecoder.decode(assertions: try assertions(nil)).activeIDs == [])
}
@Test func equalOrInvalidTimestampsDoNotGuessTheActiveFocus() throws {
  for timestamp: Any in [100.0, true, "200"] {
    let records = [assertion("personal", 100.0), assertion("sleep", timestamp)]
    #expect(FocusDecoder.decode(assertions: try assertions(records)).activeIDs == nil)
  }
}
@Test func missingOrMalformedModeNamesDoNotDisableFocusDetection() throws {
  let data = try assertions([assertion("work", 100.0)])
  for configuration in [nil, Data("invalid".utf8)] {
    let state = FocusDecoder.decode(assertions: data, configurations: configuration)
    #expect(state.activeIDs == ["work"])
    #expect(state.displayName == "Focus")
  }
}
@Test func overlappingAssertionsUseOnlyEffectiveModeForSelectedFocusRules() throws {
  let state = FocusDecoder.decode(
    assertions: try assertions([assertion("personal", 100.0), assertion("sleep", 200.0)]))
  var settings = UserSettings()
  settings.onboardingComplete = true
  settings.setupRevision = UserSettings.currentSetupRevision
  settings.automationEnabled = true
  settings.selectedFocusIDs = ["personal"]
  #expect(
    PolicyReducer.desired(
      settings: settings, focus: state, now: .now, capable: true, recoveryPending: false)
      == .visible)
  settings.selectedFocusIDs = ["sleep"]
  #expect(
    PolicyReducer.desired(
      settings: settings, focus: state, now: .now, capable: true, recoveryPending: false) == .hidden
  )
}
@Test func repeatedHiddenRefreshDoesNotWaitForSuppressionCooldown() async throws {
  let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7]]))
  let journal = MemoryJournal()
  let refresher = MemoryRefresh()
  let engine = BadgeEngine(
    store: store, journals: journal, refresher: refresher, version: "test", osBuild: "25F80",
    verificationDelay: .zero, refreshInterval: 2)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  let start = ContinuousClock.now
  for _ in 0..<10 {
    #expect(try await engine.reconcile(hidden: true, qualified: true).wrote == false)
  }
  #expect(ContinuousClock.now - start < .milliseconds(500))
  #expect(await refresher.count == 1)
  _ = try await engine.restore()
}

@Test func addingExceptionRestoresImmediatelyDuringSuppressionCooldown() async throws {
  let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7]]))
  let engine = BadgeEngine(
    store: store, journals: MemoryJournal(), refresher: MemoryRefresh(), version: "test",
    osBuild: "25F80", verificationDelay: .zero, refreshInterval: 2)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  let start = ContinuousClock.now
  _ = try await engine.reconcile(hidden: true, exceptions: ["a"], qualified: true)
  #expect(ContinuousClock.now - start < .milliseconds(500))
  #expect(await store.value.flags(for: "a") == 7)
  _ = try await engine.restore()
}

@Test func changedIntentCancelsPendingSuppressionWithoutWaitingForCooldown() async throws {
  let store = MemoryStore(try fixture([["bundle-id": "a", "flags": 7]]))
  let engine = BadgeEngine(
    store: store, journals: MemoryJournal(), refresher: MemoryRefresh(), version: "test",
    osBuild: "25F80", verificationDelay: .zero, refreshInterval: 5)
  _ = try await engine.reconcile(hidden: true, qualified: true)
  _ = try await engine.reconcile(hidden: true, exceptions: ["a"], qualified: true)
  let pending = Task { try await engine.reconcile(hidden: true, qualified: true) }
  try await Task.sleep(for: .milliseconds(100))
  let start = ContinuousClock.now
  await engine.invalidatePendingSuppression()
  let result = try await pending.value
  #expect(!result.wrote)
  #expect(ContinuousClock.now - start < .milliseconds(500))
  #expect(await store.value.flags(for: "a") == 7)
  _ = try await engine.restore()
}
