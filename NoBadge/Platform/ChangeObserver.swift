import AppKit
import Darwin
import Foundation
import NoBadgeCore

@MainActor final class ChangeObserver {
  private var sources: [DispatchSourceFileSystemObject] = []
  enum Change { case event, poll }
  private var timer: Timer?
  private var running = false
  private var interval: TimeInterval
  private var debounce: Task<Void, Never>?
  private var systemBadgeToken: NSObjectProtocol?
  private let systemBadges: Bool
  private let changed: @MainActor (Change) -> Void
  init(systemBadges: Bool = false, interval: TimeInterval = 1, changed: @escaping @MainActor (Change) -> Void) {
    self.interval = max(1, interval)
    self.systemBadges = systemBadges
    self.changed = changed
  }
  func start(watchingFolders: [URL]? = nil) {
    stop()
    running = true
    if systemBadges {
      systemBadgeToken = DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("com.apple.systempreferences.refreshdocktile"),
        object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.schedule() } }
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folders = watchingFolders ?? [
      home.appendingPathComponent("Library/DoNotDisturb/DB"),
      FileNotificationStore.currentURL.deletingLastPathComponent(),
    ]
    for folder in folders {
      let fd = open(folder.path, O_EVTONLY)
      guard fd >= 0 else { continue }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
      source.setEventHandler { [weak self] in Task { @MainActor in self?.schedule() } }
      source.setCancelHandler { close(fd) }
      source.resume()
      sources.append(source)
    }
    schedulePolling()
  }
  func setInterval(_ seconds: TimeInterval) {
    interval = max(1, seconds)
    if running { schedulePolling() }
  }
  private func schedulePolling() {
    timer?.invalidate()
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.running else { return }
        self.changed(.poll)
      }
    }
    timer.tolerance = min(0.1, interval * 0.05)
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
  private func schedule() {
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      self?.changed(.event)
    }
  }
  func stop() {
    running = false
    if let systemBadgeToken { DistributedNotificationCenter.default().removeObserver(systemBadgeToken) }
    systemBadgeToken = nil
    debounce?.cancel()
    debounce = nil
    sources.forEach { $0.cancel() }
    sources = []
    timer?.invalidate()
    timer = nil
  }
}
