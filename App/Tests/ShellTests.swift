@testable import DistrictMac
import XCTest

/// The sidebar is the iPad-parity checklist, so its count, order and wording are pinned.
final class SidebarItemTests: XCTestCase {
    func testSixteenSectionsInTheiPadOrder() {
        XCTAssertEqual(SidebarItem.allCases.map(\.title), [
            "Overview", "Inbox", "Calls", "Contacts",
            "District HQ", "Analytics", "Phone numbers", "Billing", "Rooms", "Workflows",
            "Desk", "Dial", "Scheduling", "Support", "Workspace settings",
            "Account",
        ])
    }

    func testOnlyOverviewAndAccountArePortedInThisWave() {
        let ported = SidebarItem.allCases.filter { $0.portedInWave == nil }
        XCTAssertEqual(ported, [.overview, .account])
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

final class DevicesCopyTests: XCTestCase {
    func testPlatformNamesIncludeTheMac() {
        XCTAssertEqual(DevicesModel.platformName("macos"), "Mac")
        XCTAssertEqual(DevicesModel.platformName("ios"), "iPhone or iPad")
        XCTAssertEqual(DevicesModel.platformName("plan9"), "plan9", "an unknown platform is shown as sent")
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
