import AppKit
import SwiftUI

/// How a row of a card list (the Desk's tickets, Support's requests) draws its selection.
///
/// ⛔ THE ROW DRAWS IT, INSIDE ITS OWN BOUNDS, AND THE SYSTEM'S BAND IS OFF. A Mac `List`
/// paints its accent band across the whole column, gutters included, so a selected ticket
/// cut the card's rounded outline open (3.0.1 visual QA, Desk 22-ticket). The band is
/// switched off at the table (``SystemRowHighlightOff``) and the row paints the same accent
/// inside the card, or inside the gutters on Support, with white ink.
///
/// ⚠️ ONLY IN THE KEY WINDOW. Elsewhere a Mac shows a selection in pale grey with the
/// row's own colours; the row keeps the palette's tint there, as before.
enum RowSelection: Equatable {
    case none
    /// Not the key window: the palette's tint, the row's own inks.
    case tint
    /// The key window: the system's selection colour, white ink.
    case accent

    static func look(selected: Bool, controlActive: ControlActiveState) -> RowSelection {
        guard selected else { return .none }
        return controlActive == .key ? .accent : .tint
    }

    /// ⛔ THE ROW SETS THE PROMINENCE ITS INKS READ (``SelectionInk``), rather than taking
    /// the system's: with the band off, the row is the only thing that knows it is
    /// painted with the accent.
    var prominence: BackgroundProminence {
        self == .accent ? .increased : .standard
    }

    /// The accent: the colour the system selects with, which white text clears in either
    /// appearance (`SelectionInkTests`). The palette's teal takes dark ink in dark mode.
    static let accentFill = Color(nsColor: .selectedContentBackgroundColor)
}

/// A Support row's selection: the accent or the tint as a rounded shape inside the
/// gutters, and the prominence its inks read.
struct SelectedRowGround: ViewModifier {
    let selected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActive

    func body(content: Content) -> some View {
        let look = RowSelection.look(selected: selected, controlActive: controlActive)
        let colors = DistrictColors.resolve(colorScheme)
        let shape = RoundedRectangle(cornerRadius: DistrictRadius.control)
        return content
            .environment(\.backgroundProminence, look.prominence)
            .background {
                switch look {
                case .none: Color.clear
                case .tint: shape.fill(colors.district.opacity(DistrictColors.containerAlpha))
                case .accent: shape.fill(RowSelection.accentFill)
                }
            }
    }
}

/// Switches off the Mac `List`'s own selection band for the table a row sits in.
///
/// ⚠️ THE SELECTION STAYS: arrow keys, the click and the split view's binding are the
/// table's, and only its drawing is off (`NSTableView.SelectionHighlightStyle.none`, on the
/// table and on the row's own row view, which keeps a copy). Every stacked row carries one,
/// so a row view the table makes later is covered when its row appears.
struct SystemRowHighlightOff: NSViewRepresentable {
    func makeNSView(context _: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ probe: Probe, context _: Context) {
        probe.apply()
    }

    /// An empty view that finds its row view and table among its ancestors.
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// It takes no clicks: the row under it does.
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        func apply() {
            var ancestor = superview
            while let view = ancestor {
                if let row = view as? NSTableRowView {
                    row.selectionHighlightStyle = .none
                }
                if let table = view as? NSTableView {
                    table.selectionHighlightStyle = .none
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
