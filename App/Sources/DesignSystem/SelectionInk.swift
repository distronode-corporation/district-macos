import SwiftUI

/// What a row's own colours turn into when the row is selected.
///
/// ⛔ A SELECTED ROW IN A KEY WINDOW IS THE ACCENT COLOUR, AND THE PALETTE'S INKS ARE NOT
/// MADE FOR IT. The Calls table, the Contacts table and the Inbox drew their status chips
/// (green « Terminé » on a 12% green tint) and their muted preview text on the blue
/// selection, where they could not be read (the 3.0.1 visual QA, en-US 03-thread and fr-CA
/// 07-call-detail). Plain `Text` in the same rows turned white on its own, because the system
/// styles resolve against ``EnvironmentValues/backgroundProminence``; a fixed `Color` does
/// not. So everything a row tints reads that value and, when it is `.increased`, draws the
/// way a native Mac list does: white ink, the hierarchical system styles for text, and a
/// chip that keeps its shape as a white outline.
///
/// ⛔ AN OUTLINE, NOT A TRANSLUCENT WHITE FILL. White at 22% over the selection lifted the
/// ground under the label until white text on it measured 3.7:1 on the light selection,
/// short of AA for a 12pt label; with no fill the label is white on the selection itself,
/// the pair the system draws its own selected text in. `SelectionInkTests` measures it
/// against the real `selectedContentBackgroundColor` in both appearances.
///
/// ⚠️ ONLY `.increased`. A selected row in a window that is not key is a pale grey, on which
/// the palette's own colours read as they do anywhere else, and SwiftUI reports `.standard`
/// there.
enum SelectionInk {
    /// The chip's outline on a selected row, which keeps its shape on any accent colour.
    static let chipOutlineAlpha: CGFloat = 0.75

    /// Whether `prominence` is a selected row's, which the palette's colours cannot sit on.
    static func onSelection(_ prominence: BackgroundProminence) -> Bool {
        prominence == .increased
    }

    /// A ``DistrictBadge``'s (and a ``DistrictAvatar``'s) fill.
    static func chipFill(
        _ tone: Tone,
        _ colors: DistrictColors,
        increasedContrast: Bool,
        prominence: BackgroundProminence
    ) -> Color {
        guard onSelection(prominence) else { return tone.fill(colors, increasedContrast: increasedContrast) }
        return Color.clear
    }

    /// The chip's outline: white on a selected row, none elsewhere.
    static func chipOutline(_ prominence: BackgroundProminence) -> Color? {
        onSelection(prominence) ? Color.white.opacity(chipOutlineAlpha) : nil
    }

    /// A ``DistrictBadge``'s (and a ``DistrictAvatar``'s) ink.
    static func chipInk(
        _ tone: Tone,
        _ colors: DistrictColors,
        increasedContrast: Bool,
        prominence: BackgroundProminence
    ) -> Color {
        onSelection(prominence) ? Color.white : tone.chipInk(colors, increasedContrast: increasedContrast)
    }
}

/// Which of a row's two text inks: the name, or the line under it.
enum RowInkLevel {
    case primary
    case secondary
}

extension View {
    /// Row text in the palette's `color`, or in the system's hierarchical style of `level`
    /// on a selected row (``SelectionInk``).
    func rowInk(_ color: Color, _ level: RowInkLevel) -> some View {
        modifier(RowInkModifier(color: color, level: level))
    }
}

private struct RowInkModifier: ViewModifier {
    let color: Color
    let level: RowInkLevel

    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        if SelectionInk.onSelection(prominence) {
            switch level {
            case .primary: content.foregroundStyle(.primary)
            case .secondary: content.foregroundStyle(.secondary)
            }
        } else {
            content.foregroundStyle(color)
        }
    }
}
