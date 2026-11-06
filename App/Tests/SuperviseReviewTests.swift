import DistrictCall
@testable import DistrictMac
import DistrictModel
import XCTest

/// The fixes from district-ios #101's xhigh and max reviews, on the Mac supervision's own seams:
/// an ended row, a reconnect, the session ending or a workspace switch mid-call, a receipt
/// before the 200, a stop while the join is in flight, an end during the room swap, a drop
/// checked against the row, and a stale refusal.
///
/// ⚠️ THE TWO CALLKIT MUTE ITEMS (xhigh 5, max 8) HAVE NO MAC COUNTERPART: there is no system
/// mute control, and the Mac's own is offered only once the call is taken over.
@MainActor
final class SuperviseReviewTests: XCTestCase {
    private let media = FakeSuperviseMedia()
    private let server = FakeSuperviseServer()

    private func makeModel(status: String = "in-progress") throws -> SuperviseModel {
        try SuperviseFixtures.model(call: SuperviseFixtures.call(status: status), server: server, media: media)
    }

    private func listen(_ model: SuperviseModel) async {
        server.answerMonitor(.success(SuperviseFixtures.listenSeat))
        let engines = media.engines.count
        await model.listen()
        await waitUntil(state: "\(media.log)") {
            self.media.engines.count > engines && self.media.log.contains("connect wss://sfu.example.test listen.jwt")
        }
        media.engine(.listen, .connected)
        await waitUntil(state: "\(model.state.phase)") { model.state.phase == .listening }
    }

    // MARK: - An ended call

    /// ⛔ A ROW THAT HAS ALREADY ENDED OPENS ON "The call has ended.", never on Listen.
    func testARowThatEndedOpensOver() throws {
        let model = try makeModel(status: "completed")
        XCTAssertEqual(model.state.phase, .over)
        XCTAssertFalse(model.mayListen)
        XCTAssertFalse(model.state.mayWhisper)
        XCTAssertEqual(media.log, [], "nothing claimed")

        let ringing = try makeModel(status: "ringing")
        XCTAssertEqual(ringing.state.phase, .idle, "ringing is not over")
    }

    /// ⛔ EVERY SOCKET OPEN RE-READS THE ROW: an end missed while no socket was open is caught.
    func testAReconnectReReadsTheRowAndEndsAnEndedCall() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()
        try server.answerDetail(.success(SuperviseFixtures.call(status: "completed")))

        model.events.onOpen?()
        await waitUntil { model.state.phase == .over }

