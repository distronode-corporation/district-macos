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

extension View {
    /// The size a sheet opens at on the Mac.
    ///
    /// ⚠️ A MAC SHEET HAS NO SIZE OF ITS OWN: it takes its content's ideal size, which for
    /// a form of flexible fields is either a sliver or the whole window. Each ported sheet
    /// states one at its presentation site; the iPad's sheets need none.
    func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
    }
}
