import Observation
import SwiftUI

/// How a keyboard command reaches a screen the shell cannot see into.
///
/// ⛔ THE SHELL HOLDS NO SCREEN'S MODEL, SO IT ASKS RATHER THAN CALLS. The Inbox's compose
/// sheet and search field belong to a view that is `@State` on its own root and rebuilt on
/// a workspace switch, exactly the reason ``ShellView/inboxPushSignal`` is a value the
/// screen observes. ⌘N and ⌘F therefore set a request here and select the Inbox; the Inbox
/// consumes the request when it sees it, whether it was already on screen or is being built
/// by the same selection (``View/commandTargets(canCompose:composing:)``).
///
/// ⛔ ⌘R RUNS THE REFRESH OF THE SCREEN ON SCREEN, AND "ON SCREEN" IS APPEARANCE, NOT
/// EXISTENCE. A tab the bar is not showing and a list under a pushed screen both still
/// exist; a refresh chosen by existence would re-read a list nobody is looking at. Every
/// pull-to-refresh registers here while it is visible
/// (``View/districtRefreshable(_:)``), and the most recently appeared one is the one run.
/// A list and the detail beside it do not compete: no detail screen has a pull-to-refresh.
///
/// ⚠️ A MAC HAS NO PULL GESTURE, so `.refreshable` alone would be unreachable there. The
/// registered action is what ⌘R, View > Refresh and the shell's toolbar Refresh button
/// run (``ShellView``), which keeps "the screen on screen" the one thing that decides.
@MainActor
@Observable
final class ShellCommandCenter {
    /// ⚠️ MAIN-ACTOR ISOLATED, AS `.refreshable`'S OWN ACTION IS (it inherits the view's
    /// actor), so a screen can hand over the same closure it gave the pull.
    typealias Refresh = @MainActor @Sendable () async -> Void

    /// ⌘N was pressed and the Inbox has not opened its compose sheet yet.
    var composeRequested = false

    /// ⌘F was pressed and the Inbox has not focused its search field yet.
    var searchRequested = false

    /// ⇧⌘N was pressed and Contacts has not opened its Add contact sheet yet.
    ///
    /// ⚠️ MAC ONLY. The iPad's keyboard commands stop at New Message; on the Mac every
    /// create action a section has gets a File menu item, and Contacts is the other one.
    var createContactRequested = false

    private var refreshers: [(id: UUID, action: Refresh)] = []

    /// A create action a screen on display offers, for ⌘N (``View/districtCreateCommand(_:action:)``).
    struct Create {
        /// The screen's own button title ("Create event type"), which the menu item takes.
        let title: String
        let action: @MainActor () -> Void
    }

    /// ⚠️ MAC ONLY, AND BY APPEARANCE, AS ⌘R IS: the create button that appeared last is
    /// the one ⌘N runs. With none on screen, ⌘N is New Message.
    private var creators: [(id: UUID, create: Create)] = []

    var screenCreate: Create? {
        creators.last?.create
    }

    func registerCreate(_ id: UUID, _ create: Create) {
        creators.removeAll { $0.id == id }
        creators.append((id, create))
    }

    func unregisterCreate(_ id: UUID) {
        creators.removeAll { $0.id == id }
    }

    /// ⚠️ ONE AT A TIME. A second ⌘R during a slow read would start a second read of the
    /// same list, and the models do not all guard against that themselves.
    private(set) var isRefreshing = false

    var canRefresh: Bool {
        !refreshers.isEmpty && !isRefreshing
    }

    func register(_ id: UUID, action: @escaping Refresh) {
        refreshers.removeAll { $0.id == id }
        refreshers.append((id, action))
    }

    func unregister(_ id: UUID) {
        refreshers.removeAll { $0.id == id }
    }

    /// Run the refresh of the screen that appeared last, if any is on screen.
    func refresh() async {
        guard !isRefreshing, let current = refreshers.last else { return }
        isRefreshing = true
        await current.action()
        isRefreshing = false
    }
}

