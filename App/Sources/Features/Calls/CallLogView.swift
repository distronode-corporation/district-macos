import DistrictModel
import SwiftUI

/// The Calls tab root.
///
/// ⛔ `.id(workspaceId)` IS LOAD-BEARING AND IS THE WHOLE REASON THIS WRAPPER EXISTS.
/// ``CallLogModel`` owns one ``OffsetPager`` built for one tenant, and the pager's
/// offsets and dedup set are meaningless across a switch. Seeding `@State` in an
/// initialiser only takes effect for a NEW view identity, so without this the model
/// would survive a workspace change and mix two workspaces' rows. Changing the id
/// discards the identity and runs the initialiser again.
///
/// ⛔ NO `NavigationStack` HERE. ``ShellView`` provides one per tab and registers
/// `navigationDestination(for: Route.self)` on it exactly once; SwiftUI resolves that
/// by TYPE, so a second registration inside a tab root is a runtime coin toss.
struct CallLogView: View {
    let container: AppContainer
    let workspaceId: String

    /// The open row, on regular width only; nil on the phone. See ``RouteList``.
    var selection: Binding<Route?>?

    var body: some View {
        CallLogScreen(container: container, workspaceId: workspaceId, selection: selection)
            .id(workspaceId)
    }
}

/// The call log for one workspace.
private struct CallLogScreen: View {
    let workspaceId: String
    let selection: Binding<Route?>?

    @State private var model: CallLogModel

    init(container: AppContainer, workspaceId: String, selection: Binding<Route?>?) {
        self.workspaceId = workspaceId
        self.selection = selection
        _model = State(initialValue: CallLogModel(container: container, workspaceId: workspaceId))
    }

    var body: some View {
        content
            .navigationTitle("Call log")
            .task {
                // ⚠️ Once per appearance of this view identity, not per redraw.
                await model.loadFirst()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            skeleton
        case let .content(rows, _, appending, appendFailure):
            list(rows: rows, appending: appending, appendFailure: appendFailure)
        case .empty:
            // ⚠️ Reachable only after a SUCCESSFUL first page, which is what makes an
            // empty state honest here rather than a failure wearing the wrong copy.
            EmptyStateView(
                systemImage: "phone",
                title: "Nothing here yet",
                message: "Inbound and outbound calls will appear here as they happen."
            )
        case let .failed(failure):
            FailureView(failure: failure, onRetry: reload)
        }
    }

    // MARK: - States

    /// ⚠️ SKELETON ROWS, NOT A CENTRED SPINNER. The list that is arriving has a known
    /// shape, so drawing that shape says what is loading and stops the layout jumping
    /// when it lands. A spinner on a blank screen conveys only "wait".
    private var skeleton: some View {
        VStack(spacing: DistrictSpacing.row) {
            ForEach(0 ..< 6, id: \.self) { _ in
                SkeletonBlock(height: 56)
            }
            Spacer(minLength: 0)
        }
        .padding(DistrictSpacing.gutter)
    }

    /// ⚠️ A SORTABLE `Table` ON THE MAC (``CallLogTable``) WHERE THE iPad HAS A LIST OF
    /// ``CallRow``s; the states around it, the pager and the refresh are the iPad's.
    private func list(
        rows: [CallSummary],
        appending: Bool,
        appendFailure: FailureText?
    ) -> some View {
        CallLogTable(workspaceId: workspaceId, calls: rows, selection: selection, onReachEnd: loadMore)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PagedFeedFooter(appending: appending, appendFailure: appendFailure, onRetry: loadMore)
            }
            .districtRefreshable { await model.refresh() }
    }

    // MARK: - Actions

    private func loadMore() {
        Task { await model.loadMore() }
    }

    private func reload() {
        Task { await model.loadFirst() }
    }
}
