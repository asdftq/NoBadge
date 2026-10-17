import AppKit
import Foundation
import NoBadgeCore
import ServiceManagement
import SwiftUI

enum DisplayPhase: Equatable {
  case setup, ready, hidden, paused, off, working, access, unsupported, focusUnavailable, recovery,
    error, license
}
@MainActor final class AppModel: ObservableObject {
  @Published var settings = UserSettings()
  @Published var phase: DisplayPhase = .setup
  @Published var settingsSection: SettingsSection = .general
  @Published var hiddenCount = 0
  @Published var focus: FocusObservation = .unknown("starting")
  @Published var applications: [AppEntry] = []
  @Published var detail = ""
  @Published var hasAccess = false
  @Published var focusAvailable = false
  var setupReady: Bool { hasAccess && focusAvailable && qualified && license.canUse }
  let license = LicenseService()
  @Published var isBusy = false
  @Published var onboardingStep = 0
  @Published var loginRequested = false
  @Published var errorNotice: String?
  let labOnly: Bool
  let folder: URL
  let build: String
  let version: String
  let qualified: Bool
  let compatibilityProfile: String?
  let systemSettingsSupported: Bool
  let engine: BadgeEngine
  let systemBadges: SystemSettingsBadges?
  private var lastSystemBadgeSignature: String?
  private let reader = PlatformReader()
  private let catalog = ApplicationCatalog()
  private var catalogIDs: Set<String> = []
  @Published private(set) var accessChecked = false
  private let settingsURL: URL
  private let settingsStore: SettingsStore
  private var settingsSaveTask: Task<Bool, Never>?
  private var settingsRevision: UInt64 = 0
  private var inputs: PlatformInputs?
  private var lastSignature: String?
  private var processing = false
  private var refreshTask: Task<Void, Never>?
  private var interruptionTask: Task<Void, Never>?
  private var requested = false
  private var forceRequested = false
  private var stopped = false
  private var safetySuspended = false
  // A failed explicit restore must survive unchanged platform snapshots. Otherwise
  // the cached-state fast path can display Off while the owned journal is pending.
  private var restorationRequired = false
  private var startupRecoveryChecked = false
  private var unknownSince: ContinuousClock.Instant?
  private var graceTask: Task<Void, Never>?
  private var deadlineTask: Task<Void, Never>?
  var showSettings: (() -> Void)?
  var showOnboarding: (() -> Void)?
  var showLicense: (() -> Void)?
  var stateChanged: (() -> Void)?
  var quit: (() -> Void)?
  var restorationCompleted: (() -> Void)?
  var checkUpdates: (() -> Void)?
  var updateChecksChanged: ((Bool) -> Void)?
  var languageChanged: (() -> Void)?
  @Published var updatesConfigured = false
  @Published var showReviewInvitation = false
  lazy var observer = ChangeObserver(systemBadges: systemSettingsSupported) {
    [weak self] in self?.requestRefresh()
  }
  lazy var reviews = ReviewRequestCoordinator(folder: folder, labOnly: labOnly)
  func openFeedback() {
    showReviewInvitation = false
    NSWorkspace.shared.open(URL(string: "https://asdftq.github.io/nobadge/feedback.html")!)
  }

