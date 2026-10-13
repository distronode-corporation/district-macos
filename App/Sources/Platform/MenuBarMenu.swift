import AppKit
import SwiftUI

/// The menu bar item's menu: what stands for the app while its window is closed and it
/// keeps ringing. See ``BackgroundRinging``.
struct MenuBarMenu: View {
    /// The main window's scene id, for Open District AI.
    static let mainWindowId = "main"

    let background: BackgroundRinging

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // ⚠️ `openWindow(id:)` BRINGS THE MAIN WINDOW BACK if it was closed, and fronts it if
        // not; activating the app is what puts it in front of the app in use.
        Button(NavigationCopy.menuBarOpen) {
            openWindow(id: Self.mainWindowId)
            NSApplication.shared.activate()
        }
        Toggle(NavigationCopy.menuBarOpenAtLogin, isOn: Binding(
            get: { background.opensAtLogin },
            set: { background.setOpensAtLogin($0) }
        ))
        Divider()
        Button(NavigationCopy.menuBarQuit) {
            NSApplication.shared.terminate(nil)
        }
    }
}
