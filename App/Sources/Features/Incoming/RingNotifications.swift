import DistrictModel
import Foundation
import UserNotifications

/// The incoming-call notification: its category, its two buttons, and the rules that keep
/// one ring from showing two alerts.
///
/// ⛔ TWO SOURCES CAN ALERT FOR THE SAME CALL, AND ONLY ONE MAY SHOW. This app posts its own
/// notification when the telemetry socket rings it, and the server ALSO sends the Mac's
/// APNs alert row a `district.incoming_call` alert for the same call (it cannot tell
/// whether the app is open; that alert is what reaches a closed Mac). With the app showing
/// the ring, the APNs one is a duplicate:
///   * while the app is frontmost, `willPresent` is asked and answers nothing for either
///     (the ring panel is on screen): ``presentation(userInfo:ringingCallId:)``;
///   * while it is not, macOS shows the push without asking, so the app removes it from
///     Notification Center as soon as it hears of it (``duplicates(in:ringingCallId:)``),
///     and removes both when the ring ends (``leftovers(in:callId:)``).
///
/// ⚠️ PURE, SO THE RULES ARE TESTED WITHOUT A NOTIFICATION CENTER. ``RingPresenter`` and the
/// app delegate apply them.
enum RingNotifications {
    /// ⛔ THE SERVER'S CATEGORY, BYTE FOR BYTE (`PushCategory` in the service's push types):
    /// the APNs alert's `aps.category` draws these buttons only if it matches a category
    /// this app registered, and an unmatched one draws none, with no error anywhere.
    static let category = "district.incoming_call"
    static let answerAction = "district.call.answer"
    static let declineAction = "district.call.decline"

    static let answerTitle = "Answer"
    static let declineTitle = "Decline"

    /// The category to register at launch.
    ///
    /// ⚠️ ANSWER BRINGS THE APP FORWARD (`.foreground`): the call's window, the microphone
    /// prompt and the in-call controls are all in the app. Decline does not, and is marked
    /// destructive.
    static func incomingCallCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: answerAction, title: answerTitle, options: [.foreground]),
                UNNotificationAction(identifier: declineAction, title: declineTitle, options: [.destructive]),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// This app's own notification for a ring. ⚠️ One per call, so a second post replaces it.
    static func identifier(callId: String) -> String {
        "ring:\(callId)"
    }

    /// The call a notification is about, from its payload, or nil for anything else.
    ///
    /// ⚠️ THE CORE'S PARSER, so the APNs alert (top-level `type`, `workspaceId`, `callId`)
    /// and this app's own notification (posted with the same keys) are read one way.
    static func call(in userInfo: [AnyHashable: Any]) -> (workspaceId: String, callId: String)? {
        guard case let .incomingCall(workspaceId, callId)? = PushPayload.parse(userInfo: userInfo) else { return nil }
        return (workspaceId, callId)
    }

    /// The payload this app posts, in the push's own shape.
    static func userInfo(workspaceId: String, callId: String) -> [String: String] {
        ["type": "incoming_call", "category": category, "workspaceId": workspaceId, "callId": callId]
    }

    /// What `willPresent` answers while the app is frontmost.
    ///
    /// ⛔ NOTHING FOR THE CALL THAT IS RINGING, whichever source posted it: the ring panel
    /// is the ring. Everything else is shown as before (a banner, a sound, the list).
    static func presentation(
        userInfo: [AnyHashable: Any],
        ringingCallId: String?
    ) -> UNNotificationPresentationOptions {
        presentation(callId: call(in: userInfo)?.callId, ringingCallId: ringingCallId)
    }

    /// The same, from the call id already read out of the payload. ⚠️ The app delegate
    /// reads the payload off the main actor and compares on it, and a `String` crosses
    /// that boundary where a payload dictionary cannot.
    static func presentation(callId: String?, ringingCallId: String?) -> UNNotificationPresentationOptions {
        if let ringingCallId, callId == ringingCallId {
            return []
        }
        return [.banner, .sound, .list]
    }

    /// The delivered notifications that duplicate the ring: about the ringing call, and not
    /// this app's own.
    static func duplicates(
        in delivered: [(identifier: String, userInfo: [AnyHashable: Any])],
        ringingCallId: String
    ) -> [String] {
        let own = identifier(callId: ringingCallId)
        return delivered
            .filter { $0.identifier != own && call(in: $0.userInfo)?.callId == ringingCallId }
            .map(\.identifier)
    }

    /// Every delivered notification about `callId`, this app's own included, to remove when
    /// its ring ends. ⚠️ An "Incoming call" left in Notification Center for a call that is
    /// over invites an Answer that can only fail.
    static func leftovers(
        in delivered: [(identifier: String, userInfo: [AnyHashable: Any])],
        callId: String
    ) -> [String] {
        delivered
            .filter { $0.identifier == identifier(callId: callId) || call(in: $0.userInfo)?.callId == callId }
            .map(\.identifier)
    }
}
