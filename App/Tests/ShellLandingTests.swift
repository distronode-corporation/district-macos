@testable import DistrictMac
import DistrictModel
import XCTest

/// Where a tapped notification or an app link lands on the Mac, and what a workspace switch
/// clears. The Mac's half of iOS `ShellLandingTests`: one sidebar row per landing, no
/// compact layout.
///
/// ⛔ ``ShellPaths/apply(_:)`` IS THE PURE HALF OF THE SHELL'S ONE MOVER, so every landing is
/// pinned here rather than left to a run on a Mac.
final class ShellLandingTests: ShellPathsTestCase {
    // MARK: - The tenant

    /// ⛔ A SWITCH CLEARS EVERY STACK AND KEEPS THE SELECTION (the shell draws a section the
    /// new role may not see as the Overview).
    func test_MAC_LANDING_01_resetClearsEveryStackAndKeepsTheSelection() {
        var paths = seeded()
        for item in SidebarItem.allCases {
            paths.setPath([call], for: item)
        }
        paths.select(.billing)
        paths.reset(to: "ws_2")
        XCTAssertEqual(paths.workspaceId, "ws_2")
        XCTAssertTrue(SidebarItem.allCases.allSatisfy { paths.path(for: $0).isEmpty })
        XCTAssertEqual(paths.selection, .billing)
    }

    /// ⚠️ A RESET STAMPS THE TENANT, so the `adopt` that follows when the new list resolves
    /// clears nothing a landing has just put down.
    func test_MAC_LANDING_02_aResetIsNotUndoneByTheAdoptThatFollows() {
        var paths = seeded()
        paths.reset(to: "ws_2")
        let call2 = Route.callDetail(workspaceId: "ws_2", callId: "call_2")
        paths.apply(PushRouteAction(tab: .calls, selectWorkspaceId: "ws_2", route: call2))
        paths.adopt("ws_2")
        XCTAssertEqual(paths.path(for: .calls), [call2])
    }

    // MARK: - Landing

    /// ⚠️ NO ROUTE SELECTS THE TAB'S ROW AT ITS ROOT, and resets a stack it had.
    func test_MAC_LANDING_03_noRouteSelectsTheTabsRowAtItsRoot() {
        var paths = seeded()
        paths.setPath([call], for: .inbox)
        paths.apply(PushRouteAction(tab: .inbox, selectWorkspaceId: nil))
        XCTAssertEqual(paths.selection, .inbox)
        XCTAssertEqual(paths.path(for: .inbox), [])

        paths.apply(PushRouteAction(tab: .calls, selectWorkspaceId: nil))
        XCTAssertEqual(paths.selection, .calls)
    }

    /// ⛔ A HUB ROOT OPENS ITS ROW WITH NOTHING PUSHED; A ROUTE A HUB OWNS OPENS THAT ROW WITH
    /// THE ROUTE ON IT, whatever tab the iPad would have used.
    func test_MAC_LANDING_04_aHubsRouteLandsInThatHub() {
        var paths = seeded()
        paths.setPath([contact], for: .analytics)
        let analytics = Route.analytics(workspaceId: workspaceId)
        paths.apply(PushRouteAction(tab: .overview, selectWorkspaceId: nil, route: analytics))
        XCTAssertEqual(paths.selection, .analytics)
        XCTAssertEqual(paths.path(for: .analytics), [])

        let bookings = Route.scheduling(workspaceId: workspaceId, role: role, section: .bookings)
        paths.apply(PushRouteAction(tab: .overview, selectWorkspaceId: nil, route: bookings))
        XCTAssertEqual(paths.selection, .scheduling)
        XCTAssertEqual(paths.path(for: .scheduling), [bookings])
    }

    /// ⚠️ A ROW'S ROUTE OPENS BESIDE ITS LIST, and Devices opens under Account.
    func test_MAC_LANDING_05_aRowRouteOpensBesideItsList() {
        var paths = seeded()
        paths.apply(PushRouteAction(tab: .calls, selectWorkspaceId: nil, route: call))
        XCTAssertEqual(paths.selection, .calls)
        XCTAssertEqual(paths.path(for: .calls), [call])

        paths.apply(PushRouteAction(tab: .account, selectWorkspaceId: nil, route: .devices))
        XCTAssertEqual(paths.selection, .account)
        XCTAssertEqual(paths.path(for: .account), [.devices])
    }

    // MARK: - From a link to a landing

