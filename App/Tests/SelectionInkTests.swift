import AppKit
@testable import DistrictMac
import SwiftUI
import XCTest

/// What a row's chips and text draw on a selected row (``SelectionInk``): the 3.0.1 visual QA
/// found the status chips and the Inbox preview unreadable on the blue selection.
@MainActor
final class SelectionInkTests: XCTestCase {
    private let colors = DistrictColors.resolve(.light)

    /// ⛔ ON A SELECTED ROW EVERY TONE'S CHIP IS WHITE INK IN A WHITE OUTLINE ON NO FILL, in
    /// either contrast setting, whatever the tone said off the selection.
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
                    .clear,
                    "\(tone) \(increased)"
                )
            }
        }
        XCTAssertEqual(SelectionInk.chipOutline(.increased), Color.white.opacity(SelectionInk.chipOutlineAlpha))
    }

    /// ⚠️ OFF THE SELECTION, AND ON A SELECTED ROW OF A WINDOW THAT IS NOT KEY (`.standard`),
    /// THE CHIP IS THE TONE'S OWN, Increase Contrast included, with no outline.
    func test_SELECTION_2_anUnselectedChipKeepsItsTone() {
        for tone in Tone.allCases {
            for increased in [false, true] {
                XCTAssertEqual(
                    SelectionInk.chipInk(tone, colors, increasedContrast: increased, prominence: .standard),
                    tone.chipInk(colors, increasedContrast: increased),
                    "\(tone) \(increased)"
                )
                XCTAssertEqual(
                    SelectionInk.chipFill(tone, colors, increasedContrast: increased, prominence: .standard),
                    tone.fill(colors, increasedContrast: increased),
                    "\(tone) \(increased)"
                )
            }
        }
        XCTAssertNil(SelectionInk.chipOutline(.standard))
    }

    /// ⚠️ ONLY `.increased` IS A SELECTION THE PALETTE CANNOT SIT ON.
    func test_SELECTION_3_onlyAnIncreasedBackgroundIsASelection() {
        XCTAssertTrue(SelectionInk.onSelection(.increased))
        XCTAssertFalse(SelectionInk.onSelection(.standard))
    }

    /// ⛔ THE LABEL IS WHITE ON THE SYSTEM'S OWN SELECTION, AND THAT CLEARS AA in both
    /// appearances: the colour is read from AppKit, not declared here.
    func test_SELECTION_4_whiteOnTheSelectionClearsAA() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var selection = NSColor.black
            appearance.performAsCurrentDrawingAppearance {
                selection = NSColor.selectedContentBackgroundColor.usingColorSpace(.sRGB) ?? .black
            }
            let ratio = Self.contrast(.white, selection)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name.rawValue): white on the selection is \(ratio):1")
        }
    }

    private static func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    private static func contrast(_ one: NSColor, _ other: NSColor) -> Double {
        let first = luminance(one)
        let second = luminance(other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