        XCTAssertTrue(server.requests.contains("detail ws_1 cmh1live0001"))
        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
    }

    func testAReconnectOnALiveCallChangesNothing() async throws {
        let model = try makeModel()
        await listen(model)
        try server.answerDetail(.success(SuperviseFixtures.call(status: "in-progress")))

        await model.refresh()

        XCTAssertEqual(model.state.phase, .listening)
    }

    // MARK: - The session ending, a workspace switch, sleep and quit

    /// ⛔ THE CALL STACK ENDS A LIVE SUPERVISION (a session that ended, a workspace switch).
    func testTheCallStackEndsALiveSupervision() async throws {
        let model = try makeModel()
        await listen(model)
        let stack = CallStack(microphone: FakeMicrophoneAccess(status: .granted))
        stack.supervisor = model
        media.clearLog()

        await stack.endSupervision()

        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// ⛔ THE REAL CALL STACK'S CLAIM: a supervision holds this Mac's one call (a dial, a room
    /// or a second supervision is refused), sleep, quit and sign-out reach it through
    /// ``CallStack/endEverything(_:)``, and the claim and the slot are given back.
    func testASupervisionHoldsTheMacsCallClaim() throws {
        let stack = CallStack(microphone: FakeMicrophoneAccess(status: .granted))
        let real = CallStackSuperviseMedia(stack: stack)
        let model = try makeModel()

        XCTAssertTrue(real.claim(model))
        XCTAssertTrue(stack.hasLiveCall)
        XCTAssertTrue(stack.supervisor === model)
        XCTAssertTrue(stack.callOwner === model)
        XCTAssertFalse(try real.claim(makeModel()), "one call on this Mac")

        real.release(model)
        XCTAssertFalse(stack.hasLiveCall)
        XCTAssertNil(stack.supervisor)
    }

    /// ⛔ A SESSION THAT ENDS ENDS A SUPERVISION; THE KEYPAD'S CALL ENDS ON SIGN-OUT ONLY (Sean,
    /// 2026-11-06), never on `unavailable` and never on a workspace switch.
    func testTheTeardownRules() {
        XCTAssertTrue(CallTeardown.endsSupervision(.signedOut("Signed out.")))
        XCTAssertTrue(CallTeardown.endsSupervision(.unavailable("Try again.")))
        XCTAssertFalse(CallTeardown.endsSupervision(.signedIn))
        XCTAssertFalse(CallTeardown.endsSupervision(.checking))

        XCTAssertTrue(CallTeardown.endsSoftphone(.signedOut("Signed out.")))
        XCTAssertFalse(CallTeardown.endsSoftphone(.unavailable("Try again.")))
        XCTAssertFalse(CallTeardown.endsSoftphone(.signedIn))
        XCTAssertFalse(CallTeardown.endsSoftphone(.checking))
    }

    /// The keypad's call is ended through its own system end (the carrier hang-up), not a press.
    func testTheCallStackEndsTheKeypadsCall() async {
        final class Softphone: LiveCallOwner {
            var ended = 0
            func endForSystem() async {
                ended += 1
            }
        }
        let softphone = Softphone()
        let stack = CallStack(microphone: FakeMicrophoneAccess(status: .granted))
        stack.softphone = softphone
        await stack.endSoftphone()
        XCTAssertEqual(softphone.ended, 1)
    }

    /// ⛔ A SWITCH FROM ONE WORKSPACE TO ANOTHER, HOWEVER MADE (the picker included), ends a
    /// supervision; the first workspace resolving does not.
    func testOnlyAWorkspaceToWorkspaceChangeIsASwitch() {
        XCTAssertTrue(CallTeardown.isWorkspaceSwitch(from: "ws_1", to: "ws_2"))
        XCTAssertFalse(CallTeardown.isWorkspaceSwitch(from: nil, to: "ws_1"))
        XCTAssertFalse(CallTeardown.isWorkspaceSwitch(from: "ws_1", to: "ws_1"))
        XCTAssertFalse(CallTeardown.isWorkspaceSwitch(from: "ws_1", to: nil))
    }

    /// ⛔ A PICKER SWITCH PASSES THROUGH nil WHILE THE NEW LIST LOADS (Seer, PR #98): A, nil,
    /// B still ends the supervision, and A, nil, A (the same list read again) does not.
    func testASwitchThroughNilStillEndsTheSupervision() async throws {
        let stack = CallStack(microphone: FakeMicrophoneAccess(status: .granted))
        let model = try makeModel()
        await listen(model)
        stack.supervisor = model

        stack.workspaceSelected("ws_1")
        stack.workspaceSelected(nil)
        stack.workspaceSelected("ws_1")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.state.phase, .listening, "the same workspace read again is not a switch")

        stack.workspaceSelected(nil)
        stack.workspaceSelected("ws_2")
        await waitUntil { model.state.phase == .idle }
        XCTAssertFalse(media.isClaimed)
    }

    // MARK: - A receipt before the 200

    /// ⛔ A RECEIPT THAT ARRIVES BEFORE THE ROUTE ANSWERS IS KEPT.
    func testAReceiptBeforeTheTwoHundredIsKept() async throws {
        let model = try makeModel()
        server.holdsWhispers = true
        model.draft = "Offer the Tuesday slot."
        let sending = Task { await model.sendWhisper() }
        await waitUntil { self.server.isHoldingWhisper }

        model.events.onEvent?(SuperviseFixtures.envelope(.whisperApplied, .object([
            "applied": .bool(true), "firstWords": .string("Tuesday works."),
        ])))
        await waitUntil { model.state.receipt != nil }
        server.releaseWhisper()
        await sending.value

        XCTAssertEqual(model.state.receipt?.firstWords, "Tuesday works.")
    }

    // MARK: - A stop while the join is in flight

    /// ⛔ STOP DURING A HELD CONNECT LEAVES CLEANLY, the late connect changes nothing, and
    /// Listen works again on a fresh engine.
    func testStopDuringAnInFlightConnect() async throws {
        let model = try makeModel()
        media.holdsConnect = true
        server.answerMonitor(.success(SuperviseFixtures.listenSeat))
        let listening = Task { await model.listen() }
        await waitUntil { self.media.isHoldingConnect }

        await model.stop()
        XCTAssertEqual(model.state.phase, .idle)
        media.engine(.listen, .connected)
        media.releaseConnect()
        await listening.value
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.state.phase, .idle, "the stopped engine's late connect ends nothing")
        XCTAssertFalse(media.isClaimed)

        media.holdsConnect = false
        await listen(model)
        XCTAssertEqual(media.engines.count, 2)
    }

    // MARK: - The max review

    /// ⛔ AN END DURING THE ROOM SWAP BUILDS NO ORPHAN COACH ENGINE (item 2): the engine already
    /// built is ended, connected to nothing.
    func testAnEndDuringTheSwapEndsTheCoachEngineUnconnected() async throws {
        let model = try makeModel()
        await listen(model)
        server.answerTakeover(.success(SuperviseFixtures.coachSeat))
        media.holdsBeginLeg = true
        let taking = Task { await model.takeOver() }
        await waitUntil { self.media.isHoldingBeginLeg }

        await model.stop()
        media.clearLog()
        media.releaseBeginLeg()
        await taking.value

        XCTAssertEqual(media.log, ["endLeg"], "ended, and never connected")
        XCTAssertFalse(media.log.contains { $0.hasPrefix("connect") })
        XCTAssertEqual(model.state.phase, .idle)
    }

    /// ⛔ A DROP IS CHECKED AGAINST THE ROW (item 3): a room deleted because the call ended ends
    /// as over; a drop on a live call stays a drop.
    func testADropOnAnEndedCallEndsOverAndOnALiveCallStaysADrop() async throws {
        let model = try makeModel()
        await listen(model)
        try server.answerDetail(.success(SuperviseFixtures.call(status: "in-progress")))
        media.engine(.listen, .disconnected(reason: "network"))
        await waitUntil { model.state.problem != nil }
        await waitUntil { self.server.requests.contains { $0.hasPrefix("detail") } }
        XCTAssertEqual(model.state.problem, .listenDropped(reason: "network"))
        XCTAssertEqual(model.state.phase, .idle)

        await listen(model)
        try server.answerDetail(.success(SuperviseFixtures.call(status: "completed")))
        media.engine(.listen, .disconnected(reason: "room deleted"))
        await waitUntil { model.state.phase == .over }
    }

    /// ⛔ A REFUSAL FOR AN ABANDONED LISTEN IS NOT THE NEXT ONE'S (item 7).
    func testAStaleRefusalAfterStopAndListenAgainIsDropped() async throws {
        let model = try makeModel()
        server.answerMonitor(.failure(.http(status: 409, message: nil, code: "call_ended")))
        server.holdsMonitor = true
        let first = Task { await model.listen() }
        await waitUntil { self.server.isHoldingMonitor }
        await model.stop()

        server.answerMonitor(.success(SuperviseFixtures.listenSeat))
        await model.listen()
        await waitUntil { self.media.log.contains("connect wss://sfu.example.test listen.jwt") }
        server.releaseMonitor()
        await first.value
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(model.state.problem, "the first attempt's refusal is dropped")
        XCTAssertEqual(model.state.phase, .joiningListen)
    }
}