  init() {
    #if DEBUG
      labOnly = true
    #else
      labOnly = CommandLine.arguments.contains("--lab-only")
    #endif
    folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/" + (labOnly ? "NoBadge-Lab" : "NoBadge"))
    settingsURL = folder.appendingPathComponent("settings.json")
    settingsStore = SettingsStore(url: settingsURL)
    let runningBuild = currentOSBuild()
    build = runningBuild
    version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"
    let manifest = Bundle.main.url(forResource: "Compatibility", withExtension: "json").flatMap {
      try? Data(contentsOf: $0)
    }.flatMap { try? JSONDecoder().decode(CompatibilityManifest.self, from: $0) }
    let profile = manifest?.profile(
      for: ProcessInfo.processInfo.operatingSystemVersion, osBuild: runningBuild,
      architecture: currentArchitecture())
    compatibilityProfile = profile?.id
    systemSettingsSupported = profile?.supportsSystemSettingsBadges == true
    qualified = profile != nil
    engine = BadgeEngine(
      store: FileNotificationStore(url: FileNotificationStore.currentURL),
      journals: FileJournalStore(
        url: folder.appendingPathComponent("recovery/active-session.json")),
      refresher: UserNotificationRefresher(), version: version, osBuild: build,
      compatibleRecoveryBuilds: Set(
        manifest?.qualifiedTargets.filter { $0.architecture == currentArchitecture() }.map(
          \.osBuild) ?? []),
      compatibleRecoveryBuildPrefixes: profile == nil ? [] :
        manifest?.recoveryBuildPrefixes(architecture: currentArchitecture()) ?? [])
    let hasSystemRecovery = FileManager.default.fileExists(
      atPath: folder.appendingPathComponent("recovery/system-settings.json").path)
    systemBadges = profile != nil && !labOnly && (systemSettingsSupported || hasSystemRecovery) ? SystemSettingsBadges(
      journal: folder.appendingPathComponent("recovery/system-settings.json"),
      canSuppress: systemSettingsSupported) : nil
    if let data = try? Data(contentsOf: settingsURL) {
      do {
        settings = try JSONDecoder().decode(UserSettings.self, from: data)
        guard settings.schemaVersion == 1 else { throw EngineError.invalidSchema }
      } catch {
        errorNotice = L(
          "Saved settings could not be read. Your recovery information has been kept.")
        safetySuspended = true
      }
    }
    AppLocalization.language = settings.appLanguage
    if settings.setupRevision != UserSettings.currentSetupRevision {
      settings.onboardingComplete = false
      settings.setupStep = 0
    }
    settings.normalizeDeadlines(now: .now)
    onboardingStep = min(1, max(0, settings.setupStep ?? 0))
  }
  var title: String {
    switch phase {
    case .setup: L("Finish setup")
    case .ready: L("Ready for Focus")
    case .hidden: hiddenCount == 0 ? L("No supported enabled badges to hide.") : L("Hiding badges")
    case .paused: L("Showing badges")
    case .off: L("Automatic hiding is off")
    case .working: L("Updating badge settings…")
    case .access: L("Access needs attention")
    case .unsupported: L("Update NoBadge for this macOS version")
    case .focusUnavailable: L("Focus needs attention")
    case .recovery: L("Some badge settings still need restoring")
    case .error: L("Automatic hiding is paused")
    case .license: L("Activate NoBadge")
    }
  }
  var subtitle: String {
    switch phase {
    case .license: return L("Enter your purchase license key to use NoBadge.")
    case .hidden:
      if let end = settings.manualHideUntil {
        return L("Until") + " "
          + end.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
      }
      return focus.displayName + " · " + String(hiddenCount) + " " + L("supported apps")
    case .paused:
      return settings.pauseUntil.map {
        L("Until") + " "
          + $0.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
      } ?? L("Your previous settings are restored.")
    case .ready: return L("Turn on Focus as usual.")
    case .off: return L("You can still hide badges for 30 minutes.")
    default: return detail.isEmpty ? L("A quieter Dock when you focus.") : L(detail)
    }
  }
  var primaryLabel: String {
    switch phase {
    case .license: L("Activate NoBadge")
    case .setup: L("Continue setup")
    case .access: L("Fix access")
    case .unsupported: L("Check for Updates")
    case .recovery: L("Restore previous settings")
    case .error: L("Retry safely")
    case .hidden:
      settings.manualHideUntil == nil ? L("Show badges for 15 minutes") : L("Show badges now")
    case .paused: L("Resume now")
    case .focusUnavailable: L("Check Focus again")
    case .working: L("Please wait…")
    default: L("Hide for 30 minutes")
    }
  }
  func start() {
    if settings.updatePreferencesRevision == nil {
      // Earlier releases had no update feed or visible update preference.
      settings.automaticUpdateChecks = true
      settings.updatePreferencesRevision = 1
      save()
      updateChecksChanged?(true)
    }
    license.changed = { [weak self] in
      self?.objectWillChange.send()
      self?.requestRefresh(force: true)
    }
    license.start()
    observer.start()
    requestRefresh(force: true)
    scheduleDeadline()
  }
  func requestRefresh(force: Bool = false) {
    guard !stopped else { return }
    requested = true
    forceRequested = forceRequested || force
    guard !processing else {
      // A new Focus event or user choice must interrupt a pending suppression delay.
      forceRequested = true
      if interruptionTask == nil {
        interruptionTask = Task { await engine.invalidatePendingSuppression() }
      }
      return
    }
    processing = true
    refreshTask = Task {
      while requested && !stopped {
        await interruptionTask?.value
        interruptionTask = nil
        requested = false
        let force = forceRequested
        forceRequested = false
        await refresh(force: force)
      }
      processing = false
    }
  }
  private func refresh(force: Bool) async {
    guard await finishSavingSettings() else {
      do {
        _ = try await restoreAllBadges()
        hiddenCount = 0
        phase = .error
      } catch {
        phase = .recovery
        detail = error.localizedDescription
      }
      isBusy = false
      stateChanged?()
      return
    }
    guard !stopped else { return }
    guard license.canUse else {
      do {
        // Recovery and quitting always remain available without a valid license.
        _ = try await restoreAllBadges()
        hiddenCount = 0
        phase = .license
        detail = ""
      } catch {
        phase = .recovery
        restorationRequired = true
        detail = error.localizedDescription
      }
      isBusy = false
      stateChanged?()
      return
    }
    var normalized = settings
    normalized.normalizeDeadlines(now: .now)
    if normalized != settings { settings = normalized }
    guard qualified else {
      phase = .unsupported
      detail = "This macOS version or Mac architecture needs a compatible NoBadge update."
      stateChanged?()
      return
    }
    do {
      let current = try await reader.load()
      guard !stopped else { return }
      if !accessChecked { accessChecked = true }
      let access = current.focus != .unknown("focusAccessDenied")
      if hasAccess != access { hasAccess = access }
      if focus != current.focus { focus = current.focus }
      let known = current.focus.activeIDs != nil
      if focusAvailable != known { focusAvailable = known }
      let systemSignature = try await systemBadges?.signature()
      let records =
        labOnly
        ? current.notifications.records.filter { $0.id.hasPrefix("com.asdftq.nobadge.fixture.") }
        : current.notifications.records
      let identities = Set(records.map { $0.id + "|" + ($0.path ?? "") })
      if identities != catalogIDs {
        var resolved = await catalog.load(records)
        if systemSettingsSupported, !labOnly {
          let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
          if let bundle = Bundle(url: url), !resolved.contains(where: { $0.id == SystemSettingsBadges.bundleID }) {
            resolved.append(AppEntry(id: SystemSettingsBadges.bundleID,
              name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "System Settings",
              url: url, recordIDs: [SystemSettingsBadges.bundleID]))
            resolved.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
          }
        }
        guard !stopped else { return }
        if applications != resolved { applications = resolved }
        catalogIDs = identities
      }
      inputs = current
      if !startupRecoveryChecked {
        startupRecoveryChecked = true
        if try await pendingBadgeRecovery() {
          restorationRequired = true
          phase = .working
          isBusy = true
          stateChanged?()
          _ = try await restoreAllBadges()
          restorationRequired = false
          isBusy = false
        }
      }
      if settings.needsSetup {
        phase = .setup
        detail =
          focusAvailable
          ? "" : "NoBadge cannot read Focus yet. Turn on a Focus once, then check access again."
        stateChanged?()
        return
      }
      if !hasAccess {
        phase = .access
        detail = "Allow Full Disk Access to read Focus and manage badges."
        stateChanged?()
        return
      }
      if restorationRequired {
        if !isBusy { phase = .recovery }
        stateChanged?()
        return
      }
      if safetySuspended {
        phase = .error
        stateChanged?()
        return
      }
      guard force || current.signature != lastSignature || systemSignature != lastSystemBadgeSignature else {
        updateVisiblePhase()
        stateChanged?()
        return
      }
      let desired = PolicyReducer.desired(
        settings: settings, focus: current.focus, now: .now, capable: qualified,
        recoveryPending: false)
      if desired == .unknown {
        if unknownSince == nil {
          unknownSince = .now
          graceTask = Task {
            try? await Task.sleep(for: .seconds(2), clock: .continuous)
            if !Task.isCancelled { self.requestRefresh(force: true) }
          }
        }
        if unknownSince!.duration(to: .now) < .seconds(2) { return }
        _ = try await restoreAllBadges()
        hiddenCount = 0
        phase = .focusUnavailable
        detail = "NoBadge cannot read Focus right now. Manual hiding is still available."
        stateChanged?()
        return
      }
      unknownSince = nil
      graceTask?.cancel()
      graceTask = nil
      isBusy = true
      phase = .working
      stateChanged?()
      let eligible = Set(applications.flatMap(\.recordIDs))
      guard license.canUse else {
        requested = true
        return
      }
      let result = try await engine.reconcile(
        hidden: desired == .hidden, exceptions: expandedExceptions, eligibleIDs: eligible,
        qualified: qualified)
      let systemCount = try await systemBadges?.reconcile(
        hidden: desired == .hidden, excepted: expandedExceptions.contains(SystemSettingsBadges.bundleID)) ?? 0
      hiddenCount = result.hiddenCount + systemCount
      isBusy = false
      // Cache the post-write state to avoid treating our own directory event as a new transaction.
      let confirmed = try await reader.load()
      inputs = confirmed
      lastSignature = confirmed.signature
      lastSystemBadgeSignature = try await systemBadges?.signature()
      updateVisiblePhase(desired: desired)
      detail = ""
      reviews.reconciled(
        automatic: settings.automationEnabled && settings.manualHideUntil == nil
          && settings.pauseUntil == nil,
        focusActive: current.focus.activeIDs?.isEmpty == false,
        hidden: desired == .hidden && result.hiddenCount > 0,
        restored: desired == .visible && result.hiddenCount == 0)
      stateChanged?()
    } catch {
      isBusy = false
      if !accessChecked { accessChecked = true }
      let ns = error as NSError
      if ns.domain == NSCocoaErrorDomain
        && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code)
        || ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code)
      {
        hasAccess = false
        phase = .access
        detail = "Allow access to read Focus and manage badge settings."
      } else if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError {
        phase = .error
        detail = "macOS settings are not available yet. Turn on a Focus once, then check again."
      } else {
        phase = .recovery
        restorationRequired = true
        detail = error.localizedDescription
        safetySuspended = true
        // One bounded recovery attempt; never loop on a refresh failure.
        do {
          _ = try await restoreAllBadges()
          restorationRequired = false
          hiddenCount = 0
          phase = .error
        } catch { detail = error.localizedDescription }
      }
      stateChanged?()
    }
  }
  private func restoreAllBadges() async throws -> EngineResult {
    // Each independent adapter must get a recovery attempt even when another
    // path fails; keep the first failure and its journal visible to the user.
    let regular: Result<EngineResult, Error>
    do { regular = .success(try await engine.restore()) }
    catch { regular = .failure(error) }
    do { try await systemBadges?.restore() }
    catch { _ = try regular.get(); throw error }
    return try regular.get()
  }
  private func pendingBadgeRecovery() async throws -> Bool {
    let regular = try await engine.pendingRecovery()
    let system = await systemBadges?.pendingRecovery() ?? false
    return regular || system
  }
  private func updateVisiblePhase(desired: DesiredState? = nil) {
    if restorationRequired {
      phase = .recovery
      return
    }
    if !license.canUse {
      phase = .license
      return
    }
    if settings.needsSetup {
      phase = .setup
      return
    }
    if let deadline = settings.pauseUntil, deadline > Date() {
      phase = .paused
      return
    }
    let wanted =
      desired
      ?? PolicyReducer.desired(
        settings: settings, focus: focus, now: .now, capable: qualified, recoveryPending: false)
    if wanted == .hidden {
      phase = .hidden
    } else if wanted == .unknown {
      phase = .focusUnavailable
    } else {
      phase = settings.automationEnabled ? .ready : .off
    }
  }
  private func save() {
    settingsRevision += 1
    let revision = settingsRevision
    let snapshot = settings
    settingsSaveTask = Task {
      do {
        try await settingsStore.save(snapshot, revision: revision)
        return true
      } catch {
        if revision == settingsRevision {
          errorNotice = L("NoBadge could not save your settings.")
          safetySuspended = true
        }
        return false
      }
    }
  }
  private func finishSavingSettings() async -> Bool {
    while let pending = settingsSaveTask {
      let revision = settingsRevision
      let saved = await pending.value
      if revision == settingsRevision { return saved }
    }
    return true
  }
  func setSetupStep(_ step: Int) {
    onboardingStep = min(1, max(0, step))
    settings.setupRevision = UserSettings.currentSetupRevision
    settings.setupStep = onboardingStep
    save()
  }
  func completeSetup() {
    guard setupReady else { return }
    settings.setupRevision = UserSettings.currentSetupRevision
    settings.onboardingComplete = true
    settings.automationEnabled = true
    save()
    if loginRequested { setLogin(true) }
    onboardingStep = 1
    requestRefresh(force: true)
    scheduleDeadline()
  }
  func setAutomation(_ enabled: Bool) {
    guard !enabled || license.canUse else { showLicense?(); return }
    settings.automationEnabled = enabled
    settings.manualHideUntil = nil
    settings.pauseUntil = nil
    if !enabled { safetySuspended = false }
    save()
    requestRefresh(force: true)
    scheduleDeadline()
  }
  func setSelection(_ ids: Set<String>?) {
    settings.selectedFocusIDs = ids
    save()
    requestRefresh(force: true)
  }
  func isException(_ app: AppEntry) -> Bool {
    !settings.exceptionBundleIDs.isDisjoint(with: app.recordIDs.union([app.id]))
  }
  private var expandedExceptions: Set<String> {
    applications.filter(isException).reduce(settings.exceptionBundleIDs) { $0.union($1.recordIDs) }
  }
  var focusSummary: String {
    guard let ids = focus.activeIDs else {
      return accessChecked
        ? L("Focus could not be read. Check access below.") : L("Checking Focus…")
    }
    return ids.isEmpty ? L("Focus is off") : focus.displayName + " · " + L("On")
  }
  func reviewSetup() {
    onboardingStep = 0
    showOnboarding?()
  }
  func setException(_ id: String, _ enabled: Bool) {
    let ids = (applications.first { $0.id == id }?.recordIDs ?? []).union([id])
    if enabled {
      settings.exceptionBundleIDs.formUnion(ids)
    } else {
      settings.exceptionBundleIDs.subtract(ids)
    }
    save()
    requestRefresh(force: true)
  }
  func primaryAction() {
    guard license.canUse || phase == .recovery || phase == .unsupported else {
      showLicense?()
      return
    }
    switch phase {
    case .license: showLicense?()
    case .setup: showOnboarding?()
    case .access:
      onboardingStep = 0
      showOnboarding?()
    case .focusUnavailable: requestRefresh(force: true)
    case .unsupported: checkForUpdates()
    case .recovery: restoreExplicitly()
    case .error:
      safetySuspended = false
      save()
      Task {
        await engine.resetFailureBreaker()
        requestRefresh(force: true)
      }
    case .hidden:
      settings.manualHideUntil = nil
      settings.pauseUntil = Date().addingTimeInterval(900)
      save()
      requestRefresh(force: true)
      scheduleDeadline()
    case .paused:
      settings.pauseUntil = nil
      save()
      requestRefresh(force: true)
      scheduleDeadline()
    case .working: break
    default:
      settings.pauseUntil = nil
      settings.manualHideUntil = Date().addingTimeInterval(1800)
      save()
      requestRefresh(force: true)
      scheduleDeadline()
    }
  }
  private func scheduleDeadline() {
    deadlineTask?.cancel()
    let pause = settings.pauseUntil
    let manualHide = settings.manualHideUntil
    guard let end = [settings.pauseUntil, settings.manualHideUntil].compactMap({ $0 }).min() else {
      return
    }
    let seconds = max(0, end.timeIntervalSinceNow)
    deadlineTask = Task {
      try? await Task.sleep(until: .now.advanced(by: .seconds(seconds)), clock: .continuous)
      guard !Task.isCancelled else { return }
      settings.expireDeadlines(pause: pause, manualHide: manualHide)
      save()
      requestRefresh(force: true)
    }
  }
  func systemClockChanged() {
    // A clock correction must never turn a temporary choice into a longer one.
    deadlineTask?.cancel()
    settings.pauseUntil = nil
    settings.manualHideUntil = nil
    save()
    requestRefresh(force: true)
  }
  func restoreExplicitly() {
    settingsSection = .general
    restorationRequired = true
    settings.manualHideUntil = nil
    settings.pauseUntil = Date().addingTimeInterval(900)
    save()
    Task {
      isBusy = true
      phase = .working
      stateChanged?()
      do {
        _ = try await restoreAllBadges()
        restorationRequired = false
        hiddenCount = 0
        safetySuspended = false
        restorationCompleted?()
        await engine.resetFailureBreaker()
        requestRefresh(force: true)
      } catch {
        phase = .recovery
        detail = error.localizedDescription
      }
      isBusy = false
      stateChanged?()
    }
  }
  func prepareToQuit() async -> Bool {
    restorationRequired = true
    stopped = true
    observer.stop()
    graceTask?.cancel()
    deadlineTask?.cancel()
    // Drain a refresh already suspended in an await before the final restore.
    // Otherwise it could enqueue a new hide after restoration cleared the journal.
    await engine.prioritizeRestoration()
    await interruptionTask?.value
    await refreshTask?.value
    // A rapid change followed by Quit must persist the final choice before exit.
    _ = await finishSavingSettings()
    isBusy = true
    phase = .working
    stateChanged?()
    do {
      _ = try await restoreAllBadges()
      restorationRequired = false
      hiddenCount = 0
      isBusy = false
      updateVisiblePhase(desired: .visible)
      return true
    } catch {
      isBusy = false
      phase = .recovery
      detail = error.localizedDescription
      stateChanged?()
      return false
    }
  }
  func resumeAfterCancelledQuit() {
    stopped = false
    safetySuspended = true
    observer.start()
  }
  func prepareToUninstall() {
    settingsSection = .general
    restorationRequired = true
    settings.automationEnabled = false
    settings.manualHideUntil = nil
    settings.pauseUntil = nil
    save()
    Task {
      isBusy = true
      phase = .working
      stateChanged?()
      do {
        guard await finishSavingSettings() else {
          isBusy = false
          phase = .error
          stateChanged?()
          return
        }
        _ = try await restoreAllBadges()
        restorationRequired = false
        hiddenCount = 0
        if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
          try await SMAppService.mainApp.unregister()
        }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        quit?()
      } catch {
        phase = .recovery
        detail = error.localizedDescription
      }
      isBusy = false
      stateChanged?()
    }
  }
  var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
  var loginStatus: String {
    switch SMAppService.mainApp.status {
    case .enabled: L("Open at login is enabled.")
    case .requiresApproval: L("Approve NoBadge in Login Items to finish.")
    default: L("Open at login is off.")
    }
  }
  func setLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch { errorNotice = L("Login settings could not be updated.") }
    objectWillChange.send()
  }
  func openPrivacySettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
  }
  func revealApplication() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }
  func checkForUpdates() { checkUpdates?() }
  func setUpdateChecks(_ enabled: Bool) {
    settings.automaticUpdateChecks = enabled
    save()
    updateChecksChanged?(enabled)
  }
  var appLocale: Locale { Locale(identifier: settings.appLanguage.rawValue) }
  func setLanguage(_ language: AppLanguage) {
    guard settings.appLanguage != language else { return }
    // Update localization before publishing settings so open views redraw immediately.
    AppLocalization.language = language
    settings.appLanguage = language
    save()
    languageChanged?()
    stateChanged?()
  }
  private var diagnosticSummary: String {
    "NoBadge \(version)\nBundle: com.asdftq.nobadge\nOS build: \(build)\nAdapter: usernoted-badge-v1\nProfile: \(compatibilityProfile ?? "unsupported")\nCompatible OS family: \(qualified)\nState: \(phase)\nOwned count: \(hiddenCount)\nAccess: \(hasAccess)\nNo Focus names, app list, notification data, or recovery journal included.\n"
  }
  func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "NoBadge-diagnostics.txt"
    panel.allowedContentTypes = [.plainText]
    let text = diagnosticSummary
    let preview = NSAlert()
    preview.messageText = L("Review diagnostics")
    preview.informativeText =
      L(
        "The export contains only version, compatibility, state, and counts. It does not include Focus names, app lists, message data, or recovery journals."
      ) + "\n\n" + text
    preview.addButton(withTitle: L("Save…"))
    preview.addButton(withTitle: L("Cancel"))
    guard preview.runModal() == .alertFirstButtonReturn else { return }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
      errorNotice = L("Diagnostics could not be saved.")
    }
  }
}
