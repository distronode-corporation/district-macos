@testable import DistrictMac
import XCTest

/// The pure formatting behind the Analytics and Billing cards.
///
/// ⚠️ MAC ONLY: district-ios has no test for these, and they decide what a person reads
/// about a bill. Every expectation is the behaviour the iOS source documents (and Android
/// shares), not a Mac choice.
final class MacAnalyticsBillingFormatTests: XCTestCase {
    func test_MAC_FORMAT_1_durationsReadAsMinutesAndSeconds() {
        XCTAssertEqual(AnalyticsFormat.duration(seconds: 0), "0s")
        XCTAssertEqual(AnalyticsFormat.duration(seconds: 59), "59s")
        XCTAssertEqual(AnalyticsFormat.duration(seconds: 65), "1m 5s")
        // A negative figure is a server fault, not a negative call.
        XCTAssertEqual(AnalyticsFormat.duration(seconds: -4), "0s")
    }

    /// ⚠️ ONE DECIMAL WHEN THE SECOND IS ZERO, always a `.`, and a non-finite value is
    /// "Not metered", never "nan".
    func test_MAC_FORMAT_2_meteredAmountsMatchTheOtherClients() {
        XCTAssertEqual(AnalyticsFormat.amount(318.5), "318.5")
        XCTAssertEqual(AnalyticsFormat.amount(318.25), "318.25")
        XCTAssertEqual(AnalyticsFormat.amount(12), "12")
        XCTAssertEqual(AnalyticsFormat.amount(.nan), AnalyticsFormat.absent)
    }

    /// ⛔ nil WHEN NOTHING WAS METERED, which is not zero minutes.
    func test_MAC_FORMAT_3_aSumOfNothingMeteredIsAbsent() {
        XCTAssertNil(AnalyticsFormat.sumMetered(nil, nil))
        XCTAssertEqual(AnalyticsFormat.sumMetered(nil, 2.5, .infinity, 1), 3.5)
    }

    func test_MAC_FORMAT_4_aQuietSeriesPlotsFlatRatherThanDividingByZero() {
        XCTAssertEqual(AnalyticsFormat.normalized([0, nil, 0]), [0, 0, 0])
        XCTAssertEqual(AnalyticsFormat.normalized([2, nil, 4, -1]), [0.5, 0, 1, 0])
    }

    func test_MAC_FORMAT_5_monthLabelsAndTheirFallbacks() {
        XCTAssertEqual(AnalyticsFormat.monthLabel("2026-09"), "Sep 2026")
        XCTAssertEqual(AnalyticsFormat.monthLabel("2026-13"), "2026-13")
        XCTAssertEqual(AnalyticsFormat.monthLabel("September"), "September")
    }

    func test_MAC_FORMAT_6_hexColoursAcceptShortFormsAndRefuseJunk() {
        XCTAssertNotNil(AnalyticsFormat.hexColor("#0E1C1F"))
        XCTAssertNotNil(AnalyticsFormat.hexColor("abc"))
        XCTAssertNil(AnalyticsFormat.hexColor("#12345"))
        XCTAssertNil(AnalyticsFormat.hexColor("zzzzzz"))
    }

    func test_MAC_FORMAT_7_moneyIsCentsWithoutFloatingPoint() {
        XCTAssertEqual(BillingFormat.money(cents: 0), "0.00")
        XCTAssertEqual(BillingFormat.money(cents: 2505), "25.05")
        XCTAssertEqual(BillingFormat.money(cents: -199), "-1.99")
        // ⚠️ `Int.min` must not trap (the remainder is taken before `abs`).
        XCTAssertFalse(BillingFormat.money(cents: Int.min).isEmpty)
    }

    func test_MAC_FORMAT_8_theMeterIsClampedAndNeverInventsAnAllowance() {
        XCTAssertEqual(BillingFormat.meterFraction(used: 50, included: 100), 0.5)
        XCTAssertEqual(BillingFormat.meterFraction(used: 500, included: 100), 1)
        XCTAssertEqual(BillingFormat.meterFraction(used: 50, included: 0), 0)
        XCTAssertEqual(BillingFormat.meterFraction(used: .nan, included: 100), 0)
        XCTAssertNil(BillingFormat.includedMinutes(nil))
    }

    func test_MAC_FORMAT_9_statusesAreComparedTrimmedAndLowercased() {
        XCTAssertEqual(BillingFormat.normalisedStatus(" Past_Due \n"), BillingFormat.subscriptionStatusPastDue)
        XCTAssertEqual(BillingFormat.normalisedStatus(nil), "")
    }
}
