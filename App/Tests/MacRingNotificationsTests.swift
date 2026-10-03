@testable import DistrictMac
import UserNotifications
import XCTest

/// ⛔ ONE RING, ONE ALERT.
///
/// The server sends this Mac's APNs alert row a `district.incoming_call` alert for every
/// call it rings, and cannot tell whether the app is open, so while the app shows the ring
/// itself the push is a duplicate. These pin the rules that suppress it (while the app is
/// frontmost) and remove it (while it is not), and the category the push's buttons need.
final class MacRingNotificationsTests: XCTestCase {
    private let ringing = "call_ringing_1"

    /// The APNs alert's shape: `aps` plus the data keys at the top level.
    private func push(callId: String, type: String = "incoming_call") -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title-loc-key": "push.call.title"], "category": RingNotifications.category],
            "type": type,
            "category": RingNotifications.category,
            "workspaceId": "ws_1",
            "callId": callId,
            "messageId": "msg_1",
        ]
    }

    // MARK: - The category

    func test_MAC_RING_NOTE_01_theCategoryMatchesTheServersAndCarriesBothButtons() {
        let category = RingNotifications.incomingCallCategory()
        // ⛔ BYTE FOR BYTE THE SERVER'S `PushCategory`, or the push draws no buttons.
        XCTAssertEqual(category.identifier, "district.incoming_call")
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [RingNotifications.answerAction, RingNotifications.declineAction]
        )
        XCTAssertEqual(category.actions.map(\.title), ["Answer", "Decline"])
        XCTAssertTrue(category.actions[0].options.contains(.foreground), "Answer brings the app forward")
        XCTAssertTrue(category.actions[1].options.contains(.destructive))
        XCTAssertFalse(category.actions[1].options.contains(.foreground), "Decline does not")
    }

    func test_MAC_RING_NOTE_02_theAppsOwnPayloadReadsAsTheCallItIsAbout() throws {
        let info = RingNotifications.userInfo(workspaceId: "ws_1", callId: ringing)
        let call = try XCTUnwrap(RingNotifications.call(in: info))
        XCTAssertEqual(call.workspaceId, "ws_1")
        XCTAssertEqual(call.callId, ringing)
        XCTAssertEqual(RingNotifications.identifier(callId: ringing), "ring:call_ringing_1")
    }

    // MARK: - Frontmost: willPresent

    func test_MAC_RING_NOTE_03_neitherAlertForTheRingingCallIsShownWhileTheAppIsFrontmost() {
        XCTAssertEqual(RingNotifications.presentation(userInfo: push(callId: ringing), ringingCallId: ringing), [])
        XCTAssertEqual(
            RingNotifications.presentation(
                userInfo: RingNotifications.userInfo(workspaceId: "ws_1", callId: ringing),
                ringingCallId: ringing
            ),
            [],
            "the panel is the ring; the app's own notification is not shown over it either"
        )
    }

    func test_MAC_RING_NOTE_04_everythingElseIsShownAsBefore() {
        let shown: UNNotificationPresentationOptions = [.banner, .sound, .list]
        XCTAssertEqual(
            RingNotifications.presentation(userInfo: push(callId: "call_other"), ringingCallId: ringing),
            shown
        )
        XCTAssertEqual(RingNotifications.presentation(userInfo: push(callId: ringing), ringingCallId: nil), shown)
        XCTAssertEqual(
            RingNotifications.presentation(userInfo: push(callId: ringing, type: "message"), ringingCallId: ringing),
            shown,
            "a message is never mistaken for the ring"
        )
    }

    // MARK: - Not frontmost: removed after the fact

    func test_MAC_RING_NOTE_05_onlyTheOtherSourcesAlertForTheRingingCallIsADuplicate() {
        let delivered: [(identifier: String, userInfo: [AnyHashable: Any])] = [
            (
                RingNotifications.identifier(callId: ringing),
                RingNotifications.userInfo(workspaceId: "ws_1", callId: ringing)
            ),
            ("apns-1", push(callId: ringing)),
            ("apns-2", push(callId: "call_other")),
            ("apns-3", push(callId: ringing, type: "message")),
        ]
        XCTAssertEqual(RingNotifications.duplicates(in: delivered, ringingCallId: ringing), ["apns-1"])
    }

    func test_MAC_RING_NOTE_06_whenTheRingEndsEveryAlertAboutThatCallGoes() {
        let delivered: [(identifier: String, userInfo: [AnyHashable: Any])] = [
            (
                RingNotifications.identifier(callId: ringing),
                RingNotifications.userInfo(workspaceId: "ws_1", callId: ringing)
            ),
            ("apns-1", push(callId: ringing)),
            ("apns-2", push(callId: "call_other")),
        ]
        XCTAssertEqual(
            RingNotifications.leftovers(in: delivered, callId: ringing),
            [RingNotifications.identifier(callId: ringing), "apns-1"]
        )
    }

    // MARK: - The words

    func test_MAC_RING_NOTE_07_theAppsNotificationUsesTheAlertsOwnWords() {
        // ⛔ THE SAME KEYS THE APNs ALERT RESOLVES, so the two notifications read alike.
        XCTAssertEqual(String(localized: "push.call.title"), "Incoming call")
        XCTAssertEqual(String(localized: "push.call.body"), "Someone is calling your District line.")
    }
}
