import AppKit
import Carbon
import NoBadgeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
  let model = AppModel()
  private var lock: SingleInstanceLock?
  private var item: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var onboardingWindow: NSWindow?
  private var activationWindow: NSWindow?
  private var workspaceTokens: [NSObjectProtocol] = []
  private var clockToken: NSObjectProtocol?
  private var updater: UpdateService?
  private var quitting = false
  private var systemTermination = false
  private let lifecycle = LifecycleCoordinator()
  private lazy var uiProbe = UIResponsivenessProbe(folder: model.folder)
  private var lastLoggedState = ""
  private var menuBarIcon = MenuBarIcon()
  private lazy var logger = DiagnosticLogger(
    root: model.folder, version: model.version, build: model.build)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    // A read-only installer is not a stable location for TCC or a login item.
    // Stop before taking the production lock, observing Focus or changing badges.
    let volume = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
    if volume?.volumeIsReadOnly == true {
      let alert = NSAlert()
      alert.messageText = L("Install NoBadge first")
      alert.informativeText = L(
        "Drag NoBadge to Applications in the installer window, then open the copy in Applications. Complete the access guide from the installed app.")
      alert.addButton(withTitle: L("Show installer"))
      alert.addButton(withTitle: L("Quit"))
      if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
      }
      NSApp.terminate(nil)
      return
    }
    do { lock = try SingleInstanceLock(folder: model.folder) } catch {
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.asdftq.nobadge")
        .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
        .activate()
      NSApp.terminate(nil)
      return
    }
    configureMenus()
    item = NSStatusBar.system.statusItem(withLength: 24)
    let statusMenu = NSMenu()
    statusMenu.autoenablesItems = false
    statusMenu.delegate = self
    item.menu = statusMenu
    model.showSettings = { [weak self] in self?.openSettings() }
    model.showOnboarding = { [weak self] in self?.openOnboarding() }
    model.showLicense = { [weak self] in self?.openActivation() }
    model.quit = { [weak self] in self?.requestTermination() }
    model.stateChanged = { [weak self] in self?.updateStatus() }
    model.languageChanged = { [weak self] in
      self?.configureMenus()
      self?.settingsWindow?.title = L("NoBadge Settings")
    }
    workspaceTokens.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.model.reviews.interrupted()
          self?.model.observer.stop()
        }
      })
    workspaceTokens.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.model.observer.start()
          self?.model.requestRefresh(force: true)
        }
      })
    workspaceTokens.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
      ) { [weak self] _ in Task { @MainActor in self?.systemTermination = true } })
    clockToken = NotificationCenter.default.addObserver(
      forName: .NSSystemClockDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.model.systemClockChanged() }
    }
    updater = UpdateService(model: model)
    model.updatesConfigured = updater?.configured ?? false
    model.checkUpdates = { [weak self] in self?.updater?.check() }
    model.updateChecksChanged = { [weak self] enabled in self?.updater?.setAutomaticChecks(enabled)
    }
    updateStatus()
    model.start()
    let event = NSAppleEventManager.shared().currentAppleEvent
    let atLogin =
      event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    if !model.license.canUse {
      openActivation()
    } else if model.settings.needsSetup {
      openOnboarding()
    } else if !atLogin && !CommandLine.arguments.contains("--background") {
      openSettings()
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let title = NSMenuItem(title: model.title, action: nil, keyEquivalent: "")
    title.isEnabled = false
    menu.addItem(title)
    if !model.settings.needsSetup {
      let summary = NSMenuItem(title: model.focusSummary, action: nil, keyEquivalent: "")
      summary.isEnabled = false
      menu.addItem(summary)
      if model.phase == .paused || (model.phase == .hidden && model.settings.manualHideUntil != nil) {
        let deadline = NSMenuItem(title: model.subtitle, action: nil, keyEquivalent: "")
        deadline.isEnabled = false
        menu.addItem(deadline)
      }
    }
    menu.addItem(.separator())
    let primary = menu.addItem(
      withTitle: model.primaryLabel, action: #selector(primaryAction), keyEquivalent: "")
    primary.target = self
    primary.isEnabled = !model.isBusy
    if !model.settings.needsSetup {
      let automatic = menu.addItem(
        withTitle: L("Hide automatically during Focus"), action: #selector(toggleAutomatic),
        keyEquivalent: "")
      automatic.target = self
      automatic.state = model.settings.automationEnabled ? .on : .off
      automatic.isEnabled = model.setupReady
    }
    menu.addItem(.separator())
    let open = menu.addItem(
      withTitle: L("Open NoBadge"), action: #selector(openMainWindow), keyEquivalent: "")
    open.target = self
    let settings = menu.addItem(
      withTitle: L("Settings"), action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(.separator())
    let quit = menu.addItem(
      withTitle: L("Restore & Quit"), action: #selector(requestTermination), keyEquivalent: "q")
    quit.target = self
  }
  @objc private func primaryAction() { model.primaryAction() }
  @objc private func toggleAutomatic() { model.setAutomation(!model.settings.automationEnabled) }
  @objc private func openMainWindow() {
    if !model.license.canUse {
      openActivation()
    } else if model.settings.needsSetup || (model.accessChecked && !model.hasAccess) {
      model.reviewSetup()
    } else {
      openSettings()
    }
  }
  func applicationDidBecomeActive(_ notification: Notification) {
    guard lock != nil, !quitting else { return }
    model.requestRefresh(force: true)
    model.license.refreshIfNeeded()
  }
  func applicationDidResignActive(_ notification: Notification) {
    guard lock != nil else { return }
    model.reviews.cancelRequest()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    guard lock != nil, !quitting else { return false }
    // Spotlight/Finder reopen must never anchor to a hidden/offscreen status item.
    openMainWindow()
    return true
  }
  private func updateStatus() {
    if model.phase != .ready { model.showReviewInvitation = false }
    if [.access, .error, .recovery, .unsupported, .focusUnavailable].contains(model.phase) {
      model.reviews.failed()
    }
    considerReview()
    let iconChanged = menuBarIcon.update(phase: model.phase)
    if iconChanged || item?.button?.image == nil {
      let image = NSImage(systemSymbolName: menuBarIcon.symbol, accessibilityDescription: nil)
      image?.isTemplate = true
      item?.button?.image = image
    }
    let signature = String(describing: model.phase) + "/" + String(model.hiddenCount) + "/" + model.failureDiagnostic + "/" + menuBarIcon.symbol
    if signature != lastLoggedState {
      lastLoggedState = signature
      let state = String(describing: model.phase), count = model.hiddenCount, failure = model.failureDiagnostic
      let symbol = menuBarIcon.symbol
      Task { await logger.record(state: state, count: count, failure: failure, statusSymbol: symbol) }
    }
    item?.button?.toolTip = "NoBadge — " + model.title
    item?.button?.setAccessibilityLabel("NoBadge — " + model.title)
  }
  private func considerReview() {
    model.reviews.consider(
      version: model.version,
      onInvitation: { [weak self] in
        self?.model.showReviewInvitation = true
      }
    ) { [weak self] in
      guard let self else { return false }
      return !self.quitting && NSApp.isActive && self.settingsWindow?.isKeyWindow == true
        && self.settingsWindow?.attachedSheet == nil && self.onboardingWindow?.isVisible != true
        && self.model.phase == .ready && !self.model.isBusy && self.model.errorNotice == nil
        && self.model.settingsSection == .general
        && self.model.focus.activeIDs?.isEmpty == true
    }
  }
  private func present(_ window: NSWindow, newlyCreated: Bool) {
    let screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main ?? NSScreen.screens.first
    if let screen,
      newlyCreated || window.screen != screen
        || !WindowPlacement.fits(window.frame, in: screen.visibleFrame)
    {
      window.setFrame(
        WindowPlacement.centered(size: window.frame.size, in: screen.visibleFrame), display: false)
    }
    window.collectionBehavior.insert(.moveToActiveSpace)
    window.makeKeyAndOrderFront(nil)
    uiProbe.presented(window, on: screen)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func openSettings() {
    guard model.license.canUse else { openActivation(); return }
    if model.settings.needsSetup {
      openOnboarding()
      return
    }
    let created = settingsWindow == nil
    if created {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = L("NoBadge Settings")
      window.contentMinSize = NSSize(width: 680, height: 560)
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
      settingsWindow = window
    }
    present(settingsWindow!, newlyCreated: created)
    considerReview()
  }
  func openOnboarding() {
    guard model.license.canUse else { openActivation(); return }
    let created = onboardingWindow == nil
    if created {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "NoBadge"
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(
        rootView: OnboardingView(
          model: model,
          done: { [weak self] in
            self?.onboardingWindow?.close()
            if self?.model.settings.needsSetup == false { self?.openSettings() }
          }))
      onboardingWindow = window
    }
    present(onboardingWindow!, newlyCreated: created)
  }
  private func openActivation() {
    let created = activationWindow == nil
    if created {
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 556, height: 430),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "NoBadge"
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: ActivationWindowView(model: model) { [weak self] in
        self?.activationWindow?.close()
        self?.openMainWindow()
      })
      activationWindow = window
    }
    present(activationWindow!, newlyCreated: created)
  }
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    uiProbe.windowClosed()
    model.reviews.cancelRequest()
    Task { await ApplicationIcons.shared.clear() }
    if window === settingsWindow {
      window.contentViewController = nil
      window.contentView = nil
      settingsWindow = nil
    }
    if window === onboardingWindow {
      window.contentView = nil
      onboardingWindow = nil
    }
    if window === activationWindow {
      window.contentView = nil
      activationWindow = nil
    }
  }
  private func configureMenus() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: L("Open NoBadge"), action: #selector(openMainWindow), keyEquivalent: "o")
    appMenu.addItem(withTitle: L("Settings"), action: #selector(openSettings), keyEquivalent: ",")
    appMenu.addItem(withTitle: BuildDistribution.isSourceBuild ? L("Source & updates") : L("Check for Updates"), action: #selector(checkForUpdates), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: L("Restore & Quit"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let editItem = NSMenuItem(title: L("Edit"), action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: L("Edit"))
    editMenu.addItem(withTitle: L("Undo"), action: Selector("undo:"), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: L("Redo"), action: Selector("redo:"), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    menu.addItem(editItem)
    let windowItem = NSMenuItem(title: L("Window"), action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: L("Window"))
    windowMenu.addItem(
      withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    menu.addItem(windowItem)
    NSApp.windowsMenu = windowMenu
    NSApp.mainMenu = menu
  }
  @objc private func checkForUpdates() { model.checkForUpdates() }
  @objc private func requestTermination() {
    // terminateLater enters a nested AppKit loop. Calling terminate while a Swift
    // MainActor job is still running prevents the asynchronous restore job running.
    RunLoop.main.perform(inModes: [.common]) {
      MainActor.assumeIsolated { NSApp.terminate(nil) }
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard lock != nil else { return .terminateNow }
    guard !quitting else { return .terminateLater }
    quitting = true
    model.reviews.interrupted()
    Task {
      let restored = await lifecycle.restore(model)
      if restored || systemTermination {
        lock?.release()
        NSApp.reply(toApplicationShouldTerminate: true)
      } else {
        // Leave the Swift executor before entering AppKit's nested modal loop.
        // An in-flight restoration must be able to finish while the alert is open.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
          MainActor.assumeIsolated { self?.presentTerminationFailure() }
        }
      }
    }
    return .terminateLater
  }
  private func presentTerminationFailure() {
    let alert = NSAlert()
    alert.messageText = L("Some badge settings still need restoring")
    alert.informativeText = L(
      "Retry restoration or keep NoBadge open. Quitting anyway may leave some badges turned off; open NoBadge again to recover."
    )
    alert.addButton(withTitle: L("Retry restoration"))
    alert.addButton(withTitle: L("Keep open"))
    alert.addButton(withTitle: L("Quit anyway"))
    let response = alert.runModal()
    if response == .alertThirdButtonReturn {
      lock?.release()
      NSApp.reply(toApplicationShouldTerminate: true)
    } else {
      NSApp.reply(toApplicationShouldTerminate: false)
      quitting = false
      model.resumeAfterCancelledQuit()
      if response == .alertFirstButtonReturn { requestTermination() }
    }
  }
  func applicationWillTerminate(_ notification: Notification) {
    model.observer.stop()
    lock?.release()
    workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    workspaceTokens = []
    if let clockToken { NotificationCenter.default.removeObserver(clockToken) }
    clockToken = nil
    if let item { NSStatusBar.system.removeStatusItem(item) }
  }
}
