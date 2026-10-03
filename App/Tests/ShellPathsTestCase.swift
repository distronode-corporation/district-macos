@testable import DistrictMac
import DistrictModel
import XCTest

/// Fixtures for the shell's navigation state, the iPad's `ShellPathsTestCase` without its
/// compact-width helpers.
class ShellPathsTestCase: XCTestCase {
    let workspaceId = "ws_1"
    let role = WorkspaceRole.agency

    func root(_ item: SidebarItem, role: WorkspaceRole? = .agency) -> Route {
        guard let route = item.rootRoute(workspaceId: workspaceId, role: role) else {
            preconditionFailure("\(item) is not a hub section")
        }
        return route
    }

    var call: Route {
        .callDetail(workspaceId: workspaceId, callId: "call_1")
    }

    var contact: Route {
        .contactDetail(workspaceId: workspaceId, role: role, contactId: "c_1")
    }

    var dialer: Route {
        .dialer(workspaceId: workspaceId, role: role)
    }

    var room: Route {
        .activeRoom(workspaceId: workspaceId, role: role, roomName: "meet_ws_1_a")
    }

    func seeded() -> ShellPaths {
        var paths = ShellPaths()
        paths.adopt(workspaceId)
        return paths
    }
}
