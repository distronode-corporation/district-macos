@testable import DistrictCall
import DistrictData
import DistrictLive
@testable import DistrictMac
import DistrictNetwork
import XCTest

/// ⛔ THE MAC'S RING, FROM THE GATE TO THE ANSWER ROUND TRIP.
///
/// iOS is rung by a VoIP push and CallKit; this model is rung by the telemetry gate and
/// draws its own ring. What these pin is the Mac half: the gate's stop ends only a ring that
/// is still ringing, a ring the call ended reads as the caller hanging up, a person's decline
/// is reported once (DistrictCore 8.0.0) while a ring nobody declined sends nothing, a ring the
/// session withdraws leaves no summary, and the notification's Answer reaches the one answer
/// route once. No case reaches LiveKit: every answer here is refused
/// (409, the caller gone), which is the reducer's terminal path with no engine.
@MainActor
final class MacIncomingCallModelTests: XCTestCase {
    private final class FakePresenter: RingPresenting {
        private(set) var started: [String] = []
        private(set) var stops = 0

        func startRinging(workspaceId: String, callId: String) {
            started.append(callId)
        }

        func stopRinging() {
            stops += 1
        }

        func withdrawAlerts(callId _: String) {}
    }

    private var transport: RoutedTransport!
    private var presenter: FakePresenter!
    private var calls: CallStack!
    private var microphone: FakeMicrophoneAccess!
    private var settled = 0

