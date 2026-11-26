@testable import DistrictMac
import DistrictModel
import XCTest

/// The automation monitor's model driven through the states a user's actions reach, answered
/// by the service's recorded responses (`contracts/`).
///
/// ⚠️ UNIT TESTS, NOT IMAGES: ``WorkflowsView`` builds its model in its own `@State`, so a
/// screen snapshot can only show the state its `.task` reads settle into (the sections suite
/// draws that). The states after an expand, a toggle or a campaign change are pinned here on
/// the model the view draws from.
@MainActor
final class WorkflowsModelStateTests: XCTestCase {
    private static let api = "/api/district"
    private static let active = "wf_contract_active"
    private static let paused = "wf_contract_paused"

    /// The two writes, answered after the reads: a GET on the same path matches the
    /// `.get` rule in `ScreenRules.loaded` first, so only the PATCH reaches these.
    private static let writes: [FixtureTransport.Rule] = [
        .any("\(api)/workspace/campaign-status", .fixture("mobile/district-campaign-pause.json")),
        .any("\(api)/workflows", .fixture("mobile/district-workflow-toggle.json")),
    ]

    private static let loaded = ScreenRules.loaded + writes

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (WorkflowsModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "workflows.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = WorkflowsModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.loadCampaign()
        await model.loadWorkflows()
        return (model, transport)
    }

    private func workflows(_ model: WorkflowsModel) -> [WorkflowListItem] {
        guard case let .ready(items) = model.list else { return [] }
        return items
    }

    private func runReads(_ transport: FixtureTransport) -> Int {
        transport.sentRequests.filter { $0.hasPrefix("GET \(Self.api)/workflows/runs") }.count
    }

    // MARK: - Reading

    func testBothReadsSettleIntoTheirRecordedAnswers() async {
        let (model, _) = await model(Self.loaded)
        XCTAssertEqual(workflows(model).map(\.id), [Self.active, Self.paused])
        guard case let .ready(status) = model.campaign else {
            return XCTFail("campaign not ready: \(model.campaign)")
        }
        XCTAssertTrue(status.infiniteSdrEnabled)
        XCTAssertTrue(model.canToggle)
    }

    /// ⛔ FOUR INDEPENDENT FAILURES: a campaign read that 500'd leaves the list that answered.
    func testACampaignFailureDoesNotBlankTheList() async {
        let rules: [FixtureTransport.Rule] = [.get("\(Self.api)/workspace/campaign-status", .status(500))] + Self.loaded
        let (model, _) = await model(rules)
        guard case .failed = model.campaign else {
            return XCTFail("campaign should have failed: \(model.campaign)")
        }
        XCTAssertEqual(workflows(model).count, 2)
    }

    func testAListFailureIsItsOwnState() async {
        let rules: [FixtureTransport.Rule] = [.get("\(Self.api)/workflows", .status(500))] + Self.loaded
        let (model, _) = await model(rules)
        guard case .failed = model.list else {
            return XCTFail("list should have failed: \(model.list)")
        }
        guard case .ready = model.campaign else {
            return XCTFail("campaign should have answered: \(model.campaign)")
        }
    }

    // MARK: - Run history

    func testExpandReadsTheFirstPageAndLoadMoreAppendsTheNext() async {
        let (model, transport) = await model(Self.loaded)
        await model.toggleExpanded(Self.active)
        XCTAssertEqual(model.expanded, Self.active)
        let first = model.runs[Self.active]
        XCTAssertEqual(first?.runs.count, 4)
        XCTAssertEqual(first?.total, 9)
        XCTAssertEqual(first?.hasMore, true)
        XCTAssertEqual(first?.loaded, true)
        XCTAssertEqual(first?.loading, false)
        XCTAssertNil(first?.failure)

        await model.loadMoreRuns(Self.active)
        XCTAssertEqual(model.runs[Self.active]?.runs.count, 8)
        XCTAssertEqual(runReads(transport), 2)
    }

