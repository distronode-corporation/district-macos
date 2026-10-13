import AppKit
import Foundation
import Observation
import ServiceManagement

/// How this Mac keeps ringing with its window closed, and after a restart, without a VoIP
/// push.
///
/// ⛔ THERE IS NO VoIP PUSH TO WAKE A NATIVE MAC APP. `PKPushType.voIP` is
/// `API_UNAVAILABLE(macos)` and CallKit's `CXProvider` has no native macOS availability
/// (measured on the macOS 26.2 SDK, district-macos PR #37), so a quit app cannot be
/// launched by a call push. The ring stays on the telemetry socket, which needs the
/// process alive. So (Sean's "Menu bar + loud alert"):
///
///   * **Closing the window does not quit.** The process, and with it ``DesktopLive``'s
///     socket and presence, keeps running behind the menu bar item, and a call rings as it
///     does with the window open: the ring panel, the sound, and the notification with
///     Answer and Decline. ``SessionModel`` starts the ringing, not a view, so a launch
///     with no window rings too.
///   * **Open at Login** registers the app itself as a login item
///     (`SMAppService.mainApp`), so a restart does not leave the Mac silent. ⛔ OFF UNTIL
///     THE USER TURNS IT ON: App Review guideline 2.4.5(iii) forbids starting at login
///     unasked.
///   * **Quit (⌘Q) still quits.** Then the server's APNs alert is the ring: Time Sensitive,
///     with the bundled `ring.wav`, and Answer launches the app and answers
///     (``AppDelegate``).
@MainActor
@Observable
final class BackgroundRinging {
    /// The login item, behind a seam so a test never registers the test host.
    private let loginItem: any LoginItem

    /// Whether the app opens at login, as the system reports it.
    ///
    /// ⚠️ READ BACK AFTER EVERY CHANGE, NEVER ASSUMED: the user can switch it off in System
    /// Settings > General > Login Items, and the system's answer is the truth.
    private(set) var opensAtLogin: Bool

    init(loginItem: any LoginItem = MainAppLoginItem()) {
        self.loginItem = loginItem
        opensAtLogin = loginItem.status == .enabled
    }

    /// Turn Open at Login on or off.
    ///
    /// ⚠️ `.requiresApproval` MEANS THE USER SWITCHED IT OFF IN SYSTEM SETTINGS; the app
    /// cannot override that, only open the page where they can switch it back on.
    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
        } catch {
            // ⚠️ NOTHING TO SAY BEYOND THE TOGGLE ITSELF, which is read back below and so
            // shows what the system did rather than what was asked.
        }
        let status = loginItem.status
        if enabled, status == .requiresApproval {
            loginItem.openSystemSettings()
        }
        opensAtLogin = status == .enabled
    }
}

/// The part of `SMAppService` the menu uses.
@MainActor
protocol LoginItem {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// The app itself as its login item.
struct MainAppLoginItem: LoginItem {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
