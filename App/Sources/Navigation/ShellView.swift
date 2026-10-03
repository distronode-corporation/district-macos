import DistrictModel
import SwiftUI

/// The signed-in shell: a sidebar of all sixteen sections and the selected one's detail.
///
/// Ported in shape from the iPad's `RegularShellView`. ⚠️ TWO COLUMNS FOR EVERY SECTION
/// IN THIS WAVE. The iPad gives its list sections (Inbox, Calls, Contacts, Desk, Support)
/// a third column; that arrives with those screens in Waves 5 and 7.
struct ShellView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar

    @State private var workspaceSession: WorkspaceSessionModel
    @State private var selection: SidebarItem? = .overview

    init(container: AppContainer, session: SessionModel, push: PushRegistrar) {
        self.container = container
        self.session = session
        self.push = push
        _workspaceSession = State(initialValue: WorkspaceSessionModel(container: container))
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail(selection ?? .overview)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(workspaceSession.selectedEntry?.name ?? "District AI")
        .focusedSceneValue(\.sidebarSelection, $selection)
        // ⚠️ RE-READ ON EVERY SIGN-IN (`epoch`), so a second account never sees the first
        // one's workspace list.
        .task(id: session.epoch) { await workspaceSession.load() }
    }

    @ViewBuilder
    private func detail(_ item: SidebarItem) -> some View {
        switch item {
        case .account:
            // Account is reachable with no workspace at all: it is where you sign out.
            AccountView(container: container, session: session, workspaceSession: workspaceSession, push: push)
        default:
            WorkspaceGate(workspaceSession: workspaceSession) { workspaceId in
                section(item, workspaceId: workspaceId)
            }
        }
    }

    @ViewBuilder
    private func section(_ item: SidebarItem, workspaceId: String) -> some View {
        switch item {
        case .overview:
            OverviewView(container: container, workspaceId: workspaceId)
                .id(workspaceId)
        case .scheduling:
            SchedulingHandoffView(container: container, workspaceId: workspaceId)
                .id(workspaceId)
        default:
            ComingLaterView(item: item)
        }
    }
}

/// Shows its content once a workspace is selected, and every other workspace state in
/// words. The states and their meanings are `WorkspaceSessionState`'s, from district-ios.
struct WorkspaceGate<Content: View>: View {
    let workspaceSession: WorkspaceSessionModel
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        switch workspaceSession.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(_, selected), let .partial(_, selected, _):
            content(selected.id)
        case let .degraded(message):
            notice(message, retry: true)
        case .empty:
            notice("This account is not a member of any workspace yet.", retry: false)
        case let .lapsed(count):
            notice(
                "\(count == 1 ? "Your workspace's" : "Your workspaces'") subscription is not active.",
                retry: false
            )
        case let .failed(failure):
            notice(failure.message, retry: failure.action == .retry)
        }
    }

    private func notice(_ message: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if retry {
                Button("Try again") {
                    Task { await workspaceSession.load() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The selected sidebar section, published to the menu bar so the Go menu can change it.
struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarItem?>
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarItem?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }
}
