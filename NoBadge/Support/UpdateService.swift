import AppKit
import Foundation
import Sparkle

@MainActor final class UpdateService: NSObject, SPUUpdaterDelegate {
  private weak var model: AppModel?
  private var controller: SPUStandardUpdaterController?
  private let lifecycle = LifecycleCoordinator()
  private var pendingInstall: (() -> Void)?
  let configured: Bool
  init(model: AppModel) {
    self.model = model
    let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(
      URL.init(string:))
    let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    configured =
      !BuildDistribution.isSourceBuild
      && feed?.scheme == "https" && feed?.host != nil && feed?.user == nil && feed?.password == nil
      && key.flatMap { Data(base64Encoded: $0) }?.count == 32
    super.init()
    guard configured else { return }
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    controller?.updater.automaticallyChecksForUpdates = model.settings.automaticUpdateChecks
    controller?.updater.automaticallyDownloadsUpdates = false
    controller?.updater.sendsSystemProfile = false
    controller?.updater.updateCheckInterval = 24 * 3600
    do { try controller?.updater.start() } catch {
      model.errorNotice = L("Updates are temporarily unavailable.")
    }
    model.restorationCompleted = { [weak self] in self?.continuePendingInstall() }
    assert(
      responds(
        to: NSSelectorFromString("updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")))
  }
  func check() {
    if BuildDistribution.isSourceBuild {
      NSWorkspace.shared.open(BuildDistribution.sourceURL)
      return
    }
    guard let controller else {
      let alert = NSAlert()
      alert.messageText = L("Download purchased updates")
      alert.informativeText = L(
        "Get the latest download from Lemon Squeezy My Orders using the email address on your receipt. NoBadge does not check for updates or download files automatically.")
      alert.addButton(withTitle: L("Open My Orders"))
      alert.addButton(withTitle: L("Cancel"))
      if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(string: "https://app.lemonsqueezy.com/my-orders")!)
      }
      return
    }
    controller.checkForUpdates(nil)
  }
  func setAutomaticChecks(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
    controller?.updater.sendsSystemProfile = false
  }
  @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    pendingInstall = installHandler
    guard let model else { return true }
    Task {
      if await lifecycle.restore(model) {
        continuePendingInstall()
      } else {
        model.resumeAfterCancelledQuit()
        model.errorNotice = L("Restore previous badge settings before installing the update.")
      }
    }
    return true
  }
  private func continuePendingInstall() {
    guard pendingInstall != nil else { return }
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let callback = self.pendingInstall else { return }
        self.pendingInstall = nil
        callback()
      }
    }
  }
}
