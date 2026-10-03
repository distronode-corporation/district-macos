import Foundation

/// Every top-level section of the Mac shell, in sidebar order.
///
/// ⛔ THE SAME SIXTEEN SECTIONS, IN THE SAME ORDER, AS THE iPad SIDEBAR (district-ios
/// `Navigation/SidebarItem.swift` and `OverviewEntry.all`, at gh/main 0b2354b): the four
/// list tabs, the twelve hubs in Overview's order, then Account. v1 of the Mac app is
/// iPad parity, and this enum is the checklist that parity is measured against.
/// `SidebarItemTests` pins the count and the order.
///
/// ⚠️ ROLE GATES ARE NOT APPLIED YET. The iPad hides a hub a role cannot open
/// (`RouteGate`); that arrives with the ported screens in Waves 5 to 9, since a
/// placeholder has nothing to gate.
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
        case .overview, .account: nil
        case .inbox, .calls, .contacts: 5
        case .rooms, .dialer: 6
        case .hq, .analytics, .billing, .workflows, .desk, .support: 7
        case .settings, .marketplace: 8
        case .scheduling: 9
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
