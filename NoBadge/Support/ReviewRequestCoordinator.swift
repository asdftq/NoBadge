import AppKit
import NoBadgeCore

@MainActor
final class ReviewRequestCoordinator {
  private let url: URL
  private var eligibility: ReviewEligibility
  private var experience = ReviewExperience()
  private var pending: Task<Void, Never>?
  private var requestID: UUID?
  private let enabled: Bool

  init(folder: URL, labOnly: Bool) {
    url = folder.appendingPathComponent("review-history.json")
    enabled = !labOnly
    eligibility =
      (try? Data(contentsOf: url)).flatMap {
        try? JSONDecoder().decode(ReviewEligibility.self, from: $0)
      } ?? ReviewEligibility(firstUse: .now)
    if enabled { _ = save() }
  }

  func reconciled(automatic: Bool, focusActive: Bool, hidden: Bool, restored: Bool) {
    guard enabled else { return }
    let now = Date()
    if let start = experience.observe(
      automatic: automatic, focusActive: focusActive, badgesHidden: hidden,
      restored: restored, now: now)
    {
      eligibility.completedFocus(start: start, end: now)
      _ = save()
    }
  }

  func failed() {
    experience.fail()
    cancelRequest()
  }
  func interrupted() {
    experience.cancel()
    cancelRequest()
  }
  func cancelRequest() {
    pending?.cancel()
    pending = nil
    requestID = nil
  }

  func consider(
    version: String, onInvitation: @escaping @MainActor () -> Void,
    isAppropriate: @escaping @MainActor () -> Bool
  ) {
    guard enabled, !experience.sessionHadFailure, isAppropriate() else {
      cancelRequest()
      return
    }
    guard pending == nil, eligibility.isEligible(now: .now, version: version) else { return }
    let id = UUID()
    requestID = id
    pending = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      guard let self else { return }
      defer {
        if self.requestID == id {
          self.pending = nil
          self.requestID = nil
        }
      }
      guard !Task.isCancelled, !self.experience.sessionHadFailure, isAppropriate(),
        self.eligibility.isEligible(now: .now, version: version)
      else { return }
      self.eligibility.recordAttempt(now: .now, version: version)
      // Persist before showing the invitation; relaunch must not repeat it.
      guard self.save() else { return }
      onInvitation()
    }
  }

  @discardableResult private func save() -> Bool {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(eligibility).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      return true
    } catch {
      experience.fail()
      return false
    }
  }
}
