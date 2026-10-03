@testable import DistrictMac
import XCTest

/// The sidebar is the iPad-parity checklist, so its count, order and wording are pinned.
final class MacSidebarItemTests: XCTestCase {
    func testSixteenSectionsInTheiPadOrder() {
        XCTAssertEqual(SidebarItem.allCases.map(\.title), [
            "Overview", "Inbox", "Calls", "Contacts",
            "District HQ", "Analytics", "Phone numbers", "Billing", "Rooms", "Workflows",
            "Desk", "Dial", "Scheduling", "Support", "Workspace settings",
            "Account",
        ])
    }

    /// The parity checklist: every section is drawn for real (Wave 9 ported the last,
    /// Scheduling). A section the shell draws through ``RouteDestinations`` must have a root
    /// route, or ``ShellView`` would draw nothing for it.
    func testEverySectionIsPorted() {
        let drawnByRoute = SidebarItem.allCases.filter { $0 != .overview && $0 != .account && !$0.isListSection }
        for item in drawnByRoute {
            XCTAssertNotNil(item.rootRoute(workspaceId: "ws_1", role: .viewer), "\(item)")
        }
        XCTAssertEqual(
            SidebarItem.scheduling.rootRoute(workspaceId: "ws_1", role: .client),
            .scheduling(workspaceId: "ws_1", role: .client, section: .hub)
        )
    }

    func testCommandDigitsAreTheiPadTabOrder() {
        let digits = SidebarItem.allCases.compactMap { item in item.shortcutDigit.map { (item, $0) } }
        XCTAssertEqual(digits.map(\.0), [.overview, .inbox, .calls, .contacts, .account])
        XCTAssertEqual(digits.map(\.1), ["1", "2", "3", "4", "5"])
    }

    func testEverySectionHasASymbol() {
        for item in SidebarItem.allCases {
            XCTAssertFalse(item.symbol.isEmpty, "\(item)")
        }
    }
}

final class MacDeviceNameTests: XCTestCase {
    func testBlankNamesAreOmittedAndLongOnesFitTheRoute() {
        XCTAssertNil(MacDeviceName.usable("   \n"))
        XCTAssertEqual(MacDeviceName.usable("  Studio Mac "), "Studio Mac")
        XCTAssertEqual(MacDeviceName.usable(String(repeating: "m", count: 300))?.count, 120)
    }
}

final class DistrictSentryTests: XCTestCase {
    func testABlankOrUnsubstitutedDSNKeepsTheSDKOff() {
        XCTAssertNil(DistrictSentry.usable(""))
        XCTAssertNil(DistrictSentry.usable("$(SENTRY_DSN)"))
        XCTAssertEqual(DistrictSentry.usable(" https://k@o.example.com/1 "), "https://k@o.example.com/1")
    }

    func testTheTestHostCarriesNoDSN() {
        XCTAssertNil(DistrictSentry.configuredValue(.main, forKey: DistrictSentry.dsnInfoKey))
    }
}
