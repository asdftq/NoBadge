import Cocoa
import UserNotifications

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var status: NSTextField!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Badge Fixture"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: window.title); title.font = .systemFont(ofSize: 22, weight: .semibold)
        status = NSTextField(wrappingLabelWithString: "Synthetic notification fixture. No personal data.")
        let send = NSButton(title: "Send test badge (9)", target: self, action: #selector(sendBadge))
        let notification = NSButton(title: "Send test notification", target: self, action: #selector(sendNotification))
        let clear = NSButton(title: "Clear test notifications", target: self, action: #selector(clearBadge))
        let inspect = NSButton(title: "Read notification status", target: self, action: #selector(inspectStatus))
        let quit = NSButton(title: "Quit fixture", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        [title,status,send,notification,clear,inspect,quit].forEach(stack.addArrangedSubview)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),stack.widthAnchor.constraint(equalToConstant: 380)])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func sendBadge() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.badge]) else {
                    self.status.stringValue = "Notification permission was not allowed."; return
                }
                // Use the public notification badge API, never an app-drawn overlay.
                // API acceptance alone is not evidence of a visible Dock badge.
                try await center.setBadgeCount(9)
                self.report("Badge 9 requested. Check the actual Dock.")
            } catch {
                let error = error as NSError
                self.report("Badge request failed: \(error.domain) / \(error.code).")
            }
        }
    }
    @objc func sendNotification() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.badge, .alert]) else {
                    self.report("Notification permission was not allowed."); return
                }
                let content = UNMutableNotificationContent()
                content.title = "NoBadge verification"
                content.body = "Synthetic local test. No message or account data."
                content.badge = 9
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                self.report("Synthetic notification requested.")
            } catch {
                let error = error as NSError
                self.report("Notification request failed: \(error.domain) / \(error.code).")
            }
        }
    }
    @objc func clearBadge() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { error in
            Task { @MainActor in self.report(error == nil ? "Synthetic notifications cleared." : "Badge clear failed.") }
        }
    }
    @objc func inspectStatus() { report("Notification settings read from macOS.") }
    private func report(_ message: String) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let delivered = await center.deliveredNotifications()
            self.status.stringValue = message + "\nBadge permission: " + (settings.badgeSetting == .enabled ? "enabled" : "disabled") + " · delivered: \(delivered.count)"
                + "\nAuthorization: \(settings.authorizationStatus.rawValue) · Sound: \(settings.soundSetting.rawValue) · Alert: \(settings.alertSetting.rawValue)"
                + "\nLock screen: \(settings.lockScreenSetting.rawValue) · Center: \(settings.notificationCenterSetting.rawValue) · Preview: \(settings.showPreviewsSetting.rawValue)"

        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.badge] }
}
@main struct FixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
