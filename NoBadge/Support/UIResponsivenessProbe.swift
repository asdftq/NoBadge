import AppKit

/// Opt-in, local-only QA measurements. No timer or file is created in normal use.
@MainActor final class UIResponsivenessProbe {
  private let destination: URL
  private var timer: Timer?
  private var last: TimeInterval = 0
  private var gaps: [Double] = []
  private var placements: [[String: Any]] = []
  init(folder: URL) { destination = folder.appendingPathComponent("ui-measurement.json") }
  func presented(_ window: NSWindow, on screen: NSScreen?) {
    guard CommandLine.arguments.contains("--measure-ui") else { return }
    func values(_ rect: NSRect) -> [Double] {
      [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
    }
    placements.append([
      "window": values(window.frame), "visibleScreen": values(screen?.visibleFrame ?? .zero),
      "contained": screen.map { $0.visibleFrame.contains(window.frame) } ?? false,
    ])
    guard timer == nil else { return }
    last = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let now = ProcessInfo.processInfo.systemUptime
        self.gaps.append((now - self.last) * 1000)
        self.last = now
      }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
  func windowClosed() {
    guard let timer else { return }
    timer.invalidate()
    self.timer = nil
    let sorted = gaps.sorted()
    let report: [String: Any] = [
      "kind": "main-run-loop-60hz-opportunity-gaps-not-render-frame-times",
      "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "",
      "samples": sorted.count,
      "maximumMilliseconds": sorted.last ?? 0,
      "p99Milliseconds": sorted.isEmpty
        ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))],
      "gapsOver50ms": sorted.filter { $0 > 50 }.count,
      "gapsOver100ms": sorted.filter { $0 > 100 }.count,
      "placements": placements,
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    {
      try? data.write(to: destination, options: .atomic)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    gaps = []
    placements = []
  }
}
