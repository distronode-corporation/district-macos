import DistrictL10n
@testable import DistrictMac
import XCTest

/// The Mac country list's rows and its keyboard: what is listed in which order, and where
/// the arrow keys land.
///
/// ⚠️ THE ROWS AND THE MOVES ARE STATIC FUNCTIONS so they are pinned here without a window;
/// the popover itself is seen in the pull request's screenshots.
@MainActor
final class MacDialerCountryPickerTests: XCTestCase {
    /// ⛔ SUGGESTED FIRST: the home country, the one on screen, then Canada and the US, each
    /// once; then every country.
    func testWithNoSearchSuggestedComesFirstThenEveryCountry() {
        let rows = DialerCountryPicker.rows(query: "", home: "FR", selected: "GB")
        XCTAssertEqual(rows.prefix(4).map(\.iso), ["FR", "GB", "CA", "US"])
        XCTAssertEqual(rows.prefix(4).map(\.section), Array(repeating: "suggested", count: 4))
        XCTAssertEqual(rows.count, 4 + DialPlan.countries.count)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "a country listed twice is two rows")
    }

    /// ⛔ THE SCREENSHOT'S SEARCH: "germ" finds Germany and nothing else, in English, and
    /// "allem" finds it in French.
    func testASearchListsOnlyTheMatches() {
        XCTAssertEqual(DialerCountryPicker.rows(query: "germ", home: "CA", selected: "CA").map(\.iso), ["DE"])
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(DialerCountryPicker.rows(query: "allem", home: nil, selected: nil).map(\.iso), ["DE"])
        }
        XCTAssertTrue(DialerCountryPicker.rows(query: "zzzz", home: nil, selected: nil).isEmpty)
    }

    func testTheArrowKeysMoveThroughTheRowsAndStopAtTheEnds() {
        let rows = DialerCountryPicker.rows(query: "united", home: nil, selected: nil)
        XCTAssertGreaterThan(rows.count, 2)
        XCTAssertEqual(DialerCountryPicker.move(from: nil, by: 1, in: rows), rows.first?.id)
        XCTAssertEqual(DialerCountryPicker.move(from: nil, by: -1, in: rows), rows.last?.id)
        XCTAssertEqual(DialerCountryPicker.move(from: rows[0].id, by: 1, in: rows), rows[1].id)
        XCTAssertEqual(DialerCountryPicker.move(from: rows[0].id, by: -1, in: rows), rows[0].id)
        XCTAssertEqual(DialerCountryPicker.move(from: rows.last?.id, by: 1, in: rows), rows.last?.id)
        XCTAssertNil(DialerCountryPicker.move(from: nil, by: 1, in: []))
    }
}
