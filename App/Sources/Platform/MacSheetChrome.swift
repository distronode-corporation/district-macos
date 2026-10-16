import SwiftUI

/// A Mac sheet's title bar and button bar, drawn by the app on the palette.
///
/// ⛔ NO `NavigationStack` AND NO TOOLBAR IN A SHEET. A stack's title and its
/// `.cancellationAction` and `.confirmationAction` items are drawn by macOS in bars of its
/// own, in the system's sheet grey (#1E1E1E in dark, #FFFFFF and #ECECEC in light), and
/// ``View/macSheetBackground()`` paints only the content between them (3.0.2 walk 2, on
/// Desk settings, New message and the workspace picker). Edit working hours never had
/// those bars (``SchedulingWriteSheet``) and passed; this is its shape for every other
/// sheet: the title, the content, then one bottom trailing row of buttons, all of it on
/// the page colour. `MacSheetFitTests` fails a sheet that draws a stack or a toolbar.
///
/// ⚠️ THE BUTTONS CARRY THEIR OWN KEYS, because a button outside a toolbar gets none from
/// its placement: a Cancel takes `.cancelAction` (Esc), a Done takes `.defaultAction`
/// (Return), and a compose's send keeps ``KeyboardShortcut/districtSubmit`` (⌘↩), as it
/// did in the toolbar.
///
/// ⚠️ IT PAINTS ITSELF (``View/macSheetBackground()`` and the palette under its bars), so a
/// sheet drawn in it is on the palette whatever its presentation site does.
struct MacSheetChrome<Content: View, Buttons: View>: View {
    let title: String
    private let content: Content
    private let buttons: Buttons

    @Environment(\.colorScheme) private var colorScheme

    /// ⛔ `content` AND `buttons` ARE LAST AND CONTIGUOUS, so a call site uses multiple
    /// trailing closures (see the same note on ``SchedulingWriteSheet``).
    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.content = content()
        self.buttons = buttons()
    }

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(DistrictType.title)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DistrictSpacing.gutter)
                .padding(.vertical, DistrictSpacing.row)
                // ⚠️ THE SHEET'S HEADING FOR VoiceOver, as ``SchedulingWriteSheet``'s is.
                .accessibilityAddTraits(.isHeader)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack(spacing: DistrictSpacing.tight) {
                Spacer(minLength: 0)
                buttons
            }
            .padding(DistrictSpacing.gutter)
        }
        .background(colors.background)
        .macSheetBackground()
    }
}

/// The one default button of a Mac sheet's button row: the palette's accent, filled.
///
/// ⚠️ A TOOLBAR'S `.confirmationAction` WAS DRAWN AS THE DEFAULT BUTTON BY macOS; outside a
/// toolbar it is this style, the same as ``SchedulingWriteSheet``'s confirm.
struct MacSheetDefaultButton: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(DistrictColors.resolve(colorScheme).district)
    }
}

extension View {
    /// Draws a sheet's default button in the palette's accent (``MacSheetDefaultButton``).
    func macSheetDefaultButton() -> some View {
        modifier(MacSheetDefaultButton())
    }
}
