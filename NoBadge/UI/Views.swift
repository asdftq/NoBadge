import AppKit
import NoBadgeCore
import SwiftUI

private let brand = Color.accentColor
private struct NoticeModifier: ViewModifier {
  @ObservedObject var model: AppModel
  func body(content: Content) -> some View {
    content.alert(
      L("NoBadge"),
      isPresented: Binding(
        get: { model.errorNotice != nil }, set: { if !$0 { model.errorNotice = nil } })
    ) {
      Button(L("OK"), role: .cancel) { model.errorNotice = nil }
    } message: {
      Text(model.errorNotice ?? "")
    }
  }
}
enum SettingsSection: String, CaseIterable, Identifiable {
  case general = "General"
  case apps = "Apps"
  case help = "Help & Recovery"
  case about = "About"
  case license = "License"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .apps: "square.grid.2x2"
    case .help: "arrow.counterclockwise"
    case .about: "info.circle"
    case .license: "key"
    }
  }
}
struct SettingsView: View {
  @ObservedObject var model: AppModel
  @State private var search = ""
  @State private var showSelectedFocus = false
  @State private var showKeptOnly = false
  private var section: SettingsSection { model.settingsSection }
  private var visibleApps: [AppEntry] {
    model.applications.filter {
      (!showKeptOnly || model.isException($0))
        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
    }
  }
  var body: some View {
    HStack(spacing: 0) {
      List(SettingsSection.allCases, selection: $model.settingsSection) { item in
        Label(L(item.rawValue), systemImage: item.symbol).tag(item).padding(.vertical, 4)
      }.listStyle(.sidebar).frame(width: 165)
      Divider()
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text(L(section.rawValue)).font(.system(size: 22, weight: .semibold))
          Spacer()
          if model.labOnly {
            Text(L("Verification mode")).font(.caption).foregroundStyle(.secondary)
          }
        }
        switch section {
        case .general: general
        case .apps: apps
        case .help: help
        case .about: about
        case .license: LicenseView(license: model.license)
        }
      }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }.frame(minWidth: 680, minHeight: 500)
      .modifier(NoticeModifier(model: model)).environment(\.locale, model.appLocale)
      .sheet(isPresented: $showSelectedFocus) { focusPicker }
  }
  private var general: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        Label(model.title, systemImage: model.phase == .hidden ? "app.badge.checkmark" : "app")
          .font(.headline)
        Text(model.focusSummary).font(.callout).foregroundStyle(.secondary)
        if [.access, .focusUnavailable, .error, .recovery, .unsupported, .paused].contains(model.phase)
          || (model.phase == .hidden && model.settings.manualHideUntil != nil) {
          Text(model.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
        }
        Button(model.primaryLabel) { model.primaryAction() }
          .buttonStyle(.borderedProminent).tint(brand).disabled(model.isBusy)
          .accessibilityIdentifier("primary-action")
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
      HStack {
        Text(L("Hide automatically during Focus"))
        Spacer()
        Toggle(
          L("Hide automatically during Focus"),
          isOn: Binding(
            get: { model.settings.automationEnabled }, set: { model.setAutomation($0) })
        )
        .labelsHidden().toggleStyle(.switch).disabled(!model.setupReady)
      }
      HStack {
        Picker(
          L("When to hide"),
          selection: Binding(
            get: { model.settings.selectedFocusIDs == nil },
            set: { model.setSelection($0 ? nil : Set(model.focus.activeIDs ?? [])) })
        ) {
          Text(L("Any Focus")).tag(true)
          Text(L("Selected Focus modes")).tag(false)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if model.settings.selectedFocusIDs != nil {
          Button(L("Choose…")) { showSelectedFocus = true }
        }
      }
      if model.settings.selectedFocusIDs?.isEmpty == true {
        Text(L("Choose at least one Focus.")).font(.caption).foregroundStyle(.orange)
      }
      Divider()
      HStack {
        Text(L("Open at login"))
        Spacer()
        Toggle(
          L("Open at login"),
          isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })
        )
        .labelsHidden().toggleStyle(.switch)
      }
      HStack {
        Text(L("Language"))
        Spacer()
        Picker(
          L("Language"),
          selection: Binding(get: { model.settings.appLanguage }, set: { model.setLanguage($0) })
        ) {
          Text("English").tag(AppLanguage.english)
          Text("한국어").tag(AppLanguage.korean)
        }.labelsHidden().frame(width: 150)
      }
      Spacer(minLength: 0)
      if model.showReviewInvitation {
        HStack {
          Text(L("How is NoBadge?")).font(.callout)
          Spacer()
          Button(L("Rate or review")) { model.openFeedback() }
          Button {
            model.showReviewInvitation = false
          } label: {
            Image(systemName: "xmark").font(.caption)
          }.buttonStyle(.plain).accessibilityLabel(L("Not now"))
        }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      }
      Text(L("Only badges change. Focus controls notification sounds and banners."))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private var apps: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L("Keep badges visible for these apps.")).foregroundStyle(.secondary)
      HStack {
        TextField(L("Search apps"), text: $search).textFieldStyle(.roundedBorder)
        Toggle(L("Kept visible"), isOn: $showKeptOnly).toggleStyle(.button)
      }
      if model.applications.isEmpty {
        ContentUnavailableView(
          L("No supported apps yet"), systemImage: "app.badge",
          description: Text(L("Apps appear after they register for notifications.")))
      } else if visibleApps.isEmpty {
        ContentUnavailableView.search(text: search)
      } else {
        ApplicationListView(
          apps: visibleApps,
          keptIDs: Set(model.applications.filter(model.isException).map(\.id)),
          changed: { model.setException($0, $1) })
      }
      Text(L("Apps with their own badge system may not respond to macOS badge settings."))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private var help: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label(
          model.hasAccess ? L("Full Disk Access is enabled") : L("Full Disk Access is needed"),
          systemImage: model.hasAccess ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(model.hasAccess ? brand : .orange)
        Spacer()
        Button(L("Review setup")) { model.reviewSetup() }
      }
      Text(
        L(
          "Pause NoBadge before changing badge settings in System Settings. Reopen NoBadge after a force quit to restore pending settings."
        )
      )
      .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Button(L("Restore previous settings")) { model.restoreExplicitly() }.disabled(model.isBusy)
      Divider()
      Text(
        L(
          "Diagnostics contain only app version, compatibility and status. Your Focus names, app list and messages stay private."
        )
      )
      .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Button(L("Export diagnostics…")) { model.exportDiagnostics() }
      DisclosureGroup(L("Compatibility details")) {
        VStack(alignment: .leading, spacing: 4) {
          Text("macOS \(model.build) · NoBadge \(model.version)")
          Text(
            model.qualified
              ? L("This build is qualified for the current adapter.")
              : L("This build has not been qualified."))
        }.font(.caption).padding(.top, 6)
      }
      Spacer(minLength: 0)
      Divider()
      HStack {
        Text(L("Restore badges before removing NoBadge.")).font(.caption).foregroundStyle(
          .secondary)
        Spacer()
        Button(L("Prepare to uninstall")) { model.prepareToUninstall() }.disabled(model.isBusy)
      }
    }
  }
  private var about: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("NoBadge", systemImage: "app.badge.checkmark").font(
        .system(size: 30, weight: .semibold)
      ).foregroundStyle(brand)
      Text(L("A quieter Dock when you focus.")).foregroundStyle(.secondary)
      Text(L("Version") + " \(model.version)").font(.caption)
      Button(BuildDistribution.isSourceBuild ? L("Source & updates") : (model.updatesConfigured ? L("Check for Updates") : L("Download purchased updates"))) {
        model.checkForUpdates()
      }
      if model.updatesConfigured {
        Toggle(
          L("Check for updates automatically"),
          isOn: Binding(
            get: { model.settings.automaticUpdateChecks }, set: { model.setUpdateChecks($0) }))
        Text(L("Updates are checked daily. You choose when to download and install. Badge settings are restored before restarting."))
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      Text(
        L(
          "Badge and Focus processing happens locally. No usage analytics or automatic diagnostic uploads."
        )
      )
      .font(.callout).fixedSize(horizontal: false, vertical: true)
      Text(
        L(
          "Inspired by FocusNoBadges and FocusPlsNoBadges. Original implementation; no upstream code or artwork included."
        )
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Link(
          L("Support"), destination: URL(string: "https://asdftq.github.io/nobadge/support.html")!)
        Link(
          L("Privacy"), destination: URL(string: "https://asdftq.github.io/nobadge/privacy.html")!)
        Button(L("Rate or review")) { model.openFeedback() }.buttonStyle(.link)
      }.font(.callout)
      Spacer()
      Text("© 2026 Hwechul Cho").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var focusPicker: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L("Selected Focus modes")).font(.headline)
      List(model.focus.modes) { mode in
        Toggle(
          mode.name,
          isOn: Binding(
            get: { model.settings.selectedFocusIDs?.contains(mode.id) == true },
            set: { on in
              var ids = model.settings.selectedFocusIDs ?? []
              if on { ids.insert(mode.id) } else { ids.remove(mode.id) }
              model.setSelection(ids)
            }))
      }.frame(height: min(240, CGFloat(max(1, model.focus.modes.count)) * 40))
      let missing = (model.settings.selectedFocusIDs ?? []).subtracting(model.focus.modes.map(\.id))
      if !missing.isEmpty {
        HStack {
          Text(L("Unavailable Focus") + " (\(missing.count))").font(.caption).foregroundStyle(
            .secondary)
          Spacer()
          Button(L("Remove")) {
            model.setSelection((model.settings.selectedFocusIDs ?? []).subtracting(missing))
          }
        }
      }
      HStack {
        Spacer()
        Button(L("Done")) { showSelectedFocus = false }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 350).environment(\.locale, model.appLocale)
  }
}

