import DistrictModel
import SwiftUI

/// The Contacts tab root.
///
/// ⛔ `.id(workspaceId)` IS LOAD-BEARING AND IS THE WHOLE REASON THIS WRAPPER
/// EXISTS. ``ContactsModel`` owns one ``OffsetPager`` built for one tenant, and
/// the pager's offsets and dedup set are meaningless across a switch. Seeding
/// `@State` in an initialiser only takes effect for a NEW view identity, so
/// without this the model would survive a workspace change and mix two
/// workspaces' rows.
///
/// ⛔ NO `NavigationStack` HERE. ``ShellView`` provides one per tab and registers
/// `navigationDestination(for: Route.self)` on it exactly once; SwiftUI resolves
/// that by TYPE, so a second registration inside a tab root is a runtime coin
/// toss.
struct ContactsView: View {
    let container: AppContainer
    let workspaceId: String

    /// ⚠️ CARRIED SO IT CAN TRAVEL ON THE ROUTE. ``Route/contactDetail`` holds the
    /// role because a destination restored from a `NavigationPath` after process
    /// death cannot go asking the session for one.
    let role: WorkspaceRole?

    /// The open row, on regular width only; nil on the phone. See ``RouteList``.
    var selection: Binding<Route?>?

    var body: some View {
        ContactsScreen(container: container, workspaceId: workspaceId, role: role, selection: selection)
            .id(workspaceId)
    }
}

/// The contact list for one workspace.
private struct ContactsScreen: View {
    let workspaceId: String
    let role: WorkspaceRole?
    let selection: Binding<Route?>?

    @State private var model: ContactsModel
    @State private var creating = false

    /// ⛔ THE CONTAINER'S ONE STORE. The badge on a row has to appear the moment a
    /// caller is blocked from an inbox thread in another tab; see the ⛔ on
    /// ``BlockedContactsStore``.
    private let blocked: BlockedContactsStore

    init(container: AppContainer, workspaceId: String, role: WorkspaceRole?, selection: Binding<Route?>?) {
        self.workspaceId = workspaceId
        self.role = role
        self.selection = selection
        blocked = container.blockedContacts
        _model = State(
            initialValue: ContactsModel(container: container, workspaceId: workspaceId, role: role)
        )
    }

    var body: some View {
        content
            .navigationTitle("Contacts")
            // ⛔ `.contain` FIRST, or this identifier is inherited by every row and
            // `A11yID.Contacts.row(id)` stops resolving. See SignInView's note.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.Contacts.root)
            .toolbar { addContactItem }
            .contactCommandTarget(canCreate: model.canMutate, creating: $creating)
            .sheet(isPresented: $creating) {
                CreateContactSheet(model: model)
                    .macSheetSize(width: 420, height: 360)
            }
            .task {
                // ⚠️ Once per appearance of this view identity, not per redraw.
                await model.feed.loadFirst()
            }
            // ⛔ ITS OWN `.task`, SO NEITHER READ CAN SKIP THE OTHER. The blocked
            // set is a separate route and a separate failure; the store's read is
            // silent by design (see ``BlockedContactsStore/refresh(workspaceId:)``)
            // because nobody asked for it.
            .task { await blocked.refresh(workspaceId: workspaceId) }
    }

    // MARK: - Toolbar

    /// ⚠️ OFFERED ONLY TO A ROLE THE SERVER WOULD ADMIT. `contacts/create`
    /// excludes `viewer`, so a viewer tapping this could only ever earn a 403
    /// they cannot act on.
    ///
    /// ⚠️ THE `if` IS INSIDE THE ITEM, NOT AROUND IT, AND THAT IS DELIBERATE. A
    /// conditional at `ToolbarContent` level leans on `ToolbarContentBuilder`
    /// supporting an `if` with no `else`, which is a question only the Mac
    /// compiler can settle; `ToolbarItem`'s content is a plain `@ViewBuilder`,
    /// where it certainly is supported. An empty item renders nothing.
    private var addContactItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.canMutate {
                Button("Add contact") { creating = true }
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch model.feed.state {
        case .loading:
            skeleton
        case let .content(rows, _, appending, appendFailure):
            list(rows: rows, appending: appending, appendFailure: appendFailure)
        case .empty:
            empty
        case let .failed(failure):
            FailureView(failure: failure, onRetry: reload)
        }
    }

    /// ⚠️ SKELETON ROWS, NOT A CENTRED SPINNER. The list that is arriving has a
    /// known shape, so drawing that shape says what is loading and stops the
    /// layout jumping when it lands.
    private var skeleton: some View {
        VStack(spacing: DistrictSpacing.row) {
            ForEach(0 ..< 6, id: \.self) { _ in
                SkeletonBlock(height: 56)
            }
            Spacer(minLength: 0)
        }
        .padding(DistrictSpacing.gutter)
    }

    /// ⚠️ REACHABLE ONLY AFTER A SUCCESSFUL FIRST PAGE, so it genuinely means "no
    /// contacts". The create action lives INSIDE the empty state rather than only
    /// in the toolbar, because an empty CRM is exactly where the first contact
    /// gets made and pointing at a control elsewhere is a dead end.
    @ViewBuilder
    private var empty: some View {
        if model.canMutate {
            EmptyStateView(
                systemImage: "person.2",
                title: "No contacts yet",
                message: "Callers are added automatically as they come in."
            ) {
                Button("Add a contact") { creating = true }
                    .buttonStyle(.districtPrimary)
            }
        } else {
            EmptyStateView(
                systemImage: "person.2",
                title: "No contacts yet",
                message: "Callers are added automatically as they come in."
            )
        }
    }

    /// ⚠️ A SORTABLE `Table` ON THE MAC (``ContactsTable``) WHERE THE iPad HAS A LIST; the
    /// read-only caption, the pager, the refresh and the empty state are the iPad's.
    private func list(
        rows: [Contact],
        appending: Bool,
        appendFailure: FailureText?
    ) -> some View {
        VStack(spacing: 0) {
            if !model.canMutate {
                readOnlyCaption
            }
            ContactsTable(
                workspaceId: workspaceId,
                role: role,
                contacts: rows,
                selection: selection,
                blocked: blocked,
                onReachEnd: loadMore
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PagedFeedFooter(appending: appending, appendFailure: appendFailure, onRetry: loadMore)
            }
        }
        .districtRefreshable {
            await model.feed.refresh()
            await blocked.refresh(workspaceId: workspaceId)
        }
    }

    private var readOnlyCaption: some View {
        Text("Read-only access, editing is disabled.")
            .font(DistrictType.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DistrictSpacing.gutter)
            .padding(.vertical, DistrictSpacing.tight)
    }

    // MARK: - Actions

    private func loadMore() {
        Task { await model.feed.loadMore() }
    }

    private func reload() {
        Task { await model.feed.loadFirst() }
    }
}