    /// ⛔ THE HISTORY IS CACHED ONCE IT ANSWERED: collapsing and re-expanding costs nothing.
    func testCollapseAndReExpandDoesNotReadAgain() async {
        let (model, transport) = await model(Self.loaded)
        await model.toggleExpanded(Self.active)
        await model.toggleExpanded(Self.active)
        XCTAssertNil(model.expanded)
        await model.toggleExpanded(Self.active)
        XCTAssertEqual(model.expanded, Self.active)
        XCTAssertEqual(runReads(transport), 1)
    }

    /// ⛔ A FAILED FIRST PAGE IS NOT A CACHE HIT, and the retry re-reads it.
    func testAFailedFirstPageIsRetriedNotCached() async {
        let rules: [FixtureTransport.Rule] = [.get("\(Self.api)/workflows/runs", .status(500))] + Self.loaded
        let (model, transport) = await model(rules)
        await model.toggleExpanded(Self.active)
        let history = model.runs[Self.active]
        XCTAssertNotNil(history?.failure)
        XCTAssertEqual(history?.loaded, false)
        XCTAssertEqual(history?.hasMore, false)
        XCTAssertEqual(history?.needsFirstPage, true)

        // No `hasMore`, so "load more" is refused; the retry is the way out.
        await model.loadMoreRuns(Self.active)
        XCTAssertEqual(runReads(transport), 1)
        await model.retryRuns(Self.active)
        XCTAssertEqual(runReads(transport), 2)

        // Collapsing and re-expanding asks again, because nothing answered.
        await model.toggleExpanded(Self.active)
        await model.toggleExpanded(Self.active)
        XCTAssertEqual(runReads(transport), 3)
    }

    func testRetryAndLoadMoreAreRefusedWithoutAHistoryOrAFailure() async {
        let (model, transport) = await model(Self.loaded)
        await model.loadMoreRuns(Self.paused)
        await model.retryRuns(Self.paused)
        XCTAssertEqual(runReads(transport), 0)

        await model.toggleExpanded(Self.active)
        await model.retryRuns(Self.active)
        XCTAssertEqual(runReads(transport), 1)
    }

    /// ⚠️ ONE HISTORY OPEN AT A TIME: expanding another closes the first.
    func testExpandingAnotherWorkflowMovesTheOpenRow() async {
        let (model, _) = await model(Self.loaded)
        await model.toggleExpanded(Self.active)
        await model.toggleExpanded(Self.paused)
        XCTAssertEqual(model.expanded, Self.paused)
        XCTAssertNotNil(model.runs[Self.active])
    }

    // MARK: - The per-workflow switch

    func testASuccessfulToggleKeepsItsOverride() async throws {
        let (model, transport) = await model(Self.loaded)
        let row = try XCTUnwrap(workflows(model).first)
        XCTAssertTrue(model.isActive(row))
        await model.setActive(workflowId: row.id, active: false)
        XCTAssertFalse(model.isActive(row))
        XCTAssertFalse(model.isToggling(row))
        XCTAssertNil(model.toggleFailure)
        XCTAssertTrue(transport.sentRequests.contains { $0.hasPrefix("PATCH \(Self.api)/workflows") })

        // A fresh list read is the truth and drops the override.
        await model.loadWorkflows()
        XCTAssertTrue(model.isActive(row))
    }

    /// ⛔ REMOVED RATHER THAN NEGATED: a refused toggle puts the switch back on the list's value.
    func testARefusedToggleRevertsAndSaysWhy() async throws {
        let rules: [FixtureTransport.Rule] = [
            .get("\(Self.api)/workflows", .fixture("mobile/district-workflows.json")),
            .any("\(Self.api)/workflows", .status(500)),
        ] + Self.loaded
        let (model, _) = await model(rules)
        let row = try XCTUnwrap(workflows(model).last)
        XCTAssertFalse(model.isActive(row))
        await model.setActive(workflowId: row.id, active: true)
        XCTAssertFalse(model.isActive(row))
        XCTAssertNotNil(model.toggleFailure)

        model.dismissToggleFailure()
        XCTAssertNil(model.toggleFailure)
    }

