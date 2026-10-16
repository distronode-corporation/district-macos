import AppKit
import SwiftUI

/// The image type the ported screens hold, the Mac's `NSImage` where iOS has `UIImage`.
///
/// ⚠️ AN ALIAS, NOT A WRAPPER, so a file copied from district-ios changes one word.
/// `Image(platformImage:)` below is the one place SwiftUI is handed one.
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

/// The general pasteboard, where iOS writes `UIPasteboard.general.string`.
///
/// ⛔ `clearContents()` FIRST. An `NSPasteboard` keeps every type the last writer put on it,
/// so writing a string without clearing would leave, say, a copied image beside it and a
/// paste target would choose whichever type it prefers.
@MainActor
enum Clipboard {
    static func copy(_ value: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

/// Opens a page in the user's default browser, NAMED, never through Launch Services'
/// choice of handler for the URL.
///
/// ⛔ THE BROWSER IS NAMED BECAUSE THIS APP CLAIMS PART OF THE SITE. `applinks:www.distronode.com`
/// claims `/dashboard/district/*`, so a plain `NSWorkspace.open` (or SwiftUI's `openURL`)
/// of such a page could hand it straight back to this app: the relaunch loop the iOS
/// `FinishSetupCard` avoids with an in-app Safari sheet, which macOS does not have.
/// Asking Launch Services for the `https` handler and opening the page WITH that
/// application is the Mac's equivalent of Android's `launchExternally`.
///
/// ⚠️ NOTHING OPENS when no browser is registered for `https`, and the caller is told, so
/// it can say so rather than appear to do nothing.
@MainActor
enum BrowserHandOff {
    @discardableResult
    static func open(_ url: URL, workspace: NSWorkspace = .shared) -> Bool {
        guard let probe = URL(string: "https:"), let browser = workspace.urlForApplication(toOpen: probe) else {
            return false
        }
        workspace.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

/// The main window's smallest size, which every sheet has to fit inside.
enum MacWindowSize {
    /// The main window's minimum CONTENT height, below its title bar and toolbar (612pt
    /// tall as a whole window). Its minimum width is ``ListColumnWidth/windowMin``.
    static let minHeight: CGFloat = 560
}

/// How tall a sheet's own frame may be and still fit inside the smallest main window.
///
/// ⛔ A MAC SHEET IS NOT CLAMPED TO ITS WINDOW. It hangs from below the toolbar at
/// whatever height it asks for, so a sheet taller than the window runs past the bottom
/// edge and takes its buttons with it. The 3.0.2 visual walk measured the Desk settings
/// sheet, framed at 600pt, drawn 661pt tall in a window with 560pt of content: 101pt
/// below the edge, with Done among them.
///
/// ⚠️ THE 61pt OVER THE FRAME IS THE BAR A SHEET ADDS BELOW ITS CONTENT for its
/// `.cancellationAction` and `.confirmationAction` toolbar items. ``toolbarBar`` keeps a
/// few points over that measurement, and every sheet is allowed for it, with a bar or
/// not, so one cap holds for both shapes.
enum MacSheetFit {
    static let toolbarBar: CGFloat = 64
    /// 496pt: the minimum window's content height less the bar.
    static let maxHeight: CGFloat = MacWindowSize.minHeight - toolbarBar

    /// The height a sheet asking for `requested` opens at: its own, up to ``maxHeight``.
    /// The content scrolls inside it (every sheet capped here has a `ScrollView`).
    static func height(_ requested: CGFloat) -> CGFloat {
        min(requested, maxHeight)
    }
}

extension View {
    /// The size a sheet opens at on the Mac.
    ///
    /// ⚠️ A MAC SHEET HAS NO SIZE OF ITS OWN: it takes its content's ideal size, which for
    /// a form of flexible fields is either a sliver or the whole window. Each ported sheet
    /// states one at its presentation site; the iPad's sheets need none.
    ///
    /// ⛔ THE HEIGHT IS CAPPED BY ``MacSheetFit``, AND A MAXIMUM IS SET AS WELL AS A
    /// MINIMUM, so neither a tall request nor tall content can push the sheet, or its
    /// Done, past the bottom of the smallest window.
    ///
    /// ⛔ AND IT PAINTS THE SHEET (``View/macSheetBackground()``), so a sized sheet cannot
    /// be a sheet without the palette.
    func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        let fitted = MacSheetFit.height(height)
        return frame(
            minWidth: width,
            idealWidth: width,
            minHeight: fitted,
            idealHeight: fitted,
            maxHeight: fitted
        )
        .macSheetBackground()
    }

    /// The palette's page colour under a sheet, the colour the app's content is drawn on.
    ///
    /// ⛔ EVERY SHEET TAKES IT, through ``macSheetSize(width:height:)`` or, for the few that
    /// size themselves, directly at their root. Without it a Mac sheet shows the system's
    /// own sheet colour (#1E1E1E in dark), a different grey from the `#0E1C1F` page the
    /// sheet sits over (3.0.2 visual walk). `MacSheetFitTests` fails a sheet that has neither.
    func macSheetBackground() -> some View {
        modifier(MacSheetBackground())
    }
}

/// ⚠️ THE PALETTE IS READ FROM `colorScheme` (``DistrictColors/resolve(_:)``), so the sheet
/// follows light and dark like every other surface; never a fixed colour here.
/// `presentationBackground` is macOS 13.3 and later; the deployment target is 14.0.
private struct MacSheetBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.presentationBackground(DistrictColors.resolve(colorScheme).background)
    }
}
