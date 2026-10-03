import DistrictModel
import SwiftUI

/// The signed-in shell: a sidebar of every section the role is offered, and the selected
/// one beside it.
///
/// Ported in shape from the iPad's `RegularShellView` (see PORTING.md).
///
/// ⛔ TWO SPLIT VIEWS, ONE PER COLUMN COUNT, SHARING ONE SIDEBAR AND ONE STATE, as on the
/// iPad. A list section (Inbox, Calls, Contacts, Desk, Support) is three columns: the
/// sidebar, its list, and the open row beside it. Everything else is a screen of its own
/// and gets the whole detail column. A `NavigationSplitView`'s column count is fixed when
/// it is built, and hiding the middle column has no public API.
///
/// ⛔ `navigationDestination(for: Route.self)` IS REGISTERED ONCE PER STACK, ON THE DETAIL
/// COLUMN'S STACK, AND NEVER IN THE SIDEBAR OR THE CONTENT COLUMN. See
/// ``RouteDestinations``.
///
/// ⚠️ THE SIDEBAR IS GATED BY THE WORKSPACE LIST'S ROLE (`RouteGate`), the only role the
/// shell has. A selection the sidebar does not offer is drawn as the Overview rather than
/// written over.
///
/// ⚠️ ACCOUNT IS DRAWN WITH NO WORKSPACE AT ALL, which the iPad's shell does not do (it
/// gates every tab on the workspace list): on a Mac the sidebar is always on screen, and
/// Account is where you sign out.
struct ShellView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar
    let live: DesktopLive

    @State private var workspaceSession: WorkspaceSessionModel
    @State private var paths = ShellPaths()
    @State private var commands = ShellCommandCenter()
    /// ⚠️ RESET WHENEVER THE COLUMN COUNT CHANGES, as on the iPad: the two split views read
    /// the same case differently.
    @State private var columns: NavigationSplitViewVisibility = .automatic

    init(container: AppContainer, session: SessionModel, push: PushRegistrar, live: DesktopLive) {
        self.container = container
        self.session = session
        self.push = push
        self.live = live
        _workspaceSession = State(initialValue: WorkspaceSessionModel(container: container))
    }

    private var workspaceId: String? {
        workspaceSession.workspaceId
    }

    private var role: WorkspaceRole? {
        workspaceSession.role
    }

    /// The rows the sidebar offers: the iPad's gated list once a workspace resolves, and
    /// every section, ungated, until then (each draws the workspace state in words).
    private var entries: [SidebarEntry] {
        guard let workspaceId else {
            return SidebarItem.allCases.map { SidebarEntry(item: $0, gate: .none) }
        }
        return SidebarItem.entries(workspaceId: workspaceId, role: role)
    }

    /// The section on screen: the stored selection when the sidebar offers it, and the
    /// Overview when it does not.
    private var shown: SidebarItem {
        let selected = paths.selection
        return entries.contains { $0.item == selected } ? selected : .overview
    }

    var body: some View {
        let item = shown
        let rows = entries
        Group {
            if item.isListSection, let workspaceId {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar(rows, showing: item)
                } content: {
                    listColumn(item, workspaceId: workspaceId)
                } detail: {
                    listDetail(item)
                }
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar(rows, showing: item)
                } detail: {
                    sectionDetail(item)
                }
            }
        }
        .onChange(of: item.isListSection) { columns = .automatic }
        .toolbar {
            // ⚠️ THE MAC'S STAND-IN FOR PULL-TO-REFRESH: the same registered action as ⌘R
            // (``ShellCommandCenter``), disabled while no screen on display has one.
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await commands.refresh() }
                }
                .disabled(!commands.canRefresh)
                .help("Refresh (⌘R)")
            }
        }
        .navigationSubtitle(workspaceSession.selectedEntry?.name ?? "")
        .shellCommands(commands, paths: $paths, workspaceId: workspaceId, role: role)
        // ⚠️ RE-READ ON EVERY SIGN-IN (`epoch`), so a second account never sees the first
        // one's workspace list.
        .task(id: session.epoch) { await workspaceSession.load() }
        .onChange(of: workspaceSession.workspaceId, initial: true) {
            paths.adopt(workspaceSession.workspaceId)
        }
        // ⛔ THIS MAC RINGS FOR THE SELECTED WORKSPACE, and moves with it. See ``DesktopLive``.
        .onChange(of: workspaceSession.workspaceId, initial: true) {
            live.signedIn(
                workspaceId: workspaceSession.workspaceId,
                workspaceName: workspaceSession.selectedEntry?.name
            )
        }
    }

    // ── The sidebar ──────────────────────────────────────────────────────────

    private func sidebar(_ rows: [SidebarEntry], showing item: SidebarItem) -> some View {
        List(selection: sidebarSelection(showing: item)) {
            ForEach(rows) { entry in
                SidebarRow(entry: entry)
                    .tag(entry.item)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    /// ⚠️ A nil WRITE IS IGNORED: nothing a person does deselects a sidebar row.
    private func sidebarSelection(showing item: SidebarItem) -> Binding<SidebarItem?> {
        Binding(
            get: { item },
            set: { next in
                guard let next else { return }
                if next.isListSection != shown.isListSection {
                    columns = .automatic
                }
                paths.select(next)
            }
        )
    }

    // ── List sections: the list, and the open row beside it ──────────────────

    /// The content column of a list section.
    ///
    /// ⛔ THE INBOX TAKES THE WHOLE PATH, AS ON THE iPad: its compose sheet selects the
    /// thread its send created by writing through `selection`, and it re-reads when a row
    /// it had open is left; both read the path, not the tail.
    ///
    /// ⚠️ WIDER FOR A TABLE. Calls and Contacts are sortable tables (a Mac idiom the iPad
    /// does not have), which need room for their columns; the Inbox keeps the iPad's rows.
    private func listColumn(_ item: SidebarItem, workspaceId: String) -> some View {
        let selection = listSelection(item)
        return Group {
            switch item {
            case .inbox:
                InboxView(
                    container: container,
                    workspaceId: workspaceId,
                    role: role,
                    path: path(for: .inbox),
                    // ⚠️ CONSTANT: a tapped message push does not reach the Inbox yet
                    // (iOS `PushRouting` is not ported; see PORTING.md).
                    pushSignal: 0,
                    selection: selection
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 400)
            case .calls:
                CallLogView(container: container, workspaceId: workspaceId, selection: selection)
                    .navigationSplitViewColumnWidth(min: 460, ideal: 640)
            case .contacts:
                ContactsView(container: container, workspaceId: workspaceId, role: role, selection: selection)
                    .navigationSplitViewColumnWidth(min: 460, ideal: 640)
            default:
                // Desk and Support, the two list sections that are hubs, arrive in Wave 7.
                ComingLaterView(item: item)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            }
        }
        .districtBackground()
    }

    /// The detail column: the open row as the root of its own stack, or the placeholder.
    ///
    /// ⛔ `.id(first)` GIVES EACH SELECTED ROW A FRESH STACK: the root screens seed their
    /// models once per view identity.
    @ViewBuilder
    private func listDetail(_ item: SidebarItem) -> some View {
        if let first = ListDetailPath.selection(in: paths.path(for: item)) {
            NavigationStack(path: tail(for: item)) {
                destination(first)
                    .navigationDestination(for: Route.self) { destination($0) }
            }
            .id(first)
        } else if let placeholder = item.detailPlaceholder {
            DetailPlaceholder(title: placeholder.title, symbol: placeholder.symbol)
                .districtBackground()
        }
    }

    private func listSelection(_ item: SidebarItem) -> Binding<Route?> {
        Binding(
            get: { ListDetailPath.selection(in: paths.path(for: item)) },
            set: { route in
                let next = ListDetailPath.selecting(route, in: paths.path(for: item))
                paths.setPath(next, for: item)
            }
        )
    }

    /// ⚠️ THE SETTER RE-READS THE PATH RATHER THAN CAPTURING IT, so a write from a stack
    /// that is being torn down lands on whatever the section holds now.
    private func tail(for item: SidebarItem) -> Binding<[Route]> {
        Binding(
            get: { ListDetailPath.tail(of: paths.path(for: item)) },
            set: { tail in
                let next = ListDetailPath.replacingTail(tail, in: paths.path(for: item))
                paths.setPath(next, for: item)
            }
        )
    }

    // ── Every other section: the whole detail column ─────────────────────────

    /// ⛔ `.id(item)`, SO EACH SECTION IS ITS OWN STACK.
    private func sectionDetail(_ item: SidebarItem) -> some View {
        NavigationStack(path: path(for: item)) {
            sectionRoot(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .districtBackground()
                .navigationDestination(for: Route.self) { destination($0) }
        }
        .id(item)
    }

    @ViewBuilder
    private func sectionRoot(_ item: SidebarItem) -> some View {
        if item == .account {
            AccountView(container: container, session: session, push: push, live: live)
        } else {
            WorkspaceGate(workspaceSession: workspaceSession, onSignIn: signIn) { workspaceId in
                workspaceSection(item, workspaceId: workspaceId)
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(_ item: SidebarItem, workspaceId: String) -> some View {
        switch item {
        case .overview:
            OverviewView(
                container: container,
                session: session,
                workspaceSession: workspaceSession,
                onSignIn: signIn,
                onSelectTab: { paths.select(SidebarItem(tab: $0)) }
            )
            .hidingEntryPoints()
        case .scheduling:
            SchedulingHandoffView(container: container, workspaceId: workspaceId)
                .id(workspaceId)
        default:
            if let root = item.rootRoute(workspaceId: workspaceId, role: role) {
                RouteDestinations.view(
                    for: root,
                    container: container,
                    session: workspaceSession,
                    accountSession: session
                )
                .id(root)
            } else {
                ComingLaterView(item: item)
            }
        }
    }

    // ── Shared ───────────────────────────────────────────────────────────────

    private func destination(_ route: Route) -> some View {
        RouteDestinations.view(
            for: route,
            container: container,
            session: workspaceSession,
            accountSession: session
        )
        .districtBackground()
    }

    private func path(for item: SidebarItem) -> Binding<[Route]> {
        Binding(
            get: { paths.path(for: item) },
            set: { paths.setPath($0, for: item) }
        )
    }

    private func signIn() {
        Task { await session.signIn() }
    }
}

/// One sidebar row.
///
/// ⚠️ THE `.partial` CAPTION IS A BADGE, which is where a sidebar puts a row's secondary
/// text; it says what the Overview's caption says, in the same word.
///
/// ⛔ THE ICON CARRIES AN EXPLICIT COLOUR, THE BRAND ACCENT FOR THE SCHEME. Left to the
/// sidebar, a symbol is drawn with the list's vibrant tertiary style, which against the
/// dark palette's near-black teal read as almost invisible (the Wave 5 screenshots). A
/// fixed colour opts the image out of that blending. The brand accent is the iPad
/// sidebar's icon colour (it inherits the root `districtTheme()` tint there).
private struct SidebarRow: View {
    let entry: SidebarEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(entry.item.title)
        } icon: {
            Image(systemName: entry.item.symbol)
                .foregroundStyle(DistrictColors.resolve(colorScheme).district)
        }
        .badge(caption.map { Text($0) })
        .accessibilityIdentifier(entry.item.accessibilityID)
    }

    private var caption: String? {
        switch entry.gate {
        case .partial: "Read-only"
        case .hidden, .none: nil
        }
    }
}

/// Shows its content once a workspace is selected, and every other workspace state in
/// the iPad shell's words (district-ios `ShellView.gate`).
struct WorkspaceGate<Content: View>: View {
    let workspaceSession: WorkspaceSessionModel
    let onSignIn: () -> Void
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        switch workspaceSession.state {
        case .loading:
            LoadingView(message: "Loading your workspaces…")
                .frame(maxHeight: .infinity)
        case let .content(_, selected), let .partial(_, selected, _):
            content(selected.id)
        case let .degraded(message):
            FailureView(failure: FailureText(message: message, action: .retry), onRetry: reload)
                .frame(maxHeight: .infinity)
        case .empty:
            EmptyStateView(
                systemImage: "building.2",
                title: "No workspaces yet",
                message: "This account does not belong to a workspace. Ask whoever invited you to add you to one."
            )
            .frame(maxHeight: .infinity)
        case let .lapsed(inactiveCount):
            let noun = inactiveCount == 1 ? "workspace is" : "workspaces are"
            EmptyStateView(
                systemImage: "creditcard",
                title: "Subscription not active",
                message: "Your \(noun) paused because the subscription is not active."
            )
            .frame(maxHeight: .infinity)
        case let .failed(failure):
            FailureView(failure: failure, onRetry: reload, onSignIn: onSignIn)
                .frame(maxHeight: .infinity)
        }
    }

    private func reload() {
        Task { await workspaceSession.load() }
    }
}

private extension OverviewView {
    /// ⚠️ A COPY WITH ITS ENTRY COLUMN OFF, because every row in it is a sidebar row here.
    func hidingEntryPoints() -> OverviewView {
        var copy = self
        copy.showsEntryPoints = false
        return copy
    }
}
