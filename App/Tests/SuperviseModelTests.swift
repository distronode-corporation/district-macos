import DistrictCall
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import XCTest

/// ⛔ THE ORDER A SUPERVISION PERFORMS THE CORE REDUCER'S COMMANDS IN, ON THIS APP'S SEAMS.
///
/// `SuperviseSession` is district-core-swift's and tested there; what is this app's is the
/// sequence across the Mac's call claim, the two routes and the two engines: the claim before
/// the seat, the listen room left before the coach room is joined, and the claim dropped on
/// every terminal path. Ported from district-ios #101 (`SuperviseModelTests`), without CallKit.
@MainActor
final class SuperviseModelTests: XCTestCase {
    private var media = FakeSuperviseMedia()
    private let server = FakeSuperviseServer()

    private func makeModel(role: WorkspaceRole? = .agency, receptionistOnCall: Bool? = true) throws -> SuperviseModel {
        try SuperviseFixtures.model(
            call: SuperviseFixtures.call(receptionistOnCall: receptionistOnCall),
            role: role,
            server: server,
            media: media
        )
    }

    /// Press Listen and let the listen room connect.
    private func listen(_ model: SuperviseModel) async {
        server.answerMonitor(.success(SuperviseFixtures.listenSeat))
        let engines = media.engines.count
        await model.listen()
        // ⚠️ THE ENGINE MUST EXIST BEFORE IT CAN SPEAK: an event yielded earlier goes nowhere.
        await waitUntil(state: "\(media.log)") {
            self.media.engines.count > engines && self.media.log.last == "connect wss://sfu.example.test listen.jwt"
        }
        media.engine(.listen, .connected)
        await waitUntil(state: "\(model.state.phase)") { model.state.phase == .listening }
    }

    private func takeOver(_ model: SuperviseModel) async {
        server.answerTakeover(.success(SuperviseFixtures.coachSeat))
        await model.takeOver()
        media.engine(.takeover, .connected)
        await waitUntil(state: "\(model.state.phase)") { model.state.phase == .takenOver }
    }

    // MARK: - Listen

    /// ⛔ THE CLAIM, THEN THE SEAT ASKED FOR AS A MAC, THEN A LISTEN-ONLY LEG.
    func test_MAC_SUPERVISE_01_listenClaimsTheCallThenAsksForTheSeatAsAMac() async throws {
        let model = try makeModel()
        await listen(model)

        XCTAssertEqual(server.requests, ["monitor cmh1live0001 macos"])
        XCTAssertEqual(media.log, ["claim", "beginLeg listen", "connect wss://sfu.example.test listen.jwt"])
        XCTAssertFalse(model.state.media.microphoneEnabled, "a listener publishes nothing")
        XCTAssertFalse(model.mayListen, "one supervision at a time")
    }

    /// ⛔ ONE CALL ON THIS MAC: refused with a sentence while a call or a room holds it, and
    /// nothing is claimed or asked.
    func test_MAC_SUPERVISE_02_aBusyMacRefusesListenWithItsSentence() async throws {
        let model = try makeModel()
        media.hasLiveCall = true
        await model.listen()
        XCTAssertEqual(model.startRefusal, SuperviseCopy.busyWithCall)

        media.hasLiveCall = false
        media.hasLiveRoom = true
        await model.listen()
        XCTAssertEqual(model.startRefusal, SuperviseCopy.busyInRoom)

        media.hasLiveRoom = false
        media.refusesClaim = true
        await model.listen()
        XCTAssertEqual(model.startRefusal, SuperviseCopy.busyWithCall, "a claim another call holds")
        XCTAssertEqual(media.log, [])
        XCTAssertEqual(server.requests, [])
    }

