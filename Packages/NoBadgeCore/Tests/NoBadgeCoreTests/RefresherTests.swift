import Foundation
import Testing

@testable import NoBadgeCore

private actor Commands {
  var statuses: [Int32]
  var paths: [String] = []
  init(_ statuses: [Int32]) { self.statuses = statuses }
  func run(_ path: String, _: [String]) -> Int32 {
    paths.append(path)
    return statuses.removeFirst()
  }
}
@Test func absentDaemonDuringRestartDoesNotMakeRestorationFail() async throws {
  let commands = Commands([1, 1])
  let refresher = UserNotificationRefresher { path, args in await commands.run(path, args) }
  try await refresher.refresh()
  #expect(await commands.paths == ["/usr/bin/killall", "/usr/bin/pgrep"])
}
@Test func refreshFailureWithRunningDaemonStillFailsClosed() async throws {
  let commands = Commands([1, 0])
  let refresher = UserNotificationRefresher { path, args in await commands.run(path, args) }
  await #expect(throws: EngineError.refreshFailed(1)) { try await refresher.refresh() }
}
@Test func daemonProbeFailureDoesNotPretendRefreshSucceeded() async throws {
  let commands = Commands([1, 2])
  let refresher = UserNotificationRefresher { path, args in await commands.run(path, args) }
  await #expect(throws: EngineError.refreshFailed(1)) { try await refresher.refresh() }
}
@Test func successfulRefreshNeedsNoExtraProbe() async throws {
  let commands = Commands([0])
  let refresher = UserNotificationRefresher { path, args in await commands.run(path, args) }
  try await refresher.refresh()
  #expect(await commands.paths == ["/usr/bin/killall"])
}

private actor DaemonProcesses {
  var snapshots: [Set<Int32>]
  var reads = 0
  init(_ snapshots: [Set<Int32>]) { self.snapshots = snapshots }
  func next() -> Set<Int32> {
    reads += 1
    return snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
  }
}
@Test func refreshWaitsForOldDaemonButNotItsReplacement() async throws {
  let commands = Commands([0])
  let processes = DaemonProcesses([[42], [42, 43], [43]])
  let refresher = UserNotificationRefresher(
    command: { path, args in await commands.run(path, args) },
    processIDs: { await processes.next() }, exitAttempts: 3, exitDelay: .zero)
  try await refresher.refresh()
  #expect(await processes.reads == 3)
  #expect(await commands.paths == ["/usr/bin/killall"])
}
@Test func oldDaemonThatDoesNotExitKeepsRefreshFailed() async throws {
  let commands = Commands([0])
  let processes = DaemonProcesses([[42]])
  let refresher = UserNotificationRefresher(
    command: { path, args in await commands.run(path, args) },
    processIDs: { await processes.next() }, exitAttempts: 3, exitDelay: .zero)
  await #expect(throws: EngineError.refreshFailed(Int32(ETIMEDOUT))) {
    try await refresher.refresh()
  }
  #expect(await processes.reads == 4)
}