    /// The whole Mac path for one link: resolved by the core, routed, landed.
    func test_MAC_LANDING_06_aCallLinkOpensTheCallBesideTheCallLog() throws {
        let url = try XCTUnwrap(URL(string: "https://www.distronode.com/dashboard/district/calls/call_7"))
        guard case let .destination(destination)? = AppLinkResolver.resolve(url) else {
            return XCTFail("a call link is a destination")
        }
        var paths = seeded()
        paths.apply(AppLinkRouting.action(for: destination, selectedWorkspaceId: workspaceId, role: role))
        XCTAssertEqual(paths.selection, .calls)
        XCTAssertEqual(paths.path(for: .calls), [.callDetail(workspaceId: workspaceId, callId: "call_7")])
    }

    func test_MAC_LANDING_07_aStudioLinkOpensTheSettingsRow() throws {
        let url = try XCTUnwrap(URL(string: "https://www.distronode.com/dashboard/district/studio/knowledge"))
        guard case let .destination(destination)? = AppLinkResolver.resolve(url) else {
            return XCTFail("a studio link is a destination")
        }
        var paths = seeded()
        paths.apply(AppLinkRouting.action(for: destination, selectedWorkspaceId: workspaceId, role: role))
        XCTAssertEqual(paths.selection, .settings)
        XCTAssertEqual(
            paths.path(for: .settings),
            [.workspaceSettings(workspaceId: workspaceId, role: role, section: .knowledge)]
        )
    }

    // MARK: - Pushes

    /// ⛔ A MESSAGE PUSH OPENS THE INBOX AND SWITCHES NOTHING; ITS THREAD IS RESOLVED AFTER.
    func test_MAC_LANDING_08_aMessagePushOpensTheInbox() {
        let action = PushRouting.action(
            for: .openMessage(workspaceId: workspaceId, messageId: "m_1"),
            selectedWorkspaceId: workspaceId
        )
        XCTAssertEqual(action, PushRouteAction(tab: .inbox, selectWorkspaceId: nil))
        var paths = seeded()
        paths.setPath([call], for: .inbox)
        if let action {
            paths.apply(action)
        }
        XCTAssertEqual(paths.selection, .inbox)
        XCTAssertEqual(paths.path(for: .inbox), [])
    }

    /// ⛔ A TAPPED RING SHOWS THE CALL LOG, NEVER ANSWERS, and may switch to its workspace.
    func test_MAC_LANDING_09_aRingTapOpensTheCallLogInItsWorkspace() {
        let ring = PushDeepLinkDecision.ring(workspaceId: "ws_2", callId: "call_9")
        XCTAssertEqual(
            PushRouting.action(for: ring, selectedWorkspaceId: workspaceId),
            PushRouteAction(tab: .calls, selectWorkspaceId: "ws_2")
        )
        let here = PushDeepLinkDecision.ring(workspaceId: workspaceId, callId: "call_9")
        XCTAssertEqual(
            PushRouting.action(for: here, selectedWorkspaceId: workspaceId),
            PushRouteAction(tab: .calls, selectWorkspaceId: nil)
        )
        XCTAssertNil(PushRouting.action(for: .wait, selectedWorkspaceId: nil))
    }

    // MARK: - The payload a click hands over

    /// ⛔ ONLY TOP-LEVEL STRING PAIRS: `aps` and anything that is not a string are dropped,
    /// and what is left parses as the push it was.
    func test_MAC_LANDING_10_aClickedPayloadIsFlattenedToItsStringPairs() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "New message"]],
            "type": "message",
            "workspaceId": workspaceId,
            "messageId": "m_1",
            "badge": 3,
        ]
        let flat = AppDelegate.flatten(userInfo)
        XCTAssertEqual(flat, ["type": "message", "workspaceId": workspaceId, "messageId": "m_1"])
        XCTAssertEqual(PushPayload.parse(flat), .message(workspaceId: workspaceId, messageId: "m_1"))
    }

    // MARK: - One link delivered twice

    func test_MAC_LANDING_11_theSameLinkTwiceInAMomentIsTakenOnce() throws {
        let url = try XCTUnwrap(URL(string: "https://www.distronode.com/dashboard/district/studio/video"))
        let other = try XCTUnwrap(URL(string: "https://www.distronode.com/dashboard/district/inbox"))
        let start = Date(timeIntervalSince1970: 1000)
        var recent = RecentLinks()
        XCTAssertTrue(recent.admit(url, at: start))
        XCTAssertFalse(recent.admit(url, at: start.addingTimeInterval(0.5)), "the second delivery of one link")
        XCTAssertTrue(recent.admit(other, at: start.addingTimeInterval(0.6)), "another link is new")
        XCTAssertTrue(
            recent.admit(url, at: start.addingTimeInterval(0.6 + RecentLinks.window)),
            "the same link asked for again later is a new request"
        )
    }
}
