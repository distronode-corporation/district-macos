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
        reset(to: next)
    }

    /// Make `next` the tenant these stacks belong to, with nothing left on any of them.
    ///
    /// ⚠️ CALLED DIRECTLY BY ``ShellView``'s `apply` as well as by ``adopt(_:)``, as on iOS,
    /// and that is what stops a link's own route being cleared a moment after it lands:
    /// the switch is stamped here, synchronously, so the `onChange` that fires when the new
    /// list resolves sees no change left to make. The selection is kept: a section the
    /// new role may not see is drawn as the Overview by the shell.
    mutating func reset(to next: String) {
        workspaceId = next
        stacks = [:]
    }

    /// Land where a tapped notification or an app link says (iOS `ShellPaths.apply`).
    ///
    /// ⛔ EVERY LANDING RESETS THE STACK IT LANDS ON (the ⛔ on ``PushRouteAction``). With
    /// no route, the action's tab is selected at its root; with one, the route opens in
    /// the section that owns it (``open(_:)``), so a hub's route lands in that hub and a
    /// call or a thread in its list beside the list. ⚠️ The action's tab is the iPad's
    /// compact answer; on the Mac a sidebar row is the whole answer, so a route decides.
    mutating func apply(_ action: PushRouteAction) {
        guard let route = action.route else {
            let item = SidebarItem(tab: action.tab)
            selection = item
            stacks[item] = []
            return
        }
        open(route)
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
