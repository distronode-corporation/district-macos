import Foundation

/// Every top-level section of the Mac shell, in sidebar order.
///
/// ⛔ THE SAME SIXTEEN SECTIONS, IN THE SAME ORDER, AS THE iPad SIDEBAR (district-ios
/// `Navigation/SidebarItem.swift` and `OverviewEntry.all`, at gh/main 0b2354b): the four
/// list tabs, the twelve hubs in Overview's order, then Account. v1 of the Mac app is
/// iPad parity, and this enum is the checklist that parity is measured against.
/// `SidebarItemTests` pins the count and the order.
///
/// ⛔ ROLE GATES ARE THE iPad'S: the sidebar offers what ``entries(workspaceId:role:)``
/// returns (`RouteGate`, through ``OverviewEntry/all(workspaceId:role:)``), so a viewer
/// never sees a hub whose every request would answer 403, and a read-only one is
/// badged "Read-only".
enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case overview
    case inbox
    case calls
    case contacts
    case hq
    case analytics
    case marketplace
    case billing
    case rooms
    case workflows
    case desk
    case dialer
    case scheduling
    case support
    case settings
    case account

    var id: String {
        rawValue
    }

    /// The sidebar label, the iPad's wording.
    var title: String {
        switch self {
        case .overview: "Overview"
        case .inbox: "Inbox"
        case .calls: "Calls"
        case .contacts: "Contacts"
        case .hq: "District HQ"
        case .analytics: "Analytics"
        case .marketplace: "Phone numbers"
        case .billing: "Billing"
        case .rooms: "Rooms"
        case .workflows: "Workflows"
        case .desk: "Desk"
        case .dialer: "Dial"
        case .scheduling: "Scheduling"
        case .support: "Support"
        case .settings: "Workspace settings"
        case .account: "Account"
        }
    }

    /// The SF Symbol, the iPad's choice.
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .inbox: "tray"
        case .calls: "phone"
        case .contacts: "person.2"
        case .hq: "sparkles"
        case .analytics: "chart.bar"
        case .marketplace: "number"
        case .billing: "creditcard"
        case .rooms: "video"
        case .workflows: "flowchart"
        case .desk: "tray.full"
        case .dialer: "phone.arrow.up.right"
        case .scheduling: "calendar"
        case .support: "lifepreserver"
        case .settings: "gearshape"
        case .account: "person.crop.circle"
        }
    }

    /// The wave of the macOS plan that ports this section's screens, or nil when this
    /// build already shows the real section.
    var portedInWave: Int? {
        switch self {
        case .overview, .account, .inbox, .calls, .contacts, .rooms, .dialer, .hq, .analytics, .billing,
             .workflows, .desk, .support, .settings:
            nil
        case .marketplace: 8
        case .scheduling: 9
        }
    }

    /// The row's identifier, the iPad's (`A11yID.Sidebar`).
    var accessibilityID: String {
        switch self {
        case .overview: A11yID.Sidebar.overview
        case .inbox: A11yID.Sidebar.inbox
        case .calls: A11yID.Sidebar.calls
        case .contacts: A11yID.Sidebar.contacts
        case .hq: A11yID.Sidebar.hq
        case .analytics: A11yID.Sidebar.analytics
        case .marketplace: A11yID.Sidebar.marketplace
        case .billing: A11yID.Sidebar.billing
        case .rooms: A11yID.Sidebar.rooms
        case .workflows: A11yID.Sidebar.workflows
        case .desk: A11yID.Sidebar.desk
        case .dialer: A11yID.Sidebar.dialer
        case .scheduling: A11yID.Sidebar.scheduling
        case .support: A11yID.Sidebar.support
        case .settings: A11yID.Sidebar.settings
        case .account: A11yID.Sidebar.account
        }
    }

    /// What a list section's detail column says before a row is chosen, the iPad's
    /// words (`SidebarItem+Display.swift`); nil for a section with no list.
    var detailPlaceholder: (title: String, symbol: String)? {
        switch self {
        case .inbox: ("Select a conversation", "tray")
        case .calls: ("Select a call", "phone")
        case .contacts: ("Select a contact", "person.2")
        case .desk: ("Select a ticket", "tray.full")
        case .support: ("Select a request", "lifepreserver")
        case .overview, .account, .hq, .analytics, .marketplace, .billing, .rooms, .workflows, .dialer,
             .scheduling, .settings:
            nil
        }
    }

    /// ⌘1 to ⌘5 for the first five, as on the iPad with a keyboard.
    var shortcutDigit: Character? {
        switch self {
        case .overview: "1"
        case .inbox: "2"
        case .calls: "3"
        case .contacts: "4"
        case .account: "5"
        default: nil
        }
    }
}
