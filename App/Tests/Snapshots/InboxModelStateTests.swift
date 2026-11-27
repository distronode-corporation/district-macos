@testable import DistrictMac
import DistrictModel
import XCTest

/// The inbox list model driven through its reads, mark all read, the search box and the
/// assignment filter, answered by the service's recorded responses (`contracts/`). The assign
/// sheet's own writes are pinned in ``ThreadAssignmentTests``.
@MainActor
final class InboxModelStateTests: XCTestCase {
    private static let api = "/api/district"
    private static let contact = "contact:contact_contract_1"
    private static let address = "addr:14165558888"

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (InboxModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "inbox.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = InboxModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.load()
        return (model, transport)
    }

    private func reads(_ transport: FixtureTransport) -> Int {
        transport.sentRequests.filter { $0 == "GET \(Self.api)/conversations" }.count
    }

    private func draftKeys(_ model: InboxModel) -> Set<String>? {
        guard case let .content(_, _, keys, _) = model.state else { return nil }
        return keys
    }

    func testTheRecordedConversationsLoadWithTheirDraftBadges() async {
        let (model, _) = await model(ScreenRules.loaded)
        XCTAssertEqual(model.unreadTotal, 2)
        XCTAssertNotNil(model.conversation(forThreadKey: Self.contact))
        XCTAssertNil(model.conversation(forThreadKey: "nobody"))
        XCTAssertEqual(draftKeys(model)?.contains(Self.contact), true)
    }

    /// ⚠️ A ROLE THAT CANNOT REPLY IS NOT SHOWN DRAFT BADGES, AND CANNOT MARK ALL READ.
    func testAReadOnlyRoleHasNoDraftsAndCannotMarkAllRead() async {
        let (model, transport) = await model(ScreenRules.loaded, role: nil)
        XCTAssertEqual(draftKeys(model), [])
        await model.markAllRead()
        XCTAssertFalse(transport.sentRequests.contains { $0.contains("mark-read") })
    }

    func testAnEmptyInboxIsTheEmptyState() async {
        let (model, _) = await model(ScreenRules.empty)
        guard case .empty = model.state else {
            return XCTFail("should be empty: \(model.state)")
        }
        XCTAssertEqual(model.unreadTotal, 0)
    }

    func testAFailedReadIsTheFailureState() async {
        let (model, _) = await model(ScreenRules.failing)
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
    }

    func testMarkAllReadWritesAndReReads() async {
        let (model, transport) = await model(ScreenRules.loaded)
        await model.markAllRead()
        XCTAssertTrue(transport.sentRequests.contains { !$0.hasPrefix("GET") && $0.contains("mark-read") })
        XCTAssertEqual(reads(transport), 2)
    }

    /// ⚠️ A REFUSED MARK ALL READ LEAVES THE LIST AS IT WAS, without a re-read.
    func testARefusedMarkAllReadDoesNotReRead() async {
        let rules: [FixtureTransport.Rule] = [.any("\(Self.api)/messages/mark-read", .status(500))] + ScreenRules.loaded
        let (model, transport) = await model(rules)
        await model.markAllRead()
        XCTAssertEqual(reads(transport), 1)
        XCTAssertEqual(model.unreadTotal, 2)
    }

    func testARefreshKeepsTheRowsWhileItReads() async {
        let (model, transport) = await model(ScreenRules.loaded)
        await model.refreshFromPush()
        XCTAssertEqual(reads(transport), 2)
        XCTAssertNotNil(model.conversation(forThreadKey: Self.contact))
    }

    // MARK: - Search

    func testTheSearchBoxIdlesBelowTheFloorAndFailsWhenTheReadDoes() async {
        let rules: [FixtureTransport.Rule] = [.get("\(Self.api)/messages/search", .status(500))] + ScreenRules.loaded
        let (model, transport) = await model(rules)
        model.searchQueryChanged("   ")
        guard case .idle = model.searchState else {
            return XCTFail("should be idle: \(model.searchState)")
        }
        model.searchQueryChanged("a")
        guard case .belowFloor = model.searchState else {
            return XCTFail("should be below the floor: \(model.searchState)")
        }
        model.searchQueryChanged("Thursday")
        guard case .searching = model.searchState else {
            return XCTFail("should be searching: \(model.searchState)")
        }
        await waitUntil(timeout: 5, state: "\(model.searchState) \(transport.sentRequests)") {
            if case .searching = model.searchState {
                return false
            }
            return true
        }
        guard case .failed = model.searchState else {
            return XCTFail("should have failed: \(model.searchState) \(transport.sentRequests)")
        }
    }

    // MARK: - Assignment

    private static let assigned: [FixtureTransport.Rule] = [
        .get("\(api)/conversations", .fixture("mobile/district-conversations-assignee.json")),
    ] + ScreenRules.loaded

    func testAssignedToMeHidesTheOthers() async throws {
        let (model, _) = await model(Self.assigned)
        let mine = try XCTUnwrap(model.conversation(forThreadKey: Self.contact))
        let other = try XCTUnwrap(model.conversation(forThreadKey: Self.address))
        XCTAssertEqual(model.visible([mine, other]).count, 2)
        model.assignedToMeOnly = true
        XCTAssertEqual(model.visible([mine, other]).map(\.threadKey), [Self.contact])
        XCTAssertTrue(InboxModel.hidesOpenConversation(other, assignedToMeOnly: true))
        XCTAssertFalse(InboxModel.hidesOpenConversation(mine, assignedToMeOnly: true))
        XCTAssertFalse(InboxModel.hidesOpenConversation(nil, assignedToMeOnly: true))
        XCTAssertNil(InboxModel.assignTarget(other, assignedToMeOnly: true))
        XCTAssertEqual(InboxModel.assignTarget(mine, assignedToMeOnly: true)?.threadKey, Self.contact)
        XCTAssertNil(InboxModel.assignTarget(nil, assignedToMeOnly: false))
    }

    func testBeginAssigningOpensTheSheetForThatThread() async throws {
        let (model, _) = await model(Self.assigned)
        let mine = try XCTUnwrap(model.conversation(forThreadKey: Self.contact))
        model.beginAssigning(mine)
        XCTAssertEqual(model.assigning?.threadKey, Self.contact)
    }

    func testAReadOnlyRoleCannotOpenTheAssignSheet() async throws {
        let (model, _) = await model(Self.assigned, role: nil)
        let mine = try XCTUnwrap(model.conversation(forThreadKey: Self.contact))
        model.beginAssigning(mine)
        XCTAssertNil(model.assigning)
    }

    /// ⛔ AFTER AN ASSIGNMENT THE RE-READ SAYS WHETHER THE OPEN THREAD STILL BELONGS ON SCREEN.
    func testAnAssignmentReReadsAndClosesAThreadTheFilterNowHides() async {
        let (model, transport) = await model(Self.assigned)
        model.assignedToMeOnly = true
        await model.assigned(Self.address)
        XCTAssertEqual(reads(transport), 2)
        let check = model.assignClose
        XCTAssertEqual(check?.threadKey, Self.address)
        if let check {
            XCTAssertTrue(model.closes(check, open: Self.address))
            XCTAssertFalse(model.closes(check, open: Self.contact))
            XCTAssertFalse(model.closes(check, open: nil))
        }
        // Settled once: a second settle with nothing pending changes nothing.
        model.assignClose = nil
        model.settleAssignClose(read: 99)
        XCTAssertNil(model.assignClose)
    }
}
