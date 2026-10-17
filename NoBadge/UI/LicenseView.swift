import SwiftUI

struct LicenseView: View {
  @ObservedObject var license: LicenseService
  var activated: (() -> Void)?
  @State private var key = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if BuildDistribution.isSourceBuild {
        Label(L("Built from source"), systemImage: "hammer.fill")
          .font(.system(size: 24, weight: .semibold))
        Text(L("This copy needs no purchase key. Rebuild from the latest source to update it."))
          .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Link(L("Source & updates"), destination: BuildDistribution.sourceURL)
        Link(L("Get the signed app"), destination: BuildDistribution.websiteURL)
      } else {
        Label(license.canUse ? L("License active") : L("Activate NoBadge"), systemImage: license.canUse ? "checkmark.seal.fill" : "key")
          .font(.system(size: 24, weight: .semibold))
        if license.canUse {
          Text(license.maskedKey).font(.body.monospaced()).textSelection(.enabled)
          Text(L("Your purchase is activated on this Mac.")).foregroundStyle(.secondary)
          Button(L("Deactivate this Mac")) { Task { await license.deactivate() } }
            .disabled(license.busy)
        } else {
          Text(L("Paste the license key from your purchase receipt to start using NoBadge."))
            .fixedSize(horizontal: false, vertical: true)
          SecureField(L("License key"), text: $key)
            .textFieldStyle(.roundedBorder).onSubmit { activate() }
            .accessibilityIdentifier("license-key")
          HStack {
            Button(L("Activate")) { activate() }
              .buttonStyle(.borderedProminent).disabled(license.busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if license.busy { ProgressView().controlSize(.small) }
          }
          HStack {
            Link(L("Buy NoBadge — $2.99"), destination: URL(string: "https://asdftq.lemonsqueezy.com/checkout/buy/5863d7ba-944d-4dfe-97ed-a5f4be0ae82f")!)
            Link(L("Find my license key"), destination: URL(string: "https://app.lemonsqueezy.com/my-orders")!)
          }.font(.callout)
        }
        if let message = license.message {
          Text(message).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("license-message")
        }
        Divider()
        Text(L("One purchase, up to 3 Macs. Internet is needed for activation and occasional license checks. After verification, NoBadge can work offline for up to 30 days."))
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Link(L("Purchase help"), destination: URL(string: "https://www.asdftq.com/nobadge/support.html#license")!)
          .font(.callout)
      }
    }
  }
  private func activate() {
    Task {
      if await license.activate(key) {
        key = ""
        activated?()
      }
    }
  }
}

struct ActivationWindowView: View {
  @ObservedObject var model: AppModel
  var activated: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
        Text("NoBadge").font(.title.weight(.semibold))
      }
      LicenseView(license: model.license, activated: activated)
      HStack {
        Button(L("Restore previous settings")) { model.restoreExplicitly() }.disabled(model.isBusy)
        Spacer()
        Button(L("Check for Updates")) { model.checkForUpdates() }
      }.font(.caption)
    }.padding(28).frame(width: 500)
      .environment(\.locale, model.appLocale)
  }
}
