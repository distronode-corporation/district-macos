import DistrictData
import DistrictModel
import Observation
import SwiftUI

/// The workspace overview: the four headline figures and the most recent calls.
///
/// ⚠️ A FIRST CUT, wired to the real `GET` so a signed-in user sees their workspace's
/// data. The iPad's full Overview (Finish setup, the hub entries) is ported in Wave 5.
@MainActor
@Observable
final class OverviewModel {
    enum State {
        case loading
        case loaded(OverviewResponse)
        case failed(FailureText)
    }

    private(set) var state: State = .loading

    private let repository: OverviewRepository
    private let workspaceId: String

    init(container: AppContainer, workspaceId: String) {
        repository = container.overview
        self.workspaceId = workspaceId
    }

    func load() async {
        switch await repository.overview(workspaceId: workspaceId) {
        case let .success(response):
            state = .loaded(response)
        case let .failure(error):
            state = .failed(FailureText.from(error))
        }
    }
}

struct OverviewView: View {
    @State private var model: OverviewModel

    init(container: AppContainer, workspaceId: String) {
        _model = State(initialValue: OverviewModel(container: container, workspaceId: workspaceId))
    }

    var body: some View {
        content
            .navigationSubtitle("Overview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.load() }
                    }
                    .keyboardShortcut("r")
                }
            }
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(failure):
            Text(failure.message)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(response):
            loaded(response)
        }
    }

    private func loaded(_ response: OverviewResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    metric("Total calls", "\(response.metrics.totalCalls)")
                    metric("This week", "\(response.metrics.callsThisWeek)")
                    metric("Contacts", "\(response.metrics.totalContacts)")
                    metric("Average call", response.avgDurationLabel)
                }
                Text("Recent calls")
                    .font(.headline)
                if response.recentCalls.isEmpty {
                    Text("No calls yet.")
                        .foregroundStyle(.secondary)
                } else {
                    recentCalls(response.recentCalls)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func recentCalls(_ calls: [CallSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(calls, id: \.id) { call in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.number)
                            .font(.body.monospacedDigit())
                        Text(call.aiSummary.isEmpty ? call.status : call.aiSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(call.time)
                        Text(call.duration)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }
}
