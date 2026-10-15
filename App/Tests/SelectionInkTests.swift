@testable import DistrictMac
import SwiftUI
import XCTest

/// What a row's chips and text draw on a selected row (``SelectionInk``): the 3.0.1 visual QA
/// found the status chips and the Inbox preview unreadable on the blue selection.
@MainActor
final class SelectionInkTests: XCTestCase {
    private let colors = DistrictColors.resolve(.light)

    /// ⛔ ON A SELECTED ROW EVERY TONE'S CHIP IS WHITE ON TRANSLUCENT WHITE, in either contrast
    /// setting, whatever the tone said off the selection.
    func test_SELECTION_1_aSelectedRowsChipIsWhite() {
        for tone in Tone.allCases {
            for increased in [false, true] {
                XCTAssertEqual(
                    SelectionInk.chipInk(tone, colors, increasedContrast: increased, prominence: .increased),
                    .white,
                    "\(tone) \(increased)"
                )
                XCTAssertEqual(
                    SelectionInk.chipFill(tone, colors, increasedContrast: increased, prominence: .increased),
                    Color.white.opacity(SelectionInk.chipFillAlpha),
                    "\(tone) \(increased)"
                )
            }
        }
    }

    /// ⚠️ OFF THE SELECTION, AND ON A SELECTED ROW OF A WINDOW THAT IS NOT KEY (`.standard`),
    /// THE CHIP IS THE TONE'S OWN, Increase Contrast included.
    func test_SELECTION_2_anUnselectedChipKeepsItsTone() {
        for tone in Tone.allCases {
            for increased in [false, true] {
                XCTAssertEqual(
                    SelectionInk.chipInk(tone, colors, increasedContrast: increased, prominence: .standard),
                    tone.ink(colors, increasedContrast: increased),
                    "\(tone) \(increased)"
                )
                XCTAssertEqual(
                    SelectionInk.chipFill(tone, colors, increasedContrast: increased, prominence: .standard),
                    tone.fill(colors, increasedContrast: increased),
                    "\(tone) \(increased)"
                )
            }
        }
    }

    /// ⚠️ ONLY `.increased` IS A SELECTION THE PALETTE CANNOT SIT ON.
    func test_SELECTION_3_onlyAnIncreasedBackgroundIsASelection() {
        XCTAssertTrue(SelectionInk.onSelection(.increased))
        XCTAssertFalse(SelectionInk.onSelection(.standard))
        XCTAssertGreaterThan(SelectionInk.chipFillAlpha, 0)
        XCTAssertLessThan(SelectionInk.chipFillAlpha, 0.5, "translucent, so the label stays the strongest mark")
    }
}
