import DistrictModel
import Foundation

/// Where the Mac shell is: the selected sidebar section, and one navigation stack per
/// section.
///
/// ⚠️ THE iPad's `ShellPaths` WITHOUT ITS COMPACT HALF. On iOS one value projects both the
/// tab bar and the sidebar so a size-class flip moves nobody; a Mac window has one layout,
/// so only the regular-width rules are carried over:
///   - each sidebar row owns its stack, so leaving Calls with a call open and coming back
///     finds the call where it was;
///   - a list section's stack is the open row (`first`) plus whatever was pushed on it
///     (``ListDetailPath``);
///   - every stack is cleared when the workspace changes, because each ``Route`` carries
///     the workspace it was built for and would otherwise open another tenant's row
///     under this one's name (iOS `ShellPaths.reset(to:)`).
struct ShellPaths: Equatable {
    /// The section on screen.
    private(set) var selection: SidebarItem = .overview

    private var stacks: [SidebarItem: [Route]] = [:]

    /// The workspace the stacks were built for; nil until the first one resolves.
    private(set) var workspaceId: String?

    func path(for item: SidebarItem) -> [Route] {
        stacks[item] ?? []
    }

    mutating func setPath(_ path: [Route], for item: SidebarItem) {
        stacks[item] = path
    }

    /// Select a section, keeping every stack (the iPad's sidebar does the same).
    mutating func select(_ item: SidebarItem) {
        selection = item
    }

    /// Show `route` in the section that owns it: a list row in its list section, a hub
    /// root (or a screen under one) in that hub's row.
    ///
    /// ⚠️ THE OWNER IS THE ROUTE'S, NOT THE SELECTION'S, the rule iOS `ShellPaths.apply`
    /// follows for a landing. Used by the menu commands and the compose sheet's "open the
    /// thread I just started", never by a tap inside a stack, which pushes in place.
    mutating func open(_ route: Route) {
        if let hub = SidebarItem.hubItem(forRoot: route) {
            selection = hub
            stacks[hub] = []
            return
        }
        if let root = SidebarItem.ownerRoot(of: route), let hub = SidebarItem.hubItem(forRoot: root) {
            selection = hub
            stacks[hub] = [route]
            return
        }
        let item = Self.listSection(of: route)
        selection = item
        stacks[item] = [route]
    }

    /// Adopt the workspace the session resolved, clearing every stack when it changed.
    ///
    /// ⚠️ THE FIRST RESOLUTION CLEARS NOTHING: there is nothing yet that belongs to another
    /// tenant. A section that a role may not see is left selected here and drawn as the
    /// Overview by the shell (see ``ShellView``), as on the iPad.
    mutating func adopt(_ next: String?) {
        guard let next else { return }
        guard let previous = workspaceId else {
            workspaceId = next
            return
        }
        guard next != previous else { return }
        workspaceId = next
        stacks = [:]
    }

    /// The list section a row route opens in, and Account for the one account route.
    static func listSection(of route: Route) -> SidebarItem {
        switch route {
        case .callDetail: .calls
        case .thread: .inbox
        case .contactDetail: .contacts
        case .devices: .account
        case .hq, .analytics, .marketplace, .billing, .workflows, .rooms, .activeRoom, .dialer,
             .workspaceSettings, .scheduling, .support, .supportRequest, .desk, .deskTicket:
            SidebarItem.owner(of: route) ?? .overview
        }
    }
}
