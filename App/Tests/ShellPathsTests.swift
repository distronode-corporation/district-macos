@testable import DistrictMac
import DistrictModel
import XCTest

/// The Mac shell's navigation state: one stack per sidebar row, cleared on a tenant switch.
final class ShellPathsTests: ShellPathsTestCase {
    /// ⛔ EACH ROW KEEPS ITS OWN STACK, so leaving Calls with a call open and coming back
    /// finds the call (and whatever was pushed on it) where it was.
    func test_MAC_PATHS_01_eachSectionKeepsItsStackAcrossSelections() {
        var paths = seeded()
        paths.select(.calls)
        paths.setPath([call, dialer], for: .calls)
        paths.select(.contacts)
        paths.setPath([contact], for: .contacts)
        paths.select(.calls)

        XCTAssertEqual(paths.selection, .calls)
        XCTAssertEqual(paths.path(for: .calls), [call, dialer])
        XCTAssertEqual(paths.path(for: .contacts), [contact])
        XCTAssertEqual(paths.path(for: .inbox), [])
    }

    /// ⛔ A TENANT SWITCH CLEARS EVERY STACK: each route carries the workspace it was built
    /// for. The first resolution and a re-resolution of the same tenant clear nothing.
    func test_MAC_PATHS_02_aWorkspaceSwitchClearsEveryStackAndNothingElseDoes() {
        var paths = ShellPaths()
        paths.setPath([call], for: .calls)
        paths.adopt(workspaceId)
        XCTAssertEqual(paths.path(for: .calls), [call], "the first workspace clears nothing")
        paths.adopt(nil)
        paths.adopt(workspaceId)
        XCTAssertEqual(paths.path(for: .calls), [call], "the same workspace again clears nothing")

        paths.select(.contacts)
        paths.adopt("ws_2")
        XCTAssertEqual(paths.workspaceId, "ws_2")
        XCTAssertTrue(SidebarItem.allCases.allSatisfy { paths.path(for: $0).isEmpty })
        XCTAssertEqual(paths.selection, .contacts, "a tab row stays selected")
    }

    /// ⚠️ OPENING A ROUTE PUTS IT IN THE SECTION THAT OWNS IT, whichever is on screen.
    func test_MAC_PATHS_03_openingARouteSelectsItsOwner() {
        var paths = seeded()
        paths.open(call)
        XCTAssertEqual(paths.selection, .calls)
        XCTAssertEqual(paths.path(for: .calls), [call])

        let thread = Route.thread(workspaceId: workspaceId, role: role, threadKey: "t_1", replyTargets: [], title: nil)
        paths.open(thread)
        XCTAssertEqual(paths.selection, .inbox)
        XCTAssertEqual(paths.path(for: .inbox), [thread])

        paths.open(root(.billing))
        XCTAssertEqual(paths.selection, .billing)
        XCTAssertEqual(paths.path(for: .billing), [], "a hub root is the row itself")

        let ticket = Route.deskTicket(workspaceId: workspaceId, role: role, ticketId: "t_9")
        paths.open(ticket)
        XCTAssertEqual(paths.selection, .desk)
        XCTAssertEqual(paths.path(for: .desk), [ticket])

        paths.open(.devices)
        XCTAssertEqual(paths.selection, .account)
        XCTAssertEqual(paths.path(for: .account), [.devices])
    }

    func test_MAC_PATHS_04_everyRouteHasAListSectionOrAHub() {
        XCTAssertEqual(ShellPaths.listSection(of: call), .calls)
        XCTAssertEqual(ShellPaths.listSection(of: contact), .contacts)
        XCTAssertEqual(ShellPaths.listSection(of: dialer), .dialer)
        XCTAssertEqual(ShellPaths.listSection(of: .devices), .account)
    }
}
