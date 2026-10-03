import AppKit
import Foundation
import UserNotifications

/// The AppKit half of the app's lifecycle: APNs callbacks and notification presentation.
///
/// ⚠️ ADOPTED BY `@NSApplicationDelegateAdaptor`, which constructs it before the SwiftUI
/// scene exists. The registrar is handed over from the first window's `.onAppear`, and a
/// token that arrives before that is held and delivered on adoption.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var registrar: PushRegistrar?
    private var earlyToken: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        #if DEVELOPER_ID
            DistrictUpdater.startIfConfigured()
        #endif
    }

    /// ⛔ ONE WINDOW, ONE SHELL: closing the window quits the app. A call or ring
    /// surviving with no window comes with the menu-bar presence in Wave 6.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func adopt(registrar: PushRegistrar) {
        self.registrar = registrar
        if let token = earlyToken {
            earlyToken = nil
            registrar.deviceTokenReceived(token)
        }
    }

    // MARK: - APNs

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Hex, lower case: the form the service stores and APNs addresses.
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let registrar else {
            earlyToken = hex
            return
        }
        registrar.deviceTokenReceived(hex)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        registrar?.remoteRegistrationFailed(error)
    }

    // MARK: - Notifications

    /// Show the banner while the app is frontmost too: a message alert is worth seeing
    /// even with the window open. The tap routing arrives with the Inbox (Wave 5).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
