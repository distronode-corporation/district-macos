import AppKit
import Foundation
import os
import ServiceManagement

/// SPIKE (spike/v3-mac-voip, not for merge): how this Mac keeps ringing after its window
/// is closed, and after a restart, without a VoIP push.
///
/// ⛔ THERE IS NO VoIP PUSH TO WAKE A NATIVE MAC APP. `PKPushType.voIP` is
/// `API_UNAVAILABLE(macos)` (only Mac Catalyst has it), and `CXProvider` has no native
/// macOS availability, so a quit app cannot be launched by a call push. The ring stays
/// on the telemetry socket, which needs the process alive. So:
///
///   * **Closing the window no longer quits.** The process (and with it ``DesktopLive``'s
///     socket and presence row) keeps running behind the menu bar item, and a call rings
///     exactly as it does with the window open: the ring panel, the sound and the
///     notification with Answer and Decline.
///   * **Open at login** registers the app itself as a login item
///     (`SMAppService.mainApp`, macOS 13), so a restart does not leave the Mac silent.
///     The user turns it on; App Review guideline 2.4.5(iii) forbids doing it unasked.
///   * **Quit (Command-Q) still quits.** Then the APNs alert push the service already
///     sends is the ring: Answer launches the app and answers (``AppDelegate``).
enum BackgroundRinging {
    /// ⚠️ ON BY DEFAULT IN THE SPIKE. A shipped build would put this beside "Ring on this
    /// computer" in Settings.
    static let keepRunningKey = "spike.backgroundRinging.keepRunning"

    static var keepsRunningAfterLastWindowClosed: Bool {
        UserDefaults.standard.object(forKey: keepRunningKey) as? Bool ?? true
    }

    /// Whether the app is registered to open at login.
    @MainActor
    static var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item. ⚠️ `.requiresApproval` means the
    /// user switched it off in System Settings > General > Login Items; the app cannot
    /// override that, only point there.
    @MainActor
    static func setOpensAtLogin(_ enabled: Bool) {
        let log = Logger(subsystem: "com.distronode.district", category: "BackgroundRinging")
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("open at login \(enabled) failed: \(String(describing: error), privacy: .public)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
