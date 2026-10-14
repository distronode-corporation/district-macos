import DistrictModel
import SwiftUI

/// Shows its content once a workspace is selected, and every other workspace state in
/// the iPad shell's words (district-ios `ShellView.gate`).
struct WorkspaceGate<Content: View>: View {
    let workspaceSession: WorkspaceSessionModel
    let onSignIn: () -> Void
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        switch workspaceSession.state {
        case .loading:
            LoadingView(message: NavigationCopy.loadingYourWorkspaces)
                .frame(maxHeight: .infinity)
        case let .content(_, selected), let .partial(_, selected, _):
            content(selected.id)
        case let .degraded(message):
            FailureView(failure: FailureText(message: message, action: .retry), onRetry: reload)
                .frame(maxHeight: .infinity)
        case .empty:
            EmptyStateView(
                systemImage: "building.2",
                title: NavigationCopy.noWorkspacesYet,
                message: NavigationCopy.accountDoesNotBelong
            )
            .frame(maxHeight: .infinity)
        case let .lapsed(inactiveCount):
            EmptyStateView(
                systemImage: "creditcard",
                title: NavigationCopy.subscriptionNotActive,
                message: inactiveCount == 1 ? NavigationCopy.lapsedOne : NavigationCopy.lapsedMany
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
