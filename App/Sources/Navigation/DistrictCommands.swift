import SwiftUI

/// The menu bar: a Go menu for the sidebar, and Sign Out.
///
/// ⚠️ THE GO MENU READS THE FOCUSED WINDOW'S SELECTION (`focusedSceneValue`), so with no
/// signed-in window in front its items are disabled rather than acting on nothing.
struct DistrictCommands: Commands {
    let session: SessionModel

    @FocusedBinding(\.sidebarSelection) private var selection

    var body: some Commands {
        #if DEVELOPER_ID
            // The Developer ID build's "Check for Updates...", beside About. The store
            // build has no updater: the App Store updates it.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
        #endif

        CommandMenu("Go") {
            ForEach(SidebarItem.allCases) { item in
                goButton(item)
            }
        }

        CommandGroup(after: .appSettings) {
            Button("Sign Out") {
                Task { await session.signOut() }
            }
            .disabled(session.phase != .signedIn || session.isBusy)
        }
    }

    @ViewBuilder
    private func goButton(_ item: SidebarItem) -> some View {
        let button = Button(item.title) { selection = item }
            .disabled(selection == nil)
        if let digit = item.shortcutDigit {
            button.keyboardShortcut(KeyEquivalent(digit), modifiers: .command)
        } else {
            button
        }
    }
}
