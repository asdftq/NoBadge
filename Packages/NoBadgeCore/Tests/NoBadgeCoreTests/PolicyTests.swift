import CoreGraphics
import Foundation
import Testing

@testable import NoBadgeCore

@Test func defaultsDoNotMutateAnActiveFocus() {
  #expect(
    PolicyReducer.desired(
      settings: .init(), focus: .known(activeIDs: ["work"], modes: []), now: .now, capable: true,
      recoveryPending: false) == .visible)
}
@Test func unknownIsNotOff() {
  var settings = UserSettings()
  settings.onboardingComplete = true
  settings.setupRevision = UserSettings.currentSetupRevision
  settings.automationEnabled = true
  #expect(
    PolicyReducer.desired(
      settings: settings, focus: .unknown("denied"), now: .now, capable: true,
      recoveryPending: false) == .unknown)
}
@Test func pauseWinsOverManualAndFocus() {
  let now = Date()
  var s = UserSettings()
  s.onboardingComplete = true
  s.setupRevision = UserSettings.currentSetupRevision
  s.automationEnabled = true
  s.pauseUntil = now.addingTimeInterval(900)
  s.manualHideUntil = now.addingTimeInterval(1800)
  #expect(
    PolicyReducer.desired(
      settings: s, focus: .known(activeIDs: ["work"], modes: []), now: now, capable: true,
      recoveryPending: false) == .visible)
}
@Test func selectedEmptyNeverMeansAll() {
  var s = UserSettings()
  s.onboardingComplete = true
  s.setupRevision = UserSettings.currentSetupRevision
  s.automationEnabled = true
  s.selectedFocusIDs = []
  #expect(
    PolicyReducer.desired(
      settings: s, focus: .known(activeIDs: ["work"], modes: []), now: .now, capable: true,
      recoveryPending: false) == .visible)
}
@Test func implausibleDeadlinesExpire() {
  let now = Date()
  var s = UserSettings()
  s.pauseUntil = now.addingTimeInterval(1000)
  s.manualHideUntil = now.addingTimeInterval(-1)
  s.normalizeDeadlines(now: now)
  #expect(s.pauseUntil == nil)
  #expect(s.manualHideUntil == nil)
}

@Test func continuousExpiryWinsOverABackwardWallClock() {
  let originalNow = Date(timeIntervalSince1970: 1_800_000_000)
  var s = UserSettings()
  s.pauseUntil = originalNow.addingTimeInterval(900)
  let scheduledPause = s.pauseUntil
  // A small backward correction leaves an otherwise plausible UTC deadline.
  s.normalizeDeadlines(now: originalNow.addingTimeInterval(600))
  #expect(s.pauseUntil != nil)
  s.expireDeadlines(pause: scheduledPause, manualHide: nil)
  #expect(s.pauseUntil == nil)
  s.manualHideUntil = originalNow.addingTimeInterval(1800)
  s.expireDeadlines(pause: nil, manualHide: s.manualHideUntil)
  #expect(s.manualHideUntil == nil)
}

@Test func staleTimerCannotCancelANewerTemporaryChoice() {
  let old = Date(timeIntervalSince1970: 1_800_000_000)
  var s = UserSettings()
  s.pauseUntil = old.addingTimeInterval(900)
  s.manualHideUntil = old.addingTimeInterval(1800)
  s.expireDeadlines(pause: old, manualHide: old)
  #expect(s.pauseUntil == old.addingTimeInterval(900))
  #expect(s.manualHideUntil == old.addingTimeInterval(1800))
}

@Test func setupProgressSurvivesRelaunchAndOldSettingsRemainReadable() throws {
  var settings = UserSettings()
  settings.setupStep = 1
  let saved = try JSONEncoder().encode(settings)
  #expect(try JSONDecoder().decode(UserSettings.self, from: saved).setupStep == 1)
  var legacy = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
  legacy.removeValue(forKey: "setupStep")
  let old = try JSONSerialization.data(withJSONObject: legacy)
  #expect(try JSONDecoder().decode(UserSettings.self, from: old).setupStep == nil)
}

@Test func oldAndUnknownLanguageSettingsFallBackToEnglishWithoutLosingPreferences() throws {
  var settings = UserSettings()
  settings.onboardingComplete = true
  settings.automationEnabled = true
  settings.exceptionBundleIDs = ["com.example.keep"]
  let legacy = try JSONEncoder().encode(settings)
  let loaded = try JSONDecoder().decode(UserSettings.self, from: legacy)
  #expect(loaded.languageCode == nil)
  #expect(loaded.appLanguage == .english)
  #expect(loaded == settings)
  var future = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
  future["languageCode"] = "future-language"
  let migrated = try JSONDecoder().decode(
    UserSettings.self, from: JSONSerialization.data(withJSONObject: future))
  #expect(migrated.appLanguage == .english)
  #expect(migrated.automationEnabled)
  #expect(migrated.exceptionBundleIDs == settings.exceptionBundleIDs)
}

@Test func explicitLanguageChoiceSurvivesRelaunch() throws {
  var settings = UserSettings()
  for language in AppLanguage.allCases {
    settings.appLanguage = language
    let loaded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
    #expect(loaded.appLanguage == language)
    #expect(loaded.languageCode == language.rawValue)
  }
}

@Test func legacyCompletedSetupRequiresTheNewPermissionWalkthrough() {
  var settings = UserSettings()
  settings.onboardingComplete = true
  settings.automationEnabled = true
  #expect(settings.needsSetup)
  #expect(
    PolicyReducer.desired(
      settings: settings, focus: .known(activeIDs: ["work"], modes: []), now: .now, capable: true,
      recoveryPending: false) == .visible)
  settings.setupRevision = UserSettings.currentSetupRevision
  #expect(!settings.needsSetup)
}
@Test func windowPlacementUsesTheChosenMonitorIncludingNegativeCoordinates() {
  let left = CGRect(x: -2560, y: 0, width: 2560, height: 1415)
  let right = CGRect(x: 0, y: 50, width: 1728, height: 1040)
  let target = WindowPlacement.centered(size: CGSize(width: 720, height: 520), in: left)
  #expect(target.midX == left.midX)
  #expect(target.midY == left.midY)
  #expect(WindowPlacement.fits(target, in: left))
  #expect(!WindowPlacement.fits(target, in: right))
  let small = CGRect(x: 100, y: -900, width: 640, height: 480)
  #expect(
    WindowPlacement.fits(
      WindowPlacement.centered(size: CGSize(width: 720, height: 520), in: small), in: small))
}