    /// ⛔ LISTENING TO AN ENDED CALL IS REFUSED BY THE SERVER (`call_ended`): the website's
    /// « Cet appel est terminé. » from the core's catalog, and the claim released.
    func test_MAC_SUPERVISE_03_anEndedCallsRefusalIsSaidByItsCode() async throws {
        let model = try makeModel()
        server.answerMonitor(.failure(.http(status: 409, message: "This call has ended.", code: "call_ended")))
        await model.listen()
        await waitUntil(state: "\(media.log)") { self.media.log.contains("release") }

        let expected = try XCTUnwrap(ApiErrorText.sentence(for: "call_ended"))
        XCTAssertEqual(SuperviseCopy.problem(model.state.problem), expected)
        XCTAssertEqual(
            L10nRuntime.withLocale(.frCA) { SuperviseCopy.problem(model.state.problem) },
            "Cet appel est terminé."
        )
        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertEqual(media.log, ["claim", "endLeg", "release"])
        XCTAssertFalse(media.isClaimed)
    }

    /// ⛔ STOP LISTENING: the room is left and the claim released; listening again is allowed.
    func test_MAC_SUPERVISE_04_stopLeavesTheRoomAndReleasesTheClaim() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()

        await model.stop()

        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
        XCTAssertEqual(model.state.phase, .idle)
        XCTAssertTrue(model.mayListen, "listening again is allowed, on a fresh engine")
    }

    /// ⛔ SLEEP, QUIT AND SIGN-OUT END IT THROUGH THE CALL CLAIM (``LiveCallOwner``), and a
    /// session end or a workspace switch through ``SupervisionEnding``: both leave the room.
    func test_MAC_SUPERVISE_05_theSystemEndsLeaveTheRoom() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()
        await model.endForSystem()
        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])

        await listen(model)
        media.clearLog()
        await model.endSupervision()
        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
    }

    // MARK: - Take over and hand back

    /// ⛔ THE COACH SEAT IS ASKED FOR WHILE STILL LISTENING; THE GRANT LEAVES THE LISTEN ROOM,
    /// THEN JOINS THE COACH ROOM, THEN OPENS THE MICROPHONE.
    func test_MAC_SUPERVISE_06_takeOverLeavesTheListenRoomBeforeJoiningTheCoachRoom() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()

        await takeOver(model)

        XCTAssertEqual(server.requests.last, "takeOver ws_1 cmh1live0001")
        XCTAssertEqual(media.log, [
            "disconnect", "beginLeg takeover", "connect wss://sfu.example.test coach.jwt", "setMuted false",
        ])
        XCTAssertFalse(model.state.mayWhisper, "no note while holding the call")
    }

    /// ⛔ A REFUSED TAKEOVER LEAVES THE PERSON LISTENING, with the refusal's sentence.
    func test_MAC_SUPERVISE_07_aRefusedTakeoverLeavesThePersonListening() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()
        server.answerTakeover(.failure(.http(status: 429, message: nil, code: "rate_limited")))

        await model.takeOver()

        XCTAssertEqual(model.state.phase, .listening)
        XCTAssertEqual(media.log, [], "nothing torn down")
        XCTAssertEqual(SuperviseCopy.problem(model.state.problem), ApiErrorText.sentence(for: "rate_limited"))
    }

    /// ⛔ THE MICROPHONE IS ASKED BEFORE THE SERVER: a refusal asks nothing and keeps listening,
    /// with Sean's sentence for a microphone that cannot be used.
    func test_MAC_SUPERVISE_08_aRefusedMicrophoneAsksNoTakeover() async throws {
        media = FakeSuperviseMedia(microphone: FakeMicrophoneAccess(status: .denied))
        let model = try makeModel()
        await listen(model)

        await model.takeOver()

        XCTAssertEqual(model.state.phase, .listening)
        XCTAssertFalse(server.requests.contains { $0.hasPrefix("takeOver") })
        XCTAssertEqual(model.startRefusal, SuperviseCopy.takeOverJoinFailed)
    }

    /// ⛔ HAND BACK IS LEAVING: the coach room is left and the claim released.
    func test_MAC_SUPERVISE_09_handBackLeavesTheCoachRoom() async throws {
        let model = try makeModel()
        await listen(model)
        await takeOver(model)
        media.clearLog()

        await model.stop()

        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
        XCTAssertFalse(media.isClaimed)
    }

    /// The mute control reaches the coach's microphone, and only once the call is taken over.
    func test_MAC_SUPERVISE_10_muteReachesTheCoachOnlyOnceTakenOver() async throws {
        let model = try makeModel()
        await listen(model)
        await model.toggleMute()
        XCTAssertFalse(media.log.contains { $0.hasPrefix("setMuted") }, "a listener has no microphone")

        await takeOver(model)
        media.engine(.takeover, .microphoneChanged(enabled: true))
        await waitUntil { model.state.media.microphoneEnabled }
        media.clearLog()

        await model.toggleMute()
        XCTAssertEqual(media.log, ["setMuted true"])
    }

    // MARK: - Roles and the colleague's own call

    /// ⛔ A VIEWER LISTENS AND DOES NOTHING ELSE.
    func test_MAC_SUPERVISE_11_aViewerMayOnlyListen() async throws {
        let model = try makeModel(role: .viewer)
        XCTAssertTrue(model.mayListen)
        XCTAssertFalse(model.state.mayWhisper)
        await listen(model)
        XCTAssertFalse(model.state.mayTakeOver)

        model.draft = "Offer the Tuesday slot."
        await model.sendWhisper()
        await model.takeOver()
        XCTAssertEqual(server.requests, ["monitor cmh1live0001 macos"])
    }

    /// ⛔ ON A COLLEAGUE'S OWN SOFTPHONE CALL, LISTEN STAYS AND THE NOTE AND TAKE OVER GO (Sean,
    /// 2026-11-05), with « Votre réceptionniste ne participe pas à cet appel ».
    func test_MAC_SUPERVISE_12_aColleaguesOwnCallOffersListenOnly() async throws {
        let model = try makeModel(receptionistOnCall: false)
        XCTAssertFalse(model.state.receptionistOnCall)
        XCTAssertFalse(model.state.mayWhisper)
        await listen(model)
        XCTAssertFalse(model.state.mayTakeOver)
        XCTAssertEqual(
            L10nRuntime.withLocale(.frCA) { SuperviseCopy.receptionistNotOnCall },
            "Votre réceptionniste ne participe pas à cet appel"
        )
    }

    /// ⚠️ A SERVER BEFORE LIVE SUPERVISE SENDS NO `receptionistOnCall`: read as `true`, the
    /// website's default, with the route's 409 as the fallback.
    func test_MAC_SUPERVISE_13_anAbsentReceptionistFlagReadsAsPresent() throws {
        let model = try makeModel(receptionistOnCall: nil)
        XCTAssertTrue(model.state.receptionistOnCall)
        XCTAssertTrue(model.state.mayWhisper)
    }

    // MARK: - The note and its receipt

    /// The note is trimmed, sent once, and cleared; the previous receipt goes with it.
    func test_MAC_SUPERVISE_14_aDeliveredNoteClearsTheDraftAndTheReceipt() async throws {
        let model = try makeModel()
        model.events.onEvent?(SuperviseFixtures.envelope(.whisperApplied, .object([
            "applied": .bool(true), "firstWords": .string("Sure."),
        ])))
        await waitUntil { model.state.receipt != nil }

        model.draft = "  Offer the Tuesday slot.  "
        await model.sendWhisper()

        XCTAssertEqual(server.requests, ["whisper Offer the Tuesday slot."])
        XCTAssertEqual(model.draft, "")
        XCTAssertNil(model.state.receipt)
    }

    /// ⛔ ONE NOTE AT A TIME: a second press while one is on its way sends nothing.
    func test_MAC_SUPERVISE_15_aSecondSendWhileOneIsOnItsWayIsDropped() async throws {
        let model = try makeModel()
        server.holdsWhispers = true
        model.draft = "Offer the Tuesday slot."
        let first = Task { await model.sendWhisper() }
        await waitUntil { self.server.isHoldingWhisper }
        XCTAssertTrue(model.sending)

        await model.sendWhisper()
        server.releaseWhisper()
        await first.value

        XCTAssertEqual(server.requests, ["whisper Offer the Tuesday slot."])
    }

    /// The route's limit is checked here, with Sean's sentence, and nothing is sent.
    func test_MAC_SUPERVISE_16_aNoteOverTheLimitIsRefusedLocally() async throws {
        let model = try makeModel()
        model.draft = String(repeating: "a", count: SuperviseCopy.whisperLimit + 1)
        await model.sendWhisper()
        XCTAssertEqual(model.whisperProblem, SuperviseCopy.whisperTooLong(2000))
        XCTAssertEqual(
            L10nRuntime.withLocale(.frCA) { SuperviseCopy.whisperTooLong(2000) },
            "La consigne doit compter au plus 2000 caractères."
        )
        XCTAssertEqual(server.requests, [])
    }

    /// A refusal is said by its code; one this build does not know gets the website's fallback,
    /// and the draft is kept for another try.
    func test_MAC_SUPERVISE_17_aFailedNoteKeepsTheDraft() async throws {
        let model = try makeModel()
        server.answerWhisper(.failure(.http(status: 409, message: nil, code: "call_has_no_receptionist")))
        model.draft = "Offer the Tuesday slot."
        await model.sendWhisper()
        XCTAssertEqual(model.whisperProblem, ApiErrorText.sentence(for: "call_has_no_receptionist"))
        XCTAssertEqual(model.draft, "Offer the Tuesday slot.")

        server.answerWhisper(.failure(.http(status: 400, message: nil, code: "not_a_code_this_build_knows")))
        await model.sendWhisper()
        XCTAssertEqual(model.whisperProblem, SuperviseCopy.whisperFailed)
    }

    /// ⛔ ONLY THIS CALL'S RECEIPT: the event is relayed to the whole workspace.
    func test_MAC_SUPERVISE_18_aReceiptForAnotherCallIsIgnored() async throws {
        let model = try makeModel()
        model.events.onEvent?(SuperviseFixtures.envelope(
            .whisperApplied,
            .object(["applied": .bool(false), "reason": .string("transfer")]),
            callId: "cmh1other0002"
        ))
        model.events.onEvent?(SuperviseFixtures.envelope(
            .whisperApplied,
            .object(["applied": .bool(false), "reason": .string("taken_over")])
        ))
        await waitUntil { model.state.receipt != nil }
        XCTAssertEqual(model.state.receipt?.reason, .takenOver)
    }

    // MARK: - The call ending

    /// ⛔ THE CALL ENDING WHILE LISTENING leaves the room, and the screen says the call has ended.
    func test_MAC_SUPERVISE_19_theCallEndingWhileListeningEndsTheSupervision() async throws {
        let model = try makeModel()
        await listen(model)
        media.clearLog()

        model.events.onEvent?(SuperviseFixtures.envelope(.callEnded, .object(["status": .string("completed")])))
        await waitUntil { model.state.phase == .over }

        XCTAssertEqual(media.log, ["disconnect", "endLeg", "release"])
        XCTAssertFalse(model.mayListen)
    }

    /// ⛔ STOP, THEN LISTEN AGAIN: the first engine's late `disconnected` ends nothing.
    func test_MAC_SUPERVISE_20_aStoppedEnginesLateEventEndsNothing() async throws {
        let model = try makeModel()
        await listen(model)
        await model.stop()
        await listen(model)
        XCTAssertEqual(media.engines.count, 2)

        media.engine(at: 0, .disconnected(reason: "late"))
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(model.state.phase, .listening)
        XCTAssertNil(model.state.problem)
    }
}
