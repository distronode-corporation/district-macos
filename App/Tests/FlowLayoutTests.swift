@testable import DistrictMac
import SwiftUI
import XCTest

/// ``FlowLayout``, which wraps the Desk's status chips, and ``StackedRow/insets``, which
/// keeps a Mac `List` from cutting a card in two (3.0.1 visual QA, Desk).
final class FlowLayoutTests: XCTestCase {
    /// The four French chips as the capture measured them: « Tout 3 », « Ouvert 1 »,
    /// « En attente du client 1 », « Réglé 1 ».
    private let frenchChips = [62.0, 74.0, 148.0, 67.0].map { CGSize(width: $0, height: 44) }

    /// ⛔ AT THE COLUMN THE CAPTURE HAD (371pt), « Réglé 1 » GOES TO A SECOND LINE, WHOLE,
    /// where the scroller cut it at the edge.
    func test_FLOW_1_theLastFrenchChipWrapsWhole() {
        let laid = FlowLayout.arrange(sizes: frenchChips, width: 371, spacing: 8, lineSpacing: 8)
        XCTAssertEqual(laid.frames.map(\.minY), [0, 0, 0, 52])
        XCTAssertEqual(laid.frames[3], CGRect(x: 0, y: 52, width: 67, height: 44))
        XCTAssertEqual(laid.size, CGSize(width: 371, height: 96))
    }

    /// ⛔ NO CHIP EVER RUNS PAST THE LINE, at any width from a phone's to a wide column's.
    func test_FLOW_2_everyChipIsInsideTheLineAtEveryWidth() {
        for width in stride(from: 150.0, through: 640.0, by: 1.0) {
            let laid = FlowLayout.arrange(sizes: frenchChips, width: width, spacing: 8, lineSpacing: 8)
            for frame in laid.frames {
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(width)")
                XCTAssertLessThanOrEqual(frame.maxX, width, "\(width)")
                XCTAssertEqual(frame.size, CGSize(width: frame.width, height: 44), "\(width)")
            }
            XCTAssertEqual(laid.frames.count, 4)
        }
    }

    /// ⚠️ ROOM FOR ALL OF THEM IS ONE LINE, and no width offered is one line too.
    func test_FLOW_3_oneLineWhenItFits() {
        let wide = FlowLayout.arrange(sizes: frenchChips, width: 400, spacing: 8, lineSpacing: 8)
        XCTAssertEqual(wide.frames.map(\.minX), [0, 70, 152, 308])
        XCTAssertEqual(wide.size.height, 44)
        let free = FlowLayout.arrange(sizes: frenchChips, width: nil, spacing: 8, lineSpacing: 8)
        XCTAssertEqual(free.size, CGSize(width: 375, height: 44))
    }

    /// ⚠️ A VIEW WIDER THAN THE LINE GETS A LINE OF ITS OWN AT THE LINE'S WIDTH, as tall as
    /// it measures there, and nothing is a frame when there is nothing to lay out.
    func test_FLOW_4_aViewWiderThanTheLineIsRefitted() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 500, height: 20)]
        let laid = FlowLayout.arrange(sizes: sizes, width: 300, spacing: 8, lineSpacing: 4) { index, offered in
            XCTAssertEqual(index, 1)
            return CGSize(width: offered, height: 40)
        }
        XCTAssertEqual(laid.frames[1], CGRect(x: 0, y: 24, width: 300, height: 40))
        XCTAssertEqual(laid.size, CGSize(width: 300, height: 64))
        let unmeasured = FlowLayout.arrange(sizes: [sizes[1]], width: 300, spacing: 8, lineSpacing: 4)
        XCTAssertEqual(unmeasured.frames, [CGRect(x: 0, y: 0, width: 300, height: 20)])
        let none = FlowLayout.arrange(sizes: [], width: 300, spacing: 8, lineSpacing: 4)
        XCTAssertEqual(none.size, CGSize(width: 300, height: 0))
    }

    /// ⛔ A STACKED ROW'S LIST INSETS ARE ZERO ABOVE AND BELOW: a Mac `List` repeats the top
    /// inset under the row, which is what cut the Desk's ticket card in two. The gaps are
    /// padding (``View/stackedListRow(top:bottom:)``).
    func test_FLOW_5_stackedRowsHaveNoVerticalInsets() {
        XCTAssertEqual(StackedRow.insets.top, 0)
        XCTAssertEqual(StackedRow.insets.bottom, 0)
        XCTAssertEqual(StackedRow.insets.leading, DistrictSpacing.gutter)
        XCTAssertEqual(StackedRow.insets.trailing, DistrictSpacing.gutter)
    }
}