struct OnboardingView: View {
  @ObservedObject var model: AppModel
  let done: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Label("NoBadge", systemImage: "app.badge.checkmark").font(.headline)
        Spacer()
        Text("\(model.onboardingStep + 1) / 2").font(.caption).foregroundStyle(.secondary)
      }
      if model.onboardingStep == 0 { access } else { ready }
      Spacer(minLength: 0)
      Divider()
      HStack {
        if model.onboardingStep == 1 {
          Button(L("Back")) { model.setSetupStep(0) }
        } else {
          Button(L("Not now")) { done() }
        }
        Spacer()
        if model.onboardingStep == 0 {
          if model.setupReady {
            Button(L("Continue")) { model.setSetupStep(1) }.buttonStyle(.borderedProminent).tint(
              brand
            ).keyboardShortcut(.defaultAction)
          } else {
            Button(L("Check again")) { model.requestRefresh(force: true) }.disabled(model.isBusy)
          }
        } else {
          Button(model.settings.needsSetup ? L("Start NoBadge") : L("Done")) {
            if model.settings.needsSetup { model.completeSetup() }
            done()
          }.buttonStyle(.borderedProminent).tint(brand).keyboardShortcut(.defaultAction).disabled(
            !model.setupReady)
        }
      }
    }.padding(28).frame(width: 560, height: 480)
      .modifier(NoticeModifier(model: model)).environment(\.locale, model.appLocale)
  }
  private var access: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L("Hide badges while you focus.")).font(.system(size: 26, weight: .semibold))
      Text(L("NoBadge needs Full Disk Access to read Focus and change badge settings."))
        .font(.callout).fixedSize(horizontal: false, vertical: true)
      Text(
        L(
          "This permission allows broad file access. NoBadge only uses Focus and notification settings. It does not read messages or documents."
        )
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 8) {
        if model.hasAccess {
          Label(L("Full Disk Access is enabled"), systemImage: "checkmark.circle.fill")
            .foregroundStyle(brand)
          Text(model.focusSummary).font(.callout).foregroundStyle(.secondary)
        } else {
          Text(L("1. Open System Settings below."))
          Text(L("2. Add NoBadge from Applications and turn it on."))
          Text(L("3. Return here. Quit and reopen NoBadge if macOS asks."))
        }
      }.font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      if !model.hasAccess {
        HStack {
          Button(L("Open System Settings")) { model.openPrivacySettings() }.buttonStyle(
            .borderedProminent
          ).tint(brand)
          Button(L("Show NoBadge in Finder")) { model.revealApplication() }
        }
      }
      if model.accessChecked && !model.focusAvailable && model.hasAccess {
        Text(L("Focus is not available yet. Turn on a Focus once, then check again."))
          .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
      }
      if !model.qualified { Text(model.title).font(.caption).foregroundStyle(.orange) }
    }
  }
  private var ready: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L("You're ready.")).font(.system(size: 28, weight: .semibold))
      Text(
        L(
          "Turn on Focus as usual. NoBadge hides supported badges and restores your previous settings when Focus ends."
        )
      )
      .fixedSize(horizontal: false, vertical: true)
      Label(model.focusSummary, systemImage: "moon.circle").foregroundStyle(brand)
      Toggle(L("Open at login"), isOn: $model.loginRequested).toggleStyle(.switch)
      Text(
        L(
          "Choose apps to keep visible in Settings → Apps. You can pause or quit from the menu bar at any time."
        )
      )
      .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}