extension View {
    /// `.refreshable`, and the same action on ⌘R while this view is on screen.
    ///
    /// ⛔ THE ONE ACTION FOR BOTH, SO THE KEYBOARD CAN NEVER REFRESH DIFFERENTLY FROM THE
    /// PULL. Outside the shell (a preview, a test host) there is no center and this is
    /// exactly `.refreshable`.
    func districtRefreshable(_ action: @escaping ShellCommandCenter.Refresh) -> some View {
        modifier(CommandRefreshable(action: action))
    }

    /// This create button's action on ⌘N while it is on screen.
    ///
    /// ⚠️ MAC ONLY. The iPad's keyboard commands stop at New Message; on the Mac a section
    /// whose screen offers a create (Scheduling's event types, teams, keys and webhooks)
    /// takes ⌘N while that button is on screen, and File > New Message keeps its place
    /// without the shortcut. The button already carries the role gate (it is absent for a
    /// role that may not create), so registering only while it is drawn is the gate.
    func districtCreateCommand(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        modifier(CreateCommand(create: ShellCommandCenter.Create(title: title, action: action)))
    }

    /// Where ⇧⌘N lands: open Contacts' Add contact sheet. ⚠️ Consumed either way, like
    /// ⌘N, so a request this role cannot honour does not wait for one where it can.
    func contactCommandTarget(canCreate: Bool, creating: Binding<Bool>) -> some View {
        modifier(ContactCommandTarget(canCreate: canCreate, creating: creating))
    }

    /// Where ⌘N and ⌘F land: open the compose sheet, focus the search field.
    ///
    /// ⚠️ APPLIED AFTER `.searchable`, because the search focus it binds belongs to that
    /// field.
    func commandTargets(canCompose: Bool, composing: Binding<Bool>) -> some View {
        modifier(CommandTargets(canCompose: canCompose, composing: composing))
    }
}

private struct CommandRefreshable: ViewModifier {
    let action: ShellCommandCenter.Refresh

    @Environment(ShellCommandCenter.self) private var center: ShellCommandCenter?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .refreshable { await action() }
            .onAppear { center?.register(id, action: action) }
            .onDisappear { center?.unregister(id) }
    }
}

private struct CreateCommand: ViewModifier {
    let create: ShellCommandCenter.Create

    @Environment(ShellCommandCenter.self) private var center: ShellCommandCenter?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { center?.registerCreate(id, create) }
            .onDisappear { center?.unregisterCreate(id) }
    }
}

private struct CommandTargets: ViewModifier {
    let canCompose: Bool
    @Binding var composing: Bool

    @Environment(ShellCommandCenter.self) private var center: ShellCommandCenter?
    @FocusState private var searchFocused: Bool

    func body(content: Content) -> some View {
        focusable(content)
            // ⛔ `initial: true`, BECAUSE THE REQUEST CAN ARRIVE BEFORE THIS VIEW DOES. On
            // regular width ⌘N selects the Inbox and sets the request in one update, and the
            // Inbox is built by that same selection, so the request is already set on its
            // first evaluation and would never be a change.
            .onChange(of: center?.composeRequested == true, initial: true) { _, requested in
                guard requested else { return }
                center?.composeRequested = false
                // ⚠️ CONSUMED EITHER WAY, so a request this role cannot honour does not sit
                // waiting for a workspace where it can.
                if canCompose {
                    composing = true
                }
            }
            .onChange(of: center?.searchRequested == true, initial: true) { _, requested in
                guard requested else { return }
                center?.searchRequested = false
                searchFocused = true
            }
    }

    /// ⚠️ macOS 15 OR LATER ONLY: `searchFocused` does not exist on 14, where the command
    /// brings the field on screen and stops. See ``DistrictCommands``.
    @ViewBuilder
    private func focusable(_ content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused($searchFocused)
        } else {
            content
        }
    }
}

private struct ContactCommandTarget: ViewModifier {
    let canCreate: Bool
    @Binding var creating: Bool

    @Environment(ShellCommandCenter.self) private var center: ShellCommandCenter?

    func body(content: Content) -> some View {
        // ⛔ `initial: true`, FOR THE REASON ``CommandTargets`` GIVES: the selection that
        // builds Contacts and the request arrive in one update.
        content.onChange(of: center?.createContactRequested == true, initial: true) { _, requested in
            guard requested else { return }
            center?.createContactRequested = false
            if canCreate {
                creating = true
            }
        }
    }
}
