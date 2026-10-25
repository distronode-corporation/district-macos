@testable import DistrictCall
import DistrictData
import DistrictLive
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import XCTest

/// The ring cancel (3.0.1): when the server ends a ring, this Mac stops ringing, words it by
/// the reason, and leaves a call it answered alone.
///
/// ⛔ THE WORDING IS THE REASON'S: answered elsewhere for `answered`, the caller hanging up
/// only for `call_ended`, declined for `declined` (DistrictCore 8.0.0), nobody answered
/// otherwise. None of them sends anything.
@MainActor
final class MacRingCancelTests: XCTestCase {
    private final class FakePresenter: RingPresenting {
        private(set) var started: [String] = []
        private(set) var withdrawn: [String] = []

        func startRinging(workspaceId _: String, callId: String) {
            started.append(callId)
        }

        func stopRinging() {}

        func withdrawAlerts(callId: String) {
            withdrawn.append(callId)
        }
    }

    private var transport: RoutedTransport!
    private var presenter: FakePresenter!

    private func makeModel() -> IncomingCallModel {
        transport = RoutedTransport { request in
            if request.url.path.hasSuffix("/answer") {
                return HTTPResponse(statusCode: 409, body: Data(#"{"error":"Call ended"}"#.utf8))
            }
            return HTTPResponse(statusCode: 404, body: Data(#"{"error":"Not found"}"#.utf8))
        }
        let api = ApiClient(
            baseURL: URL(string: "https://www.example.test")!,
            transport: transport,
            accessToken: { "a.b.c" }
        )
        presenter = FakePresenter()
        let model = IncomingCallModel(
            calls: CallStack(microphone: FakeMicrophoneAccess(status: .granted, grantsWhenAsked: true)),
            inbound: InboundCallRepository(client: api),
            callLog: CallsRepository(client: api),
            presenter: presenter
        )
        model.sessionChanged(.signedIn)
        return model
    }

    private func ringing() async -> IncomingCallModel {
        let model = makeModel()
        model.ringStarted(workspaceId: "ws_1", callId: "call_1", workspaceName: nil)
        await waitUntil(state: "\(model.state.phase)") { model.isRinging }
        return model
    }

    private func sentence(_ model: IncomingCallModel) -> String {
        IncomingCallCopy.sentence(
            for: model.state,
            endedByOperator: model.endedByOperator,
            ringEndedByCall: model.ringEndedByCall,
            ringAnsweredElsewhere: model.ringAnsweredElsewhere
        )
    }

    private var answerRequests: Int {
        transport.requests.count { $0.url.path.hasSuffix("/answer") }
    }

    private var declineRequests: Int {
        transport.requests.count { $0.url.path.hasSuffix("/decline") }
    }

    /// ⛔ ANSWERED ON ANOTHER DEVICE, FROM THE SOCKET: the ring stops, sends nothing, and says so.
    func test_MAC_RINGCANCEL_01_answeredElsewhereStopsTheRingAndSaysSo() async {
        let model = await ringing()

        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .cancelled(.answered))
        await waitUntil { model.state.phase.isEnded }

        XCTAssertEqual(model.state.phase, .ended(.ringTimedOut))
        XCTAssertTrue(model.ringAnsweredElsewhere)
        XCTAssertFalse(model.ringEndedByCall)
        XCTAssertEqual(sentence(model), "Answered on another device")
        XCTAssertEqual(answerRequests, 0, "a ring that ends unanswered here sends nothing")
    }

    /// ⛔ ONLY `call_ended` SAYS THE CALLER HUNG UP; `timeout` and `withdrawn` are a missed call.
    func test_MAC_RINGCANCEL_02_everyOtherReasonIsWordedByIt() async {
        for (reason, expected) in [
            (RingCancelReason.callEnded, "Call ended · the caller hung up"),
            (.timeout, "Call ended · nobody answered"),
            (.withdrawn, "Call ended · nobody answered"),
        ] {
            let model = await ringing()
            model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .cancelled(reason))
            await waitUntil { model.state.phase.isEnded }
            XCTAssertEqual(sentence(model), expected, "\(reason)")
            XCTAssertFalse(model.ringAnsweredElsewhere)
        }
    }

    /// ⛔ EVERY MEMBER DECLINED, THIS MAC'S PERSON ON ANOTHER DEVICE: the ring stops and reads
    /// as the decline it was, never as a missed call, and this Mac reports no decline of its own.
    func test_MAC_RINGCANCEL_06_declinedElsewhereReadsAsDeclinedAndSendsNothing() async {
        let model = await ringing()

        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .cancelled(.declined))
        await waitUntil { model.state.phase.isEnded }
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.state.phase, .ended(.declined))
        XCTAssertFalse(model.ringAnsweredElsewhere)
        XCTAssertFalse(model.ringEndedByCall)
        XCTAssertEqual(sentence(model), "Call ended · declined")
        XCTAssertEqual(answerRequests, 0)
        XCTAssertEqual(declineRequests, 0, "only a press on this Mac reports a decline")
        XCTAssertTrue(transport.requests.allSatisfy { $0.method == .get }, "nothing was written")
    }

    /// ⛔ THE SAME FROM THE PUSH, WHICH ALSO TAKES THE CALL'S DELIVERED ALERTS AWAY.
    func test_MAC_RINGCANCEL_07_theDeclinedPushWithdrawsItsAlerts() async {
        let model = await ringing()

        model.ringCancelled(RingCancel(workspaceId: "ws_1", callId: "call_1", reason: .declined))
        await waitUntil { model.state.phase.isEnded }

        XCTAssertEqual(presenter.withdrawn, ["call_1"])
        XCTAssertEqual(sentence(model), "Call ended · declined")
        XCTAssertEqual(declineRequests, 0)
    }

    /// ⛔ THE PUSH STOPS THE RING AND TAKES THE CALL'S DELIVERED ALERTS AWAY.
    func test_MAC_RINGCANCEL_03_thePushStopsTheRingAndWithdrawsItsAlerts() async {
        let model = await ringing()

        model.ringCancelled(RingCancel(workspaceId: "ws_1", callId: "call_1", reason: .answered))
        await waitUntil { model.state.phase.isEnded }

        XCTAssertEqual(presenter.withdrawn, ["call_1"])
        XCTAssertEqual(sentence(model), "Answered on another device")
    }

    /// ⚠️ A CANCEL FOR A CALL THAT DID NOT RING HERE (the app was quit, or the socket missed it)
    /// still takes the server's delivered alert away, and touches the ringing call not at all.
    func test_MAC_RINGCANCEL_04_aCancelForAnotherCallOnlyWithdrawsItsAlerts() async {
        let model = await ringing()

        model.ringCancelled(RingCancel(workspaceId: "ws_1", callId: "call_other", reason: .answered))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(presenter.withdrawn, ["call_other"])
        XCTAssertTrue(model.isRinging)
        XCTAssertEqual(model.callId, "call_1")
    }

    /// ⛔ THE CALL THIS MAC ANSWERED IGNORES THE CANCEL: no alert work, no new sentence.
    func test_MAC_RINGCANCEL_05_theCallThisMacAnsweredIgnoresTheCancel() async {
        let model = await ringing()
        model.answerPressed()
        await waitUntil { model.state.phase.isEnded }
        let after = model.state

        model.ringCancelled(RingCancel(workspaceId: "ws_1", callId: "call_1", reason: .answered))
        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .cancelled(.answered))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.state, after)
        XCTAssertFalse(model.ringAnsweredElsewhere)
        XCTAssertEqual(presenter.withdrawn, [])
        XCTAssertEqual(answerRequests, 1)
    }
}
