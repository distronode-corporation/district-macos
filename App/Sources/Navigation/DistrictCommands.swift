import DistrictModel
import SwiftUI

/// Which menu commands can run, decided from the shell's state alone.
///
/// Ported from district-ios `Navigation/ShellCommands.swift` (see PORTING.md), where the
/// same commands serve an iPad's hardware keyboard.
///
/// ⛔ A COMMAND THAT CANNOT RUN IS DISABLED, NEVER REMOVED. A menu whose entries come and
/// go with the screen teaches nothing, while a greyed entry says what it would do and that
/// it cannot do it here.
///
/// ⛔ ``unavailable`` IS WHAT A SIGNED-OUT APP GETS, and it gets it structurally rather than
/// by a check. The shell is the only publisher of ``ShellCommandActions``, and ``RootView``
/// draws the shell only for a signed-in session, so with nobody signed in there is no value
/// to read and every command falls back to this.
struct ShellCommandAvailability: Equatable {
    /// ⚠️ EVERY COMMAND NEEDS A WORKSPACE, because every section but Account reads one.
    let workspaceResolved: Bool
    let canSend: Bool
    let refreshAvailable: Bool
    /// The sections the sidebar offers this role (``SidebarItem/entries(workspaceId:role:)``).
    let offered: Set<SidebarItem>

    init(workspaceId: String?, role: WorkspaceRole?, refreshAvailable: Bool) {
        workspaceResolved = workspaceId != nil
        // ⛔ THE SAME GATE THE INBOX'S OWN "New" BUTTON AND THE SEND ITSELF USE, so the
        // shortcut can never offer a viewer the sheet the toolbar hides from them.
        canSend = WorkspaceRole.allowsMutation(role)
        self.refreshAvailable = refreshAvailable
        offered = workspaceId.map { Set(SidebarItem.visible(workspaceId: $0, role: role)) } ?? []
    }

    static let unavailable = ShellCommandAvailability(workspaceId: nil, role: nil, refreshAvailable: false)

    /// ⚠️ ACCOUNT IS ALWAYS SELECTABLE: it is where you sign out, and on the Mac it is drawn
    /// with no workspace at all (``ShellView``).
    func canSelect(_ item: SidebarItem) -> Bool {
        item == .account || (workspaceResolved && offered.contains(item))
    }

    var canCompose: Bool {
        workspaceResolved && canSend && offered.contains(.inbox)
    }

    /// ⛔ THE SAME GATE AS CONTACTS' OWN "Add contact" (``ContactsModel/canMutate``).
    var canCreateContact: Bool {
        workspaceResolved && canSend && offered.contains(.contacts)
    }

    var canSearch: Bool {
        workspaceResolved && offered.contains(.inbox)
    }

    /// ⚠️ ONLY WHILE A SCREEN WITH A REFRESH IS ON SCREEN. See ``ShellCommandCenter``.
    var canRefresh: Bool {
        workspaceResolved && refreshAvailable
    }
}

/// What the signed-in shell lets the menu bar do, published for ``DistrictCommands``.
///
/// ⛔ ONE PUBLISHER, THE SHELL, SO THERE IS NEVER A QUESTION OF WHICH VALUE WINS. The
/// screens reach the menu bar through ``ShellCommandCenter`` instead, which the shell owns.
struct ShellCommandActions {
    let availability: ShellCommandAvailability
    let select: (SidebarItem) -> Void
    let newMessage: () -> Void
    let newContact: () -> Void
    let search: () -> Void
    let refresh: () -> Void
}

private struct ShellCommandActionsKey: FocusedValueKey {
    typealias Value = ShellCommandActions
}

extension FocusedValues {
    var shellCommands: ShellCommandActions? {
        get { self[ShellCommandActionsKey.self] }
        set { self[ShellCommandActionsKey.self] = newValue }
    }
}

/// The menu bar: File > New Message and New Contact, Edit > Search Messages, View >
/// Refresh, a Go menu for the sidebar, and Sign Out.
///
/// ⚠️ THE COMMANDS READ THE FOCUSED WINDOW'S SHELL (`focusedSceneValue`), so with no
/// signed-in window in front every item is disabled rather than acting on nothing.
struct DistrictCommands: Commands {
    let session: SessionModel

    @FocusedValue(\.shellCommands) private var shell

    private var availability: ShellCommandAvailability {
        shell?.availability ?? .unavailable
    }

    var body: some Commands {
        #if DEVELOPER_ID
            // The Developer ID build's "Check for Updates...", beside About. The store
            // build has no updater: the App Store updates it.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
        #endif

        CommandGroup(replacing: .newItem) {
            Button("New Message") { shell?.newMessage() }
                .keyboardShortcut("n")
                .disabled(!availability.canCompose)
            Button("New Contact") { shell?.newContact() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!availability.canCreateContact)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Messages") { shell?.search() }
                .keyboardShortcut("f")
                .disabled(!availability.canSearch)
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh") { shell?.refresh() }
                .keyboardShortcut("r")
                .disabled(!availability.canRefresh)
        }

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
        let button = Button(item.title) { shell?.select(item) }
            .disabled(!availability.canSelect(item))
        if let digit = item.shortcutDigit {
            button.keyboardShortcut(KeyEquivalent(digit), modifiers: .command)
        } else {
            button
        }
    }
}

extension View {
    /// Publish the shell's menu commands and hand the screens below the center they answer
    /// through.
    func shellCommands(
        _ center: ShellCommandCenter,
        paths: Binding<ShellPaths>,
        workspaceId: String?,
        role: WorkspaceRole?
    ) -> some View {
        let availability = ShellCommandAvailability(
            workspaceId: workspaceId,
            role: role,
            refreshAvailable: center.canRefresh
        )
        let select: (SidebarItem) -> Void = { item in
            guard availability.canSelect(item) else { return }
            paths.wrappedValue.select(item)
        }
        let actions = ShellCommandActions(
            availability: availability,
            select: select,
            newMessage: {
                guard availability.canCompose else { return }
                select(.inbox)
                center.composeRequested = true
            },
            newContact: {
                guard availability.canCreateContact else { return }
                select(.contacts)
                center.createContactRequested = true
            },
            search: {
                guard availability.canSearch else { return }
                select(.inbox)
                center.searchRequested = true
            },
            refresh: {
                guard availability.canRefresh else { return }
                Task { await center.refresh() }
            }
        )
        return environment(center)
            .focusedSceneValue(\.shellCommands, actions)
    }
}
