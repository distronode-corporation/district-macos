import AppKit
@testable import DistrictMac
import SwiftUI
import XCTest

/// The card lists' own selection (``RowSelection``), drawn inside the card with the
/// system's band switched off (``SystemRowHighlightOff``), 3.0.1 visual QA, Desk and Support.
@MainActor
final class RowSelectionTests: XCTestCase {
    /// ⛔ THE ACCENT ONLY ON A SELECTED ROW IN THE KEY WINDOW; THE TINT IN ANY OTHER WINDOW
    /// STATE; NOTHING ON A ROW THAT IS NOT SELECTED.
    func test_ROWSEL_1_theLookFollowsTheWindow() {
        XCTAssertEqual(RowSelection.look(selected: true, controlActive: .key), .accent)
        XCTAssertEqual(RowSelection.look(selected: true, controlActive: .active), .tint)
        XCTAssertEqual(RowSelection.look(selected: true, controlActive: .inactive), .tint)
        for state in [ControlActiveState.key, .active, .inactive] {
            XCTAssertEqual(RowSelection.look(selected: false, controlActive: state), RowSelection.none)
        }
    }

    /// ⛔ WHITE INK (`.increased`) ONLY ON THE ACCENT; the row's own inks everywhere else,
    /// whatever the system reports.
    func test_ROWSEL_2_onlyTheAccentTurnsTheInkWhite() {
        XCTAssertEqual(RowSelection.accent.prominence, .increased)
        XCTAssertEqual(RowSelection.tint.prominence, .standard)
        XCTAssertEqual(RowSelection.none.prominence, .standard)
        XCTAssertTrue(SelectionInk.onSelection(RowSelection.accent.prominence))
    }

    /// ⛔ THE PROBE SWITCHES OFF THE BAND ON ITS ROW VIEW AND ITS TABLE, and keeps the
    /// table's selection: only the drawing goes.
    func test_ROWSEL_3_theProbeTurnsOffTheTablesBand() {
        let table = NSTableView()
        let row = NSTableRowView()
        let cell = NSView()
        let probe = SystemRowHighlightOff.Probe()
        table.addSubview(row)
        row.addSubview(cell)
        cell.addSubview(probe)
        XCTAssertEqual(table.selectionHighlightStyle, .regular)
        probe.apply()
        XCTAssertEqual(table.selectionHighlightStyle, NSTableView.SelectionHighlightStyle.none)
        XCTAssertEqual(row.selectionHighlightStyle, NSTableView.SelectionHighlightStyle.none)
        XCTAssertTrue(table.allowsEmptySelection)
        XCTAssertNil(probe.hitTest(.zero))
    }

    /// ⚠️ OUTSIDE A TABLE THE PROBE DOES NOTHING, and an outline view (what a `List` is on
    /// the Mac) is a table.
    func test_ROWSEL_4_outsideATableNothingChanges() {
        let host = NSView()
        let probe = SystemRowHighlightOff.Probe()
        host.addSubview(probe)
        probe.apply()
        let outline = NSOutlineView()
        let inner = SystemRowHighlightOff.Probe()
        outline.addSubview(inner)
        inner.apply()
        XCTAssertEqual(outline.selectionHighlightStyle, NSTableView.SelectionHighlightStyle.none)
    }
}
