import DistrictData
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// Cards the section screens draw only in states their first load does not reach: the
/// analytics usage and history cards, the SDR campaign card and an expanded workflow's run
/// history, and the dialer's country picker, each drawn from the service's recorded answers.
final class CardScreenTests: ScreenSnapshotCase {
    private static let size = MarketplaceTabScreenTests.size

    // MARK: - Analytics

    func testUsage() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                MarketplaceTabScreenTests.named("month", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let usage = try await app.container.analytics.usage(workspaceId: app.workspaceId).get()
                return MarketplaceTabScreenTests.tab { AnalyticsUsageCard(usage: usage) }
            }
        }
        // The recorded answer for a workspace with no usage yet (`usage: null`).
        let none: [FixtureTransport.Rule] = [
            .get("/api/district/workspace/usage", .fixture("mobile/district-usage-empty.json")),
        ]
        try await assertView("none", rules: none + ScreenRules.loaded, size: Self.size) { app in
            let usage = try await app.container.analytics.usage(workspaceId: app.workspaceId).get()
            return MarketplaceTabScreenTests.tab { AnalyticsUsageCard(usage: usage) }
        }
    }

    /// ⚠️ THE HISTORY IS ANSWERED BY ITS OWN RULE: it is the same path as this month's usage
    /// (`history=true` is a query item, which the fixture transport does not match on), so
    /// ``ScreenRules/loaded`` answers it with this month's shape.
    func testUsageHistory() async throws {
        let history: [FixtureTransport.Rule] = [
            .get("/api/district/workspace/usage", .fixture("mobile/district-usage-history.json")),
        ]
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                MarketplaceTabScreenTests.named("months", locale),
                rules: history + ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let months = try await app.container.analytics.usageHistory(workspaceId: app.workspaceId).get()
                return MarketplaceTabScreenTests.tab { AnalyticsHistoryCard(months: months) }
            }
        }
    }

    // MARK: - Workflows

    func testCampaign() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                MarketplaceTabScreenTests.named("loaded", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let model = WorkflowsModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
                await model.loadCampaign()
                guard case let .ready(status) = model.campaign else {
                    XCTFail("the recorded campaign status did not load")
                    return AnyView(EmptyView())
                }
                return MarketplaceTabScreenTests.tab { SdrCampaignCard(model: model, status: status) }
            }
        }
    }

    /// The first recorded workflow opened on its run history, as a press on its row opens it.
    func testRunHistory() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                MarketplaceTabScreenTests.named("loaded", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                try await Self.workflows(app)
            }
        }
        let none: [FixtureTransport.Rule] = [
            .get("/api/district/workflows/runs", .emptied("mobile/district-workflow-runs.json")),
        ]
        try await assertView("empty", rules: none + ScreenRules.loaded, size: Self.size) { app in
            try await Self.workflows(app)
        }
        let failing: [FixtureTransport.Rule] = [.get("/api/district/workflows/runs", .status(500))]
        try await assertView("failed", rules: failing + ScreenRules.loaded, size: Self.size) { app in
            try await Self.workflows(app)
        }
    }

    // MARK: - Dialer

    /// The picker the dialer's country button opens, at its own 320 by 420.
    func testCountryPicker() async throws {
        let size = CGSize(width: 320, height: 420)
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                MarketplaceTabScreenTests.named("canada", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: size
            ) { _ in
                AnyView(DialerCountryPicker(home: "CA", selected: "CA") { _ in })
            }
        }
        // No home country, and a country chosen that is not a suggestion.
        try await assertView("france", rules: ScreenRules.loaded, size: size) { _ in
            AnyView(DialerCountryPicker(home: nil, selected: "FR") { _ in })
        }
    }

    // MARK: - Drawing

    /// The recorded workflows as `WorkflowsView` lists them, the first opened on its runs.
    private static func workflows(_ app: SignedInApp) async throws -> AnyView {
        let model = WorkflowsModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        await model.loadWorkflows()
        guard case let .ready(workflows) = model.list, let first = workflows.first else {
            XCTFail("the recorded workflows did not load")
            return AnyView(EmptyView())
        }
        await model.toggleExpanded(first.id)
        return MarketplaceTabScreenTests.tab {
            ForEach(workflows, id: \.id) { workflow in
                VStack(alignment: .leading, spacing: 0) {
                    WorkflowRowView(model: model, workflow: workflow)
                    if model.expanded == workflow.id {
                        RunHistoryPanel(model: model, workflowId: workflow.id)
                    }
                    DistrictRowDivider()
                }
            }
        }
    }
}
