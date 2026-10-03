@testable import DistrictMac
import DistrictModel
import XCTest

/// How a scheduling URL becomes a destination, and who may reach one.
final class SchedulingRoutingTests: XCTestCase {
    // ⚠️ THE iOS FILE'S FIRST NINE CASES (`test_IOS_SCHLINK_01` TO `_09`) RESOLVE A
    // `www.distronode.com` LINK THROUGH `AppLinkResolver` AND `AppLinkRouting`, WHICH THE
    // MAC HAS NOT PORTED (PORTING.md, "App links and push taps"). They come over with that
    // port; the six below need only the route, the gate and the Overview's rows.

    // MARK: - The gate

    /// ⛔ `.partial` FOR A VIEWER RATHER THAN `.hidden` OR `.none`, AND ALL THREE ARE
    /// MEANINGFUL. `.hidden` would withhold nine screens the server would serve; `.none`
    /// would claim nothing on the surface is gated, which stopped being true when the
    /// recordings download arrived.
    func test_IOS_SCHLINK_10_aViewerReachesSchedulingReadOnly() {
        let route = Route.scheduling(workspaceId: "ws_1", role: .viewer, section: .hub)
        guard case .partial = RouteGate.gate(for: route, role: .viewer) else {
            return XCTFail("a viewer must reach scheduling read-only")
        }
    }

    func test_IOS_SCHLINK_11_aMutatorIsNotGated() {
        for role in [WorkspaceRole.agency, .client] {
            let route = Route.scheduling(workspaceId: "ws_1", role: role, section: .hub)
            guard case .none = RouteGate.gate(for: route, role: role) else {
                return XCTFail("\(role) must not be gated on scheduling")
            }
        }
    }

    /// ⛔ A ROLE THAT DID NOT PARSE IS TREATED AS A VIEWER, never as a client.
    func test_IOS_SCHLINK_12_anUnparseableRoleGetsTheReadOnlyGate() {
        let route = Route.scheduling(workspaceId: "ws_1", role: nil, section: .hub)
        guard case .partial = RouteGate.gate(for: route, role: nil) else {
            return XCTFail("a nil role must fail closed to read-only")
        }
    }

    /// ⛔ THE SETTINGS HUB'S SCHEDULING ROW IS NOT HIDDEN FROM A VIEWER. Every read
    /// behind it admits a viewer.
    func test_IOS_SCHLINK_13_theSettingsHubOffersSchedulingToAViewer() {
        let route = Route.workspaceSettings(workspaceId: "ws_1", role: .viewer, section: .scheduling)
        guard case .partial = RouteGate.gate(for: route, role: .viewer) else {
            return XCTFail("the scheduling settings row must be offered to a viewer")
        }
    }

    /// ⚠️ THE OVERVIEW ROW IS PRESENT FOR EVERY ROLE and captioned read-only for a viewer.
    func test_IOS_SCHLINK_14_theOverviewRowIsOfferedToEveryRole() {
        for role in [WorkspaceRole.agency, .client, .viewer] {
            let entries = OverviewEntry.all(workspaceId: "ws_1", role: role)
            XCTAssertTrue(
                entries.contains { $0.title == "Scheduling" },
                "Scheduling must be offered to \(role)"
            )
        }
        let viewerRow = OverviewEntry.all(workspaceId: "ws_1", role: .viewer)
            .first { $0.title == "Scheduling" }
        XCTAssertEqual(viewerRow?.caption, "Read-only")
    }

    /// ⛔ AND THE ROW OPENS THE HUB, not a section. A workspace with no booking page has
    /// nothing in any of the nine, so landing elsewhere would be a screen whose every read
    /// answers `scheduling_not_ready`.
    func test_IOS_SCHLINK_15_theOverviewRowOpensTheHub() {
        let entry = OverviewEntry.all(workspaceId: "ws_1", role: .agency)
            .first { $0.title == "Scheduling" }
        guard case let .route(route) = entry?.target,
              case let .scheduling(_, _, section) = route
        else {
            return XCTFail("expected a scheduling route")
        }
        XCTAssertEqual(section, .hub)
    }
}
