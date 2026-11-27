@testable import DistrictMac
import DistrictModel
import XCTest

/// The support request list and the desk ticket thread driven through their writes, answered
/// by the service's recorded responses (`contracts/`).
///
/// ⚠️ EACH WRITE IS ANSWERED AFTER `ScreenRules.loaded`: the reads keep their recorded `.get`
/// rules there, which match first, so only a write (or a path no read uses) reaches the rule a
/// test adds.
@MainActor
final class SupportDeskModelStateTests: XCTestCase {
    private static let api = "/api/district"
    private static let ticketId = "desk_ticket_open"

    private static func support(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/support/requests", reply)]
    }

    private static func desk(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/desk/tickets/.*", reply)]
    }

    private func app(_ rules: [FixtureTransport.Rule]) async -> (ScreenSnapshotCase.SignedInApp, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "support.\(UUID().uuidString)") ?? .standard
        return await (ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults), transport)
    }

    private func supportModel(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (SupportModel, FixtureTransport) {
        let (app, transport) = await app(rules)
        let model = SupportModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.load()
        return (model, transport)
    }

    private func deskModel(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (DeskTicketModel, FixtureTransport) {
        let (app, transport) = await app(rules)
        let model = DeskTicketModel(
            container: app.container,
            workspaceId: app.workspaceId,
            ticketId: Self.ticketId,
            role: role
        )
        await model.load()
        return (model, transport)
    }

    private func writes(_ transport: FixtureTransport) -> [String] {
        transport.sentRequests.filter { !$0.hasPrefix("GET") }
    }

    // MARK: - Support

    func testTheRecordedRequestsLoad() async {
        let (model, _) = await supportModel(ScreenRules.loaded)
        XCTAssertEqual(model.requests.first?.id, "support_filed")
        XCTAssertTrue(model.canWrite)
        XCTAssertFalse(model.canSubmit)
    }

    func testAFailedListIsItsOwnState() async {
        let (model, _) = await supportModel([.get("\(Self.api)/support/requests", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.list else {
            return XCTFail("should have failed: \(model.list)")
        }
        XCTAssertTrue(model.requests.isEmpty)
    }

    func testAFiledRequestClosesTheComposerAndReReads() async {
        let (
            model,
            transport
        ) = await supportModel(Self.support(.fixture("mobile/district-support-request-create.json")))
        model.beginCompose()
        XCTAssertTrue(model.composing)
        model.selectKind(.problem)
        model.editSubject("  Calls drop  ")
        model.editMessage("Every outbound call drops after a minute.")
        XCTAssertTrue(model.canSubmit)
        await model.submit()
        XCTAssertFalse(model.composing, "\(model.create) \(transport.sentRequests)")
        XCTAssertEqual(model.draftSubject, "")
        guard case .done = model.create else {
            return XCTFail("should be done: \(model.create)")
        }
        XCTAssertEqual(writes(transport).count, 1)
        // The list is read again after the filing.
        XCTAssertEqual(transport.sentRequests.filter { $0 == "GET \(Self.api)/support/requests" }.count, 2)

        model.dismissNotice()
        guard case .idle = model.create else {
            return XCTFail("should be idle: \(model.create)")
        }
    }

    /// ⚠️ AN INCOMPLETE DRAFT IS MARKED REJECTED AND SENDS NOTHING.
    func testAnIncompleteDraftIsRejectedLocally() async {
        let (
            model,
            transport
        ) = await supportModel(Self.support(.fixture("mobile/district-support-request-create.json")))
        model.beginCompose()
        model.editSubject("Only a subject")
        await model.submit()
        XCTAssertTrue(model.draftRejected)
        XCTAssertTrue(writes(transport).isEmpty)
        model.editMessage("And now a message")
        XCTAssertFalse(model.draftRejected)
    }

    func testARefusedFilingKeepsTheDraft() async {
        let (model, _) = await supportModel(Self.support(.status(500)))
        model.beginCompose()
        model.editSubject("Calls drop")
        model.editMessage("Every outbound call drops.")
        await model.submit()
        guard case .failed = model.create else {
            return XCTFail("should have failed: \(model.create)")
        }
        XCTAssertTrue(model.composing)
        XCTAssertEqual(model.draftSubject, "Calls drop")
    }

    func testCancellingTheComposerClearsTheDraft() async {
        let (model, _) = await supportModel(ScreenRules.loaded)
        model.beginCompose()
        model.editSubject("Calls drop")
        model.cancelCompose()
        XCTAssertFalse(model.composing)
        XCTAssertEqual(model.draftSubject, "")
    }

    func testAReadOnlyRoleCannotCompose() async {
        let (model, transport) = await supportModel(Self.support(.status(500)), role: nil)
        model.beginCompose()
        XCTAssertFalse(model.composing)
        await model.submit()
        XCTAssertTrue(writes(transport).isEmpty)
    }

    // MARK: - Desk ticket

    func testTheRecordedTicketLoads() async {
        let (model, _) = await deskModel(ScreenRules.loaded)
        XCTAssertEqual(model.ticket?.id, Self.ticketId)
        XCTAssertEqual(model.ticket?.status, "open")
        XCTAssertFalse(model.canSend)
    }

    func testAFailedTicketReadIsItsOwnState() async {
        let (model, _) = await deskModel([.get("\(Self.api)/desk/tickets/[^/]+", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.thread else {
            return XCTFail("should have failed: \(model.thread)")
        }
        XCTAssertNil(model.ticket)
    }

    func testAReplyIsAppendedAndAdoptsTheTicket() async {
        let (model, transport) = await deskModel(Self.desk(.fixture("mobile/district-desk-ticket-reply.json")))
        model.editDraft("  We can do Friday.  ")
        XCTAssertTrue(model.canSend)
        await model.sendReply()
        XCTAssertEqual(model.draft, "", "\(String(describing: model.notice)) \(transport.sentRequests)")
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.ticket?.status, "waiting")
    }

    func testARefusedReplyKeepsTheDraftAndSaysWhy() async {
        let (model, _) = await deskModel(Self.desk(.status(500)))
        model.editDraft("We can do Friday.")
        await model.sendReply()
        XCTAssertEqual(model.draft, "We can do Friday.")
        XCTAssertNotNil(model.notice)
        model.dismissNotice()
        XCTAssertNil(model.notice)
    }

    func testAStatusChangeAdoptsTheReply() async {
        let (model, transport) = await deskModel(Self.desk(.fixture("mobile/district-desk-ticket-status.json")))
        await model.setStatus(.resolved)
        XCTAssertEqual(
            model.ticket?.status,
            "resolved",
            "\(String(describing: model.notice)) \(transport.sentRequests)"
        )
        XCTAssertNil(model.notice)
    }

    /// ⚠️ THE STATUS ALREADY HELD IS NOT WRITTEN AGAIN.
    func testTheCurrentStatusIsNotWrittenAgain() async {
        let (model, transport) = await deskModel(Self.desk(.status(500)))
        await model.setStatus(.open)
        XCTAssertTrue(writes(transport).isEmpty)
    }

    func testARefusedStatusChangeKeepsTheTicket() async {
        let (model, _) = await deskModel(Self.desk(.status(500)))
        await model.setStatus(.resolved)
        XCTAssertEqual(model.ticket?.status, "open")
        XCTAssertNotNil(model.notice)
    }

    func testAReadOnlyRoleSendsNoDeskWrite() async {
        let (model, transport) = await deskModel(Self.desk(.status(500)), role: nil)
        model.editDraft("We can do Friday.")
        XCTAssertFalse(model.canSend)
        await model.sendReply()
        await model.setStatus(.resolved)
        XCTAssertTrue(writes(transport).isEmpty)
    }
}
