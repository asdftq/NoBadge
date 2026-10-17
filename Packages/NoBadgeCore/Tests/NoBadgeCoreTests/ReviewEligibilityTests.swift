import Foundation
import Testing

@testable import NoBadgeCore

private let firstUse = Date(timeIntervalSince1970: 1_800_000_000)
private func earned() -> ReviewEligibility {
  var policy = ReviewEligibility(firstUse: firstUse)
  for day in 1...3 {
    let start = firstUse.addingTimeInterval(Double(day) * 86400)
    policy.completedFocus(start: start, end: start.addingTimeInterval(900))
  }
  return policy
}

@Test func reviewNeedsSevenDaysAndThreeDistinctSuccessfulDays() {
  var policy = ReviewEligibility(firstUse: firstUse)
  let now = firstUse.addingTimeInterval(8 * 86400)
  #expect(!policy.isEligible(now: now, version: "1.0"))
  for _ in 0..<10 { policy.completedFocus(start: now, end: now.addingTimeInterval(900)) }
  #expect(policy.completedDays.count == 1)
  #expect(!policy.isEligible(now: now, version: "1.0"))
  #expect(!earned().isEligible(now: firstUse.addingTimeInterval(6 * 86400), version: "1.0"))
  #expect(earned().isEligible(now: now, version: "1.0"))
}

@Test func shortOrBackwardsSessionsNeverEarnAReview() {
  var policy = ReviewEligibility(firstUse: firstUse)
  policy.completedFocus(start: firstUse, end: firstUse.addingTimeInterval(899))
  policy.completedFocus(start: firstUse, end: firstUse.addingTimeInterval(-900))
  #expect(policy.completedDays.isEmpty)
}

@Test func attemptsSurviveRelaunchAndNeedNewVersionUsageAndCooldown() throws {
  let attempt = firstUse.addingTimeInterval(8 * 86400)
  var policy = earned()
  policy.recordAttempt(now: attempt, version: "1.0")
  policy = try JSONDecoder().decode(ReviewEligibility.self, from: JSONEncoder().encode(policy))
  #expect(policy.completedDays.isEmpty)
  for day in 1...3 {
    let start = attempt.addingTimeInterval(Double(day) * 86400)
    policy.completedFocus(start: start, end: start.addingTimeInterval(900))
  }
  #expect(!policy.isEligible(now: attempt.addingTimeInterval(119 * 86400), version: "1.1"))
  #expect(!policy.isEligible(now: attempt.addingTimeInterval(121 * 86400), version: "1.0"))
  #expect(policy.isEligible(now: attempt.addingTimeInterval(120 * 86400), version: "1.1"))
}

@Test func onlyFocusEndWithConfirmedRestorationCompletesACycle() {
  var experience = ReviewExperience()
  #expect(
    experience.observe(
      automatic: true, focusActive: true, badgesHidden: true,
      restored: false, now: firstUse) == nil)
  #expect(
    experience.observe(
      automatic: true, focusActive: true, badgesHidden: true,
      restored: false, now: firstUse.addingTimeInterval(30)) == nil)
  #expect(
    experience.observe(
      automatic: true, focusActive: false, badgesHidden: false,
      restored: true, now: firstUse.addingTimeInterval(900)) == firstUse)
  #expect(
    experience.observe(
      automatic: true, focusActive: false, badgesHidden: false,
      restored: true, now: firstUse.addingTimeInterval(1000)) == nil)
}

@Test func manualPauseFailureAndInterruptionCannotEarnAReview() {
  for interruption in 0..<3 {
    var experience = ReviewExperience()
    _ = experience.observe(
      automatic: true, focusActive: true, badgesHidden: true,
      restored: false, now: firstUse)
    if interruption == 0 { experience.fail() }
    if interruption == 1 { experience.cancel() }
    if interruption == 2 {
      _ = experience.observe(
        automatic: false, focusActive: true, badgesHidden: false,
        restored: true, now: firstUse.addingTimeInterval(900))
    }
    #expect(
      experience.observe(
        automatic: true, focusActive: false, badgesHidden: false,
        restored: true, now: firstUse.addingTimeInterval(1800)) == nil)
  }
}

@Test func failureSuppressesTheRestOfTheProcessSession() {
  var experience = ReviewExperience()
  experience.fail()
  _ = experience.observe(
    automatic: true, focusActive: true, badgesHidden: true,
    restored: false, now: firstUse)
  #expect(experience.startedAt == nil)
  #expect(experience.sessionHadFailure)
}
