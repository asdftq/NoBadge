import Foundation

/// Local, bounded usage counters. No app IDs, Focus names, ratings, or analytics.
public struct ReviewEligibility: Codable, Equatable, Sendable {
  public var firstUse: Date
  public private(set) var completedDays: Set<String> = []
  public private(set) var lastAttempt: Date?
  public private(set) var lastVersion: String?

  public init(firstUse: Date) { self.firstUse = firstUse }

  public mutating func completedFocus(start: Date, end: Date) {
    guard end.timeIntervalSince(start) >= 15 * 60, end >= firstUse else { return }
    // Three distinct UTC days, not three rapid toggles or an app launch count.
    guard completedDays.count < 3 else { return }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.dateComponents([.year, .month, .day], from: end)
    completedDays.insert("\(day.year!)-\(day.month!)-\(day.day!)")
  }

  public func isEligible(now: Date, version: String) -> Bool {
    guard now.timeIntervalSince(firstUse) >= 7 * 86400,
      completedDays.count >= 3, lastVersion != version
    else { return false }
    if let lastAttempt, now.timeIntervalSince(lastAttempt) < 120 * 86400 { return false }
    return true
  }

  public mutating func recordAttempt(now: Date, version: String) {
    lastAttempt = now
    lastVersion = version
    completedDays.removeAll()
  }
}

/// A success is a verified hide followed by a verified restore after Focus ends.
/// Pauses, manual hiding, errors, shutdown, and permission failures cancel the cycle.
public struct ReviewExperience: Sendable {
  public private(set) var startedAt: Date?
  public private(set) var sessionHadFailure = false
  public init() {}

  public mutating func observe(
    automatic: Bool, focusActive: Bool, badgesHidden: Bool, restored: Bool, now: Date
  ) -> Date? {
    guard automatic, !sessionHadFailure else {
      startedAt = nil
      return nil
    }
    if focusActive && badgesHidden {
      if startedAt == nil { startedAt = now }
      return nil
    }
    let completedStart = !focusActive && restored ? startedAt : nil
    startedAt = nil
    return completedStart
  }

  public mutating func cancel() { startedAt = nil }
  public mutating func fail() {
    startedAt = nil
    sessionHadFailure = true
  }
}
