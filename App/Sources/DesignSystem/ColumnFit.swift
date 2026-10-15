import AppKit
import SwiftUI

/// The width a table column needs for the longest value it can show, measured in the font
/// the cell draws it in.
///
/// ⛔ MEASURED, NOT GUESSED. The Calls table's Status column was a fixed 92pt, which held
/// "No answer" and clipped « Sans réponse » and « Échec du transfert », and a French
/// Duration that a fixed 56pt had cut (« 2 min 3… ») was patched to 72 by hand (3.0.1 visual
/// QA). A column sized from the strings in the active language fits whichever language is
/// showing, and the list column's minimum follows (``ListColumnWidth``).
///
/// ⚠️ THE SYSTEM FONT IS THE ONE SwiftUI DRAWS: ``DistrictType`` sets `.system(size:weight:)`
/// and a table cell with no font draws at the system's 13pt body, and a Mac has no Dynamic
/// Type to scale either. `ColumnFitTests` pins the arithmetic against real strings.
enum ColumnFit {
    /// A table cell's text with no font of its own: the Mac body size.
    static let cellSize: CGFloat = NSFont.systemFontSize

    /// The widest of `strings` at `size` and `weight`, rounded up to a whole point.
    static func text(
        _ strings: [String],
        size: CGFloat = cellSize,
        weight: NSFont.Weight = .regular,
        monospacedDigits: Bool = false
    ) -> CGFloat {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        let widest = strings.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return widest.rounded(.up)
    }

    /// The widest ``DistrictBadge`` of `labels`: its label at ``DistrictType/label`` and its
    /// padding on both sides, plus a point for the antialiased edge.
    static func badge(_ labels: [String]) -> CGFloat {
        text(labels, size: DistrictType.label.size, weight: .semibold) + 2 * DistrictSpacing.tight + 1
    }

    /// A column header's title, which sits beside the sort arrow.
    static func header(_ title: String) -> CGFloat {
        text([title], size: NSFont.smallSystemFontSize, weight: .medium) + headerArrow
    }

    /// The header's sort indicator and the gap before it.
    static let headerArrow: CGFloat = 16

    /// The width a table of `columns` needs: each column's own width, plus 17pt of cell
    /// spacing per column and 15pt of row inset, read off the real `NSTableView`
    /// (``ListColumnWidth``).
    static func table(_ columns: [CGFloat]) -> CGFloat {
        columns.reduce(0, +) + columnSpacing * CGFloat(columns.count) + rowInset
    }

    static let columnSpacing: CGFloat = 17
    static let rowInset: CGFloat = 15
}
