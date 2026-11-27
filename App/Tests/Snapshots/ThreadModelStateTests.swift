@testable import DistrictMac
import DistrictModel
import XCTest

/// One conversation's thread model driven through its timeline, the older page, a reply and
/// an AI draft, answered by the service's recorded responses (`contracts/`). The draft
/// autosave and restore are pinned in ``ThreadModelDraftWriteTests``.
///
/// ⚠️ THE WRITES ARE ANSWERED AFTER `ScreenRules.loaded`: the reads keep their recorded `.get`
/// rules there, which match first. The AI draft is a POST to the draft path (its GET is the
/// saved draft's read), and every other write (the send, the draft delete after it) is
/// answered by the messages rule.
@MainActor
final class ThreadModelStateTests: XCTestCase {
    private static let api = "/api/district"
    private static let threadKey = "contact:contact_contract_1"

    private static func rules(
        timeline: FixtureTransport.Reply? = nil,
        send: FixtureTransport.Reply = .fixture("mobile/district-message-send.json"),
        draft: FixtureTransport.Reply = .fixture("mobile/district-ai-draft.json")
    ) -> [FixtureTransport.Rule] {
        (timeline.map { [.get("\(api)/timeline", $0)] } ?? []) + ScreenRules.loaded + [
            FixtureTransport.Rule(method: .post, pattern: "\(api)/messages/draft", op: nil, reply: draft),
            .any("\(api)/messages(/.*)?", send),
        ]
    }

    /// The recorded timeline with an older page to read, for the "load older" control.
    private static let hasOlder = FixtureTransport.Reply.edited("mobile/district-timeline.json") { body in
        var page = body["pageInfo"] as? [String: Any] ?? [:]
        page["hasMore"] = true
        body["pageInfo"] = page
    }

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency,
        replyTargets: [ReplyTarget] = [ReplyTarget(to: "+14165551234", channel: MessageChannel.sms)]
    ) async -> (ThreadModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "thread.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = ThreadModel(
            container: app.container,
            workspaceId: app.workspaceId,
            role: role,
            threadKey: Self.threadKey,
            replyTargets: replyTargets
        )
        await model.load()
        return (model, transport)
    }

    private func timelineReads(_ transport: FixtureTransport) -> Int {
        transport.sentRequests.filter { $0 == "GET \(Self.api)/timeline" }.count
    }

    func testTheRecordedTimelineLoads() async {
        let (model, _) = await model(Self.rules())
        XCTAssertEqual(model.current?.events.isEmpty, false)
        XCTAssertTrue(model.canReply)
        XCTAssertTrue(model.canAttach)
    }

    func testAnUnopenableThreadKeyFailsWithoutARead() async {
        let transport = FixtureTransport(rules: Self.rules())
        let defaults = UserDefaults(suiteName: "thread.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = ThreadModel(
            container: app.container,
            workspaceId: app.workspaceId,
            role: .agency,
            threadKey: "",
            replyTargets: []
        )
        await model.load()
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
        XCTAssertEqual(timelineReads(transport), 0)
    }

    func testAFailedTimelineIsTheFailureState() async {
        let (model, _) = await model(Self.rules(timeline: .status(500)))
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
        XCTAssertNil(model.current)
    }

    func testAnEmptyTimelineIsTheEmptyState() async {
        let (model, _) = await model(Self.rules(timeline: .emptied("mobile/district-timeline.json")))
        guard case .empty = model.state else {
            return XCTFail("should be empty: \(model.state)")
        }
    }

    // MARK: - Older page

    func testLoadOlderIsRefusedWithoutAnOlderPage() async {
        let (model, transport) = await model(Self.rules())
        await model.loadOlder()
        XCTAssertEqual(timelineReads(transport), 1)
    }

    func testLoadOlderReadsTheNextPage() async {
        let (model, transport) = await model(Self.rules(timeline: Self.hasOlder))
        XCTAssertEqual(model.current?.hasMore, true)
        await model.loadOlder()
        XCTAssertEqual(timelineReads(transport), 2, "\(transport.sentRequests)")
        XCTAssertEqual(model.current?.loadingOlder, false)
        XCTAssertNil(model.current?.olderFailure)
    }

    // MARK: - Reply

    func testAReplyIsSentAndTheThreadReRead() async {
        let (model, transport) = await model(Self.rules())
        model.composerTextChanged("See you Thursday.")
        await model.send()
        XCTAssertEqual(
            model.composerText,
            "",
            "\(String(describing: model.current?.sendFailure)) \(transport.sentRequests)"
        )
        XCTAssertNil(model.current?.sendFailure)
        XCTAssertEqual(model.current?.sending, false)
        XCTAssertEqual(timelineReads(transport), 2)
    }

    func testARefusedReplyKeepsTheTextAndSaysWhy() async {
        let (model, _) = await model(Self.rules(send: .status(500)))
        model.composerTextChanged("See you Thursday.")
        await model.send()
        XCTAssertEqual(model.composerText, "See you Thursday.")
        XCTAssertNotNil(model.current?.sendFailure)
        model.dismissFailure()
        XCTAssertNil(model.current?.sendFailure)
    }

    /// ⚠️ NO REPLY TARGET, NO REPLY: a read-only role or a thread with no address sends nothing.
    func testWithoutAReplyTargetNothingIsSent() async {
        let (readOnly, readOnlyTransport) = await model(Self.rules(), role: nil)
        XCTAssertFalse(readOnly.canReply)
        readOnly.adoptDraft("See you Thursday.")
        await readOnly.send()
        await readOnly.generateDraft()
        XCTAssertFalse(readOnlyTransport.sentRequests.contains { !$0.hasPrefix("GET") })

        let (noAddress, _) = await model(Self.rules(), replyTargets: [])
        XCTAssertFalse(noAddress.canReply)
        XCTAssertFalse(noAddress.canAttach)
    }

    // MARK: - AI draft

    func testAnAIDraftFillsTheComposer() async {
        let (model, transport) = await model(Self.rules())
        await model.generateDraft()
        XCTAssertTrue(model.composerText.hasPrefix("Thanks for waiting"), "\(transport.sentRequests)")
        XCTAssertEqual(model.current?.draftGenerating, false)
    }

    func testAFailedAIDraftSaysWhy() async {
        let (model, _) = await model(Self.rules(draft: .status(500)))
        await model.generateDraft()
        XCTAssertEqual(model.composerText, "")
        XCTAssertNotNil(model.current?.sendFailure)
    }

    func testTheSubjectIsKeptAndAdopted() async {
        let (model, _) = await model(Self.rules())
        model.subjectChanged("Thursday")
        XCTAssertEqual(model.composerSubject, "Thursday")
        model.adoptSubject("Friday")
        XCTAssertEqual(model.composerSubject, "Friday")
        XCTAssertTrue(ThreadModel.isBlank("  \n"))
        XCTAssertFalse(ThreadModel.isBlank("x"))
    }
}
