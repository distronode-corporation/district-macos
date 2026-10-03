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

    /// The parity checklist: which sections this build draws for real.
    func testTheSectionsPortedSoFar() {
        let ported = SidebarItem.allCases.filter { $0.portedInWave == nil }
        XCTAssertEqual(ported, [
            .overview, .inbox, .calls, .contacts, .hq, .analytics, .billing, .rooms, .workflows, .desk,
            .dialer, .support, .account,
        ])
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

final class SchedulingHandoffNoticeTests: XCTestCase {
    func testTheServersNonceSentenceWins() {
        XCTAssertEqual(SchedulingHandoffModel.notice(for: .nonceRequired(message: "Server words.")), "Server words.")
        XCTAssertEqual(
            SchedulingHandoffModel.notice(for: .nonceRequired(message: nil)),
            "Update the app to open the website from it."
        )
        XCTAssertEqual(
            SchedulingHandoffModel.notice(for: .api(.http(status: 409, message: nil))),
            "Scheduling is not ready yet. Turn it on, or wait for setup to finish."
        )
    }
}
