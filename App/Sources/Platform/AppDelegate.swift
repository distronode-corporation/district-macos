import AppKit
import Foundation
import UserNotifications

/// The AppKit half of the app's lifecycle: APNs callbacks, notification presentation and
/// actions, and quitting with a call up.
///
/// ⚠️ ADOPTED BY `@NSApplicationDelegateAdaptor`, which constructs it before the SwiftUI
/// scene exists. The registrar and the call objects are handed over from the first
/// window's `.onAppear`; a token or a notification action that arrives before that (the
/// app launched by pressing Answer) is held and delivered on adoption.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The live-call objects the delegate reaches.
    struct Calls {
        let incoming: IncomingCallModel
        let presenter: RingPresenter
        let live: DesktopLive
    }

    private weak var registrar: PushRegistrar?
    private var calls: Calls?
    private var earlyToken: String?
    private var earlyAction: RingAction?

    /// A press on the incoming-call notification.
    enum RingAction: Equatable {
        case answer(workspaceId: String, callId: String)
        case decline(callId: String)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // ⛔ REGISTERED AT LAUNCH, BEFORE ANY ALERT CAN ARRIVE: the APNs alert's
        // `aps.category` draws Answer and Decline only if this category is already
        // registered when it is shown. See ``RingNotifications``.
        center.setNotificationCategories([RingNotifications.incomingCallCategory()])
        #if DEVELOPER_ID
            DistrictUpdater.startIfConfigured()
        #endif
    }

    /// ⛔ ONE WINDOW, ONE SHELL: closing the main window quits the app, which stops ringing
    /// here (the APNs alert still reaches this Mac). ⚠️ The ring panel is a panel and does
    /// not hold the app open; a call in progress is ended by the quit like any other
    /// (see ``applicationShouldTerminate(_:)``).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// ⛔ A QUIT WITH A CALL UP ENDS IT FIRST, AND WAITS (BRIEFLY) FOR THE CARRIER. A placed
    /// call's hang-up is a request to the server; a process that exited before sending it
    /// would leave the far end ringing an empty room and billing. ``DesktopLive/terminate()``
    /// is bounded, so a quit never hangs on a network that has gone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let live = calls?.live else { return .terminateNow }
        Task { @MainActor in
            await live.terminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func adopt(registrar: PushRegistrar) {
        self.registrar = registrar
        if let token = earlyToken {
            earlyToken = nil
            registrar.deviceTokenReceived(token)
        }
    }

    func adopt(calls: Calls) {
        guard self.calls == nil else { return }
        self.calls = calls
        if let action = earlyAction {
            earlyAction = nil
            perform(action)
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

    /// A push arrived while the app runs. ⚠️ If it is the APNs alert for the call already
    /// ringing here, macOS may have shown it without asking (the app not frontmost), so it
    /// is taken out of Notification Center. See ``RingNotifications``.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        calls?.presenter.removeDuplicates()
    }

    // MARK: - Notifications

    /// Show the banner while the app is frontmost too (a message alert is worth seeing with
    /// the window open), EXCEPT for the call that is ringing: the panel is the ring.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let call = RingNotifications.call(in: userInfo)?.callId
        return await MainActor.run {
            let ringing = self.calls?.incoming.isRinging == true ? self.calls?.incoming.callId : nil
            return RingNotifications.presentation(callId: call, ringingCallId: ringing)
        }
    }

    /// A press on a notification. ⚠️ Only the incoming-call buttons do anything yet; a tap
    /// on a message notification brings the app forward, as before (routing a tap into a
    /// section is not ported; see PORTING.md).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let call = RingNotifications.call(in: userInfo) else { return }
        let action: RingAction? = switch response.actionIdentifier {
        case RingNotifications.answerAction:
            .answer(workspaceId: call.workspaceId, callId: call.callId)
        case RingNotifications.declineAction:
            .decline(callId: call.callId)
        default:
            nil
        }
        guard let action else { return }
        await MainActor.run { self.received(action) }
    }

    private func received(_ action: RingAction) {
        guard calls != nil else {
            earlyAction = action
            return
        }
        perform(action)
    }

    private func perform(_ action: RingAction) {
        guard let incoming = calls?.incoming else { return }
        switch action {
        case let .answer(workspaceId, callId):
            NSApplication.shared.activate()
            incoming.notificationAnswered(workspaceId: workspaceId, callId: callId)
        case let .decline(callId):
            incoming.notificationDeclined(callId: callId)
        }
    }
}