    /// ⛔ A ROLE THE SERVER WOULD REFUSE NEVER SENDS THE WRITE.
    func testARoleThatCannotMutateSendsNothing() async throws {
        let (model, transport) = await model(Self.loaded, role: nil)
        XCTAssertFalse(model.canToggle)
        let row = try XCTUnwrap(workflows(model).first)
        await model.setActive(workflowId: row.id, active: false)
        model.requestCampaignChange(enable: false)
        XCTAssertNil(model.campaignConfirm)
        await model.confirmCampaignChange()
        XCTAssertTrue(model.isActive(row))
        XCTAssertFalse(transport.sentRequests.contains { $0.hasPrefix("PATCH") })
    }

    func testAToggleBeforeTheListAnswersIsDropped() async {
        let rules: [FixtureTransport.Rule] = [.get("\(Self.api)/workflows", .status(500))] + Self.loaded
        let (model, transport) = await model(rules)
        await model.setActive(workflowId: Self.active, active: false)
        XCTAssertTrue(model.activeOverrides.isEmpty)
        XCTAssertFalse(transport.sentRequests.contains { $0.hasPrefix("PATCH") })
    }

    // MARK: - The campaign

    func testAConfirmedPauseAdoptsTheReply() async {
        let (model, _) = await model(Self.loaded)
        // ⚠️ ASKING FOR THE VALUE ALREADY HELD OPENS NOTHING.
        model.requestCampaignChange(enable: true)
        XCTAssertNil(model.campaignConfirm)

        model.requestCampaignChange(enable: false)
        XCTAssertEqual(model.campaignConfirm?.enable, false)
        await model.confirmCampaignChange()
        XCTAssertNil(model.campaignConfirm)
        XCTAssertFalse(model.campaignPending)
        XCTAssertNil(model.campaignFailure)
        guard case let .ready(status) = model.campaign else {
            return XCTFail("campaign not ready: \(model.campaign)")
        }
        XCTAssertFalse(status.infiniteSdrEnabled)
    }

    /// ⛔ THE CARD KEEPS THE LAST STATE THE SERVER SENT when the write fails.
    func testAFailedPauseKeepsTheLastStatus() async {
        let rules: [FixtureTransport.Rule] = [
            .get("\(Self.api)/workspace/campaign-status", .fixture("mobile/district-campaign-status.json")),
            .any("\(Self.api)/workspace/campaign-status", .status(500)),
        ] + Self.loaded
        let (model, _) = await model(rules)
        model.requestCampaignChange(enable: false)
        await model.confirmCampaignChange()
        XCTAssertNotNil(model.campaignFailure)
        guard case let .ready(status) = model.campaign else {
            return XCTFail("campaign not ready: \(model.campaign)")
        }
        XCTAssertTrue(status.infiniteSdrEnabled)
    }

    func testDismissingTheConfirmationWritesNothing() async {
        let (model, transport) = await model(Self.loaded)
        model.requestCampaignChange(enable: false)
        model.dismissCampaignConfirm()
        XCTAssertNil(model.campaignConfirm)
        await model.confirmCampaignChange()
        XCTAssertFalse(transport.sentRequests.contains { $0.hasPrefix("PATCH") })
    }

    /// ⛔ RESET CLEARS THE CACHE, THE OPEN ROW, THE OVERRIDES AND THE CONFIRMATION.
    func testResetStartsBothReadsClean() async {
        let (model, _) = await model(Self.loaded)
        await model.toggleExpanded(Self.active)
        await model.setActive(workflowId: Self.active, active: false)
        model.requestCampaignChange(enable: false)
        model.reset()
        XCTAssertNil(model.expanded)
        XCTAssertTrue(model.runs.isEmpty)
        XCTAssertTrue(model.activeOverrides.isEmpty)
        XCTAssertNil(model.campaignConfirm)
        guard case .loading = model.list, case .loading = model.campaign else {
            return XCTFail("reset should leave both reads loading")
        }
    }
}
