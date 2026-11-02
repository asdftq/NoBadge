import Foundation

/// The timeout returns to AppKit without cancelling an in-flight narrow restoration.
@MainActor final class LifecycleCoordinator {
  private var pending: [UUID: CheckedContinuation<Bool, Never>] = [:]
  private var timers: [UUID: Task<Void, Never>] = [:]
  func restore(_ model: AppModel) async -> Bool {
    let id = UUID()
    return await withCheckedContinuation { continuation in
      pending[id] = continuation
      Task { self.finish(id, success: await model.prepareToQuit()) }
      timers[id] = Task {
        // Allow the old process exit (5s), launchd restart deferral (up to 10s)
        // and verified readback before presenting a quit failure.
        try? await Task.sleep(for: .seconds(20))
        guard !Task.isCancelled else { return }
        self.finish(id, success: false)
      }
    }
  }
  private func finish(_ id: UUID, success: Bool) {
    guard let continuation = pending.removeValue(forKey: id) else { return }
    timers.removeValue(forKey: id)?.cancel()
    continuation.resume(returning: success)
  }
}