    private func makeModel(
        microphone status: MicrophoneStatus = .granted,
        answer: Int = 409,
        decline: Int = 200
    ) -> IncomingCallModel {
        transport = RoutedTransport { request in
            if request.url.path.hasSuffix("/answer") {
                return HTTPResponse(statusCode: answer, body: Data(#"{"error":"Call ended"}"#.utf8))
            }
            if request.url.path.hasSuffix("/decline") {
                let body = decline == 200 ? #"{"success":true}"# : #"{"success":false,"error":"Server error"}"#
                return HTTPResponse(statusCode: decline, body: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 404, body: Data(#"{"error":"Not found"}"#.utf8))
        }
        let api = ApiClient(
            baseURL: URL(string: "https://www.example.test")!,
            transport: transport,
            accessToken: { "a.b.c" }
        )
        microphone = FakeMicrophoneAccess(status: status, grantsWhenAsked: true)
        calls = CallStack(microphone: microphone)
        presenter = FakePresenter()
        let model = IncomingCallModel(
            calls: calls,
            inbound: InboundCallRepository(client: api),
            callLog: CallsRepository(client: api),
            presenter: presenter
        )
        settled = 0
        model.onRingSettled = { [weak self] in self?.settled += 1 }
        model.sessionChanged(.signedIn)
        return model
    }

    private func ring(_ model: IncomingCallModel, callId: String = "call_1") async {
        model.ringStarted(workspaceId: "ws_1", callId: callId, workspaceName: "Acme")
        await waitUntil(state: "\(model.state.phase)") { model.isRinging }
    }

    private var answerRequests: [HTTPRequest] {
        transport.requests.filter { $0.url.path.hasSuffix("/answer") }
    }

    private var declineRequests: [HTTPRequest] {
        transport.requests.filter { $0.url.path.hasSuffix("/decline") }
    }

    /// Long enough for a spawned request (or a wrongly retried one) to reach the transport.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - The gate's stop

    func test_MAC_INCOMING_01_aRingTheCallEndedReadsAsTheCallerHangingUp() async {
        let model = makeModel()
        await ring(model)
        XCTAssertEqual(presenter.started, ["call_1"])
        XCTAssertEqual(model.workspaceName, "Acme")
        XCTAssertTrue(calls.hasLiveCall, "a ring holds the call claim, so a room cannot be joined over it")

        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .callEnded)
        await waitUntil { model.state.phase.isEnded }

        XCTAssertEqual(model.state.phase, .ended(.ringTimedOut))
        XCTAssertTrue(model.ringEndedByCall)
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: model.state, endedByOperator: false, ringEndedByCall: model.ringEndedByCall),
            "Call ended · the caller hung up"
        )
        XCTAssertGreaterThanOrEqual(presenter.stops, 1)
        XCTAssertTrue(answerRequests.isEmpty, "a ring that ends unanswered sends nothing")
        XCTAssertFalse(calls.hasLiveCall, "the claim is given back")
        XCTAssertEqual(settled, 1, "the gate is told it may take the next ring")
    }

    func test_MAC_INCOMING_02_theGatesTimeoutReadsAsNobodyAnswering() async {
        let model = makeModel()
        await ring(model)

        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .timedOut)
        await waitUntil { model.state.phase.isEnded }

        XCTAssertFalse(model.ringEndedByCall)
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: model.state, endedByOperator: false, ringEndedByCall: model.ringEndedByCall),
            "Call ended · nobody answered"
        )
    }

    func test_MAC_INCOMING_03_aStopForAnotherCallOrAnEchoedClearChangesNothing() async {
        let model = makeModel()
        await ring(model)

        model.ringStopped(workspaceId: "ws_1", callId: "call_other", reason: .callEnded)
        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .cleared)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(model.isRinging)
    }

    func test_MAC_INCOMING_04_theGatesStopNeverEndsACallBeingAnswered() async {
        let model = makeModel()
        let release = transport.hold(pathSuffix: "/answer")
        await ring(model)

        model.answerPressed()
        await waitUntil { model.state.phase == .answering }
        model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: .timedOut)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(model.state.phase, .answering, "the gate's thirty seconds must not tear down an answer")
        release()
        await waitUntil { model.state.phase.isEnded }
        XCTAssertEqual(model.state.phase, .ended(.callerCancelled))
    }

    // MARK: - Decline and withdrawal

    /// ⛔ A PERSON'S DECLINE IS REPORTED, EXACTLY ONCE, TO THE CALL'S OWN DECLINE ROUTE.
    func test_MAC_INCOMING_05_aDeclineIsReportedOnce() async throws {
        let model = makeModel()
        await ring(model)

        model.declinePressed()
        model.declinePressed()
        await waitUntil { model.state.phase.isEnded && !self.declineRequests.isEmpty }
        await settle()

        XCTAssertEqual(model.state.phase, .ended(.declined))
        XCTAssertTrue(answerRequests.isEmpty)
        XCTAssertEqual(declineRequests.count, 1, "two presses, one decline")
        let request = try XCTUnwrap(declineRequests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url.path, "/api/district/calls/call_1/decline")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String]
        XCTAssertEqual(body, ["workspaceId": "ws_1"])
        XCTAssertFalse(calls.hasLiveCall, "the claim is given back")
        XCTAssertEqual(settled, 1)
    }

    /// ⛔ NEVER AWAITED: the ring ends and the summary shows while the request is still out.
    func test_MAC_INCOMING_05b_aDeclineNeverWaitsForItsRequest() async {
        let model = makeModel()
        let release = transport.hold(pathSuffix: "/decline")
        await ring(model)

        model.declinePressed()
        await waitUntil { model.state.phase.isEnded && !self.declineRequests.isEmpty }

        XCTAssertEqual(model.state.phase, .ended(.declined), "ended with the request still held")
        XCTAssertGreaterThanOrEqual(presenter.stops, 1)
        XCTAssertFalse(calls.hasLiveCall)
        model.dismissEndedCall()
        await waitUntil { !model.isPresented }
        release()
        await settle()
        XCTAssertEqual(declineRequests.count, 1)
    }

    /// ⛔ NEVER RETRIED: a refused decline is not sent again, and the screen is unchanged.
    func test_MAC_INCOMING_05c_aFailedDeclineIsNotRetried() async {
        let model = makeModel(decline: 500)
        await ring(model)

        model.declinePressed()
        await waitUntil { !self.declineRequests.isEmpty }
        await settle()

        XCTAssertEqual(declineRequests.count, 1)
        XCTAssertEqual(model.state.phase, .ended(.declined))
    }

    /// ⛔ A WITHDRAWN RING SENDS NOTHING: nobody pressed Decline.
    func test_MAC_INCOMING_06_aWithdrawnRingLeavesNoSummary() async {
        let model = makeModel()
        await ring(model)

        model.ringWithdrawn(callId: "call_1")
        await waitUntil { !model.isPresented }
        await settle()

        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertGreaterThanOrEqual(presenter.stops, 1)
        XCTAssertFalse(calls.hasLiveCall)
        XCTAssertTrue(declineRequests.isEmpty, "a withdrawal is not a decline")
    }

    func test_MAC_INCOMING_07_sleepOrQuitWithdrawsARing() async {
        let model = makeModel()
        await ring(model)

        await calls.endEverything(.sleep)
        await waitUntil { !model.isPresented }
        await settle()

        XCTAssertTrue(answerRequests.isEmpty)
        XCTAssertTrue(declineRequests.isEmpty, "sleep and quit are not a decline")
    }

    /// ⛔ A RING ENDED BECAUSE NOBODY IS SIGNED IN SENDS NOTHING.
    func test_MAC_INCOMING_07b_aRingEndedForNoSessionSendsNothing() async {
        let model = makeModel()
        await ring(model)

        model.sessionChanged(.signedOut(""))
        await waitUntil { model.state.phase.isEnded }
        await settle()

        XCTAssertEqual(model.state.phase, .ended(.declined), "the decline's local ending")
        XCTAssertTrue(declineRequests.isEmpty, "a missing session is not a decline")
        XCTAssertFalse(calls.hasLiveCall)
    }

    /// ⛔ A RING THAT TIMES OUT OR THE CALL ENDS SENDS NOTHING EITHER.
    func test_MAC_INCOMING_07c_aRingNobodyDeclinedSendsNothing() async {
        for reason in [DesktopRingEnd.timedOut, .callEnded, .cancelled(.declined)] {
            let model = makeModel()
            await ring(model)

            model.ringStopped(workspaceId: "ws_1", callId: "call_1", reason: reason)
            await waitUntil { model.state.phase.isEnded }
            await settle()

            XCTAssertTrue(declineRequests.isEmpty, "\(reason)")
        }
    }

    // MARK: - One call at a time

    func test_MAC_INCOMING_08_aRingWhileACallIsLiveIsDropped() async {
        let model = makeModel()
        let other = RecordingCallOwner()
        XCTAssertTrue(calls.claimCall(other))

        model.ringStarted(workspaceId: "ws_1", callId: "call_2", workspaceName: nil)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(presenter.started.isEmpty, "nothing rings over a live call")
        XCTAssertEqual(settled, 1, "and the gate is freed at once")
    }

    func test_MAC_INCOMING_09_aSignedOutMacNeverRings() async {
        let model = makeModel()
        model.sessionChanged(.signedOut(""))

        model.ringStarted(workspaceId: "ws_1", callId: "call_1", workspaceName: nil)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(model.isPresented)
    }

    // MARK: - The notification's buttons

    func test_MAC_INCOMING_10_answerFromTheNotificationRingsThenAnswersOnce() async {
        let model = makeModel(microphone: .notDetermined)

        model.notificationAnswered(workspaceId: "ws_1", callId: "call_9")
        model.notificationAnswered(workspaceId: "ws_1", callId: "call_9")
        await waitUntil { model.state.phase.isEnded }

        XCTAssertEqual(
            presenter.started,
            ["call_9"],
            "a call the socket missed is rung first, so the reducer sees ring then answer"
        )
        XCTAssertEqual(answerRequests.count, 1, "two presses, one answer")
        XCTAssertEqual(answerRequests.first?.method, .post)
        XCTAssertEqual(answerRequests.first?.url.path, "/api/district/calls/call_9/answer")
        XCTAssertEqual(microphone.requestCount, 1, "the microphone is asked at the answer")
        XCTAssertEqual(model.state.phase, .ended(.callerCancelled))
    }

    /// ⚠️ THE KNOWN RESIDUAL IS THE FIRST HALF: Decline on an alert for a call that is not
    /// ringing here (a quit Mac's alert) sends nothing. The ringing call's is reported once.
    func test_MAC_INCOMING_11_declineFromTheNotificationOnlyTouchesTheRingingCall() async {
        let model = makeModel()
        await ring(model)

        model.notificationDeclined(callId: "call_other")
        await settle()
        XCTAssertTrue(model.isRinging)
        XCTAssertTrue(declineRequests.isEmpty, "a call not ringing here is not reported")

        model.notificationDeclined(callId: "call_1")
        await waitUntil { model.state.phase.isEnded && !self.declineRequests.isEmpty }
        await settle()
        XCTAssertEqual(model.state.phase, .ended(.declined))
        XCTAssertEqual(declineRequests.map(\.url.path), ["/api/district/calls/call_1/decline"])
    }

    // MARK: - The microphone at Answer

    /// ⚠️ PORTED FROM iOS's `MicrophoneAccessTests`, without its foreground condition: every
    /// Mac answer is a press with the app able to show the alert.
    func test_MAC_INCOMING_12_atAnswerOnlyAnUnaskedQuestionIsPut() async {
        let fresh = FakeMicrophoneAccess(status: .notDetermined, grantsWhenAsked: true)
        let first = await IncomingCallModel.askAtAnswer(fresh)
        XCTAssertTrue(first)
        let again = await IncomingCallModel.askAtAnswer(fresh)
        XCTAssertFalse(again, "an answered question is never put twice")
        XCTAssertEqual(fresh.requestCount, 1)

        let refused = FakeMicrophoneAccess(status: .denied)
        let afterARefusal = await IncomingCallModel.askAtAnswer(refused)
        XCTAssertFalse(afterARefusal)
        XCTAssertEqual(refused.requestCount, 0)
    }
}

/// A transport that answers by route, records every request, and can hold one route's
/// answer until the test releases it.
final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let route: @Sendable (HTTPRequest) -> HTTPResponse
    private var recorded: [HTTPRequest] = []
    private var held: (suffix: String, gate: AsyncGate)?

    init(_ route: @escaping @Sendable (HTTPRequest) -> HTTPResponse) {
        self.route = route
    }

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    /// Hold every request whose path ends in `pathSuffix` until the returned closure runs.
    func hold(pathSuffix: String) -> @Sendable () -> Void {
        let gate = AsyncGate()
        lock.withLock { held = (pathSuffix, gate) }
        return { gate.open() }
    }

    func send(_ request: HTTPRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let gate: AsyncGate? = lock.withLock {
            recorded.append(request)
            guard let held, request.url.path.hasSuffix(held.suffix) else { return nil }
            return held.gate
        }
        await gate?.wait()
        return route(request)
    }
}

/// Waiters suspend until ``open()``; after it, waiting returns at once.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = lock.withLock {
                guard !isOpen else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}
