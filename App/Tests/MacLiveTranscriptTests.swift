import AppKit
import DistrictLive
@testable import DistrictMac
import DistrictModel
import XCTest

/// ⛔ THE LIVE TRANSCRIPT ON THE MAC RIDES THE SOCKET THE MAC HOLDS FOR RINGING.
///
/// What is the Mac's, and tested here: that watching a call keeps that one socket running
/// (even with "Ring on this computer" off, when it then does not ring), that the socket
/// keeps the workspace relay (no `socket.mode`), that a watched call is subscribed on every
/// open, renewals included, and that the frames reach the screen watching that call and no
/// other. The transcript's rules are district-core-swift's `TranscriptReducer`.
@MainActor
final class MacLiveTranscriptTests: XCTestCase {
    private typealias FakeSession = MacDesktopLiveTests.FakeSession

    private var sessions: [FakeSession] = []
    private var center = NotificationCenter()
    private var ringSetting: Bool?

    private var running: [FakeSession] {
        sessions.filter { $0.stops == 0 && $0.signOuts == 0 }
    }

    private func makeLive(ringHere: Bool) -> DesktopLive {
        ringSetting = ringHere
        return DesktopLive(
            calls: CallStack(microphone: FakeMicrophoneAccess(status: .granted)),
            setting: RingSetting(
                load: { [weak self] in self?.ringSetting },
                save: { [weak self] in self?.ringSetting = $0 }
            ),
            workspaceCenter: center,
            beginActivity: { NSObject() },
            endActivity: { _ in },
            factory: { [weak self] request in
                let session = FakeSession(request: request)
                self?.sessions.append(session)
                if request.rings {
                    request.onStatus(.live)
                }
                return session
            }
        )
    }

    private func envelope(_ eventType: String, callId: String = "call_1", data: String) -> TelemetryEnvelope? {
        try? JSONDecoder().decode(TelemetryEnvelope.self, from: Data("""
        {"workspaceId":"ws_1","callId":"\(callId)","eventType":"\(eventType)","data":\(data),"timestamp":"t"}
        """.utf8))
    }

    /// ⚠️ NEVER EMPTY WITH `lastSeq: 0`: the server holds a subscribe until the call's first
    /// line exists, and answers with a snapshot that has it (contract §4.12 Q4).
    private func snapshot(_ callId: String) -> TelemetryEnvelope? {
        envelope("transcript_snapshot", callId: callId, data: """
        {"v":1,"callId":"\(callId)","live":true,"complete":true,"epoch":1,"lastSeq":1,"segments":[\
        {"segmentId":"item_a1","index":0,"epoch":1,"seq":1,"rev":0,"speaker":"agent","speakerName":"Ava",\
        "text":"Good afternoon","final":true,"interrupted":false,"language":"en","startedAt":"t","endedAt":"t"}],\
        "part":0,"more":false}
        """)
    }

    // MARK: - DesktopLive: when the socket runs

    /// ⛔ RING OFF, CALL WATCHED: the socket runs for the transcript and does not ring, and it
    /// stops when the last screen stops watching.
    func test_MAC_TRANSCRIPT_01_watchingWithRingingOffRunsASessionThatDoesNotRing() async {
        let live = makeLive(ringHere: false)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()
        XCTAssertTrue(sessions.isEmpty)

        let watch = live.watchTranscript(callId: "call_1", subscribed: true) { _ in }
        await live.settled()
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(running.first?.rings, false, "no presence, no gate")
        XCTAssertEqual(running.first?.startedWith, ["call_1"])
        XCTAssertEqual(live.status, .off, "the line under the setting is about ringing")

        live.stopWatchingTranscript(watch)
        await live.settled()
        XCTAssertTrue(running.isEmpty, "the last watcher gone, nothing keeps the socket")
    }

    /// ⛔ RING ON: THE RINGING SESSION CARRIES THE TRANSCRIPT, with no second socket and no
    /// restart: one subscription per call however many screens watch it, one unsubscribe
    /// when the last stops. ⚠️ A second screen sends the subscribe again, since the server
    /// answers a duplicate with the fresh snapshot that screen needs (§4.12 Q5).
    func test_MAC_TRANSCRIPT_02_aRingingSessionCarriesTheTranscriptWithoutRestarting() async {
        let live = makeLive(ringHere: true)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        let first = live.watchTranscript(callId: "call_1", subscribed: true) { _ in }
        let second = live.watchTranscript(callId: "call_1", subscribed: true) { _ in }
        await live.settled()
        live.resubscribeTranscript(callId: "call_1")
        live.stopWatchingTranscript(first)
        live.stopWatchingTranscript(second)
        live.stopWatchingTranscript(second)
        await live.settled()

        XCTAssertEqual(sessions.count, 1, "the ringing session is never restarted for a transcript")
        XCTAssertEqual(sessions.first?.rings, true)
        XCTAssertEqual(sessions.first?.ops, ["+call_1", "~call_1", "~call_1", "-call_1"])
        XCTAssertEqual(running.count, 1, "and it keeps ringing after")
    }

    /// Switching the setting while a call is watched restarts the session with the other
    /// role, the watched call carried over; the screen hears of the gap.
    func test_MAC_TRANSCRIPT_03_switchingRingingWhileWatchingRestartsWithTheCall() async {
        let live = makeLive(ringHere: true)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        var heard: [TranscriptFeed] = []
        _ = live.watchTranscript(callId: "call_1", subscribed: true) { heard.append($0) }
        await live.settled()

        live.setRingHere(false)
        await live.settled()

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertEqual(running.first?.rings, false)
        XCTAssertEqual(running.first?.startedWith, ["call_1"])
        XCTAssertTrue(heard.contains(.disconnected))
    }

    /// Sleep stops the socket; wake starts it again with the watched call.
    func test_MAC_TRANSCRIPT_04_wakeStartsTheSessionAgainWithTheWatchedCall() async {
        let live = makeLive(ringHere: false)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        _ = live.watchTranscript(callId: "call_1", subscribed: true) { _ in }
        await live.settled()

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await live.settled()
        XCTAssertTrue(running.isEmpty)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await live.settled()

        XCTAssertEqual(running.first?.startedWith, ["call_1"])
    }

    // MARK: - DesktopLive: routing

    /// ⛔ A FRAME REACHES THE SCREEN WATCHING ITS CALL AND NO OTHER; the socket's state
    /// reaches every screen; a ring reaches none.
    func test_MAC_TRANSCRIPT_05_framesReachOnlyTheScreenWatchingTheirCall() async throws {
        let live = makeLive(ringHere: true)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        var one: [TranscriptFeed] = []
        var two: [TranscriptFeed] = []
        _ = live.watchTranscript(callId: "call_1", subscribed: true) { one.append($0) }
        _ = live.watchTranscript(callId: "call_2", subscribed: true) { two.append($0) }
        await live.settled()
        let session = try XCTUnwrap(running.first)

        session.onTranscript(.connected)
        try session.onTranscript(.event(XCTUnwrap(snapshot("call_1"))))
        try session.onTranscript(.event(XCTUnwrap(envelope(
            "call_ended",
            callId: "call_2",
            data: #"{"status":"completed"}"#
        ))))
        try session.onTranscript(.event(XCTUnwrap(envelope(
            "call_ringing",
            data: #"{"callId":"call_1","userIds":[]}"#
        ))))
        try session.onTranscript(.event(XCTUnwrap(envelope(
            "transcript_error",
            callId: "",
            data: #"{"v":1,"callId":null,"op":"socket.mode","code":"bad_request","retryAfterMs":null}"#
        ))))
        session.onTranscript(.discarded)
        session.onTranscript(.reconnecting(delayMilliseconds: 0, cause: .renewal))
        session.onTranscript(.ended(.forbidden(reason: "Access denied to workspace")))

        XCTAssertEqual(one.count, 4)
        XCTAssertEqual(one.first, .connected)
        guard case .event(.snapshot) = one[1] else { return XCTFail("call_1's snapshot, got \(one[1])") }
        XCTAssertEqual(Array(one.suffix(2)), [.disconnected, .failed])
        XCTAssertEqual(two, [.connected, .callEnded, .disconnected, .failed])
    }

    // MARK: - The session's socket

    /// ⛔ ON THE MAC'S OWN SOCKET: the subscribe and nothing else (no `socket.mode`: the ring
    /// needs the relay), the frames handed on, and a ring still rings.
    func test_MAC_TRANSCRIPT_06_theSessionSubscribesWithoutSocketModeAndStillRings() async {
        let rig = SessionRig()
        var heard: [TelemetryUpdate] = []
        let session = rig.start(rings: true, watched: ["call_1"]) { heard.append($0) }
        await waitUntil(state: "sent=\(rig.tasks.first?.sent ?? [])") { rig.tasks.first?.sent.count == 1 }

        XCTAssertEqual(rig.tasks.first?.sent, [#"{"op":"transcript.subscribe","v":1,"callId":"call_1"}"#])
        rig.tasks.first?.push(.success(.string(LiveFixtures.ringing())))
        await waitUntil { rig.ring.started == 1 }
        await waitUntil { heard.contains {
            if case .event = $0 {
                true
            } else {
                false
            }
        } }
        await session.stop()
    }

    /// ⛔ A SUBSCRIPTION IS PER SOCKET: the socket that replaces the old one before its
    /// credential expires is subscribed again.
    func test_MAC_TRANSCRIPT_07_theRenewalsSocketIsSubscribedAgain() async {
        let rig = SessionRig()
        let session = rig.start(rings: false, watched: ["call_1"]) { _ in }
        await waitUntil { rig.tasks.first?.sent.count == 1 }

        var moved: Int64 = 0
        while rig.tasks.count < 2 || rig.tasks[1].sent.isEmpty, moved < 15 * 60 * 1000 {
            rig.clock.advance(by: 10000)
            moved += 10000
            try? await Task.sleep(for: .milliseconds(5))
        }

        await waitUntil { rig.tasks.count == 2 && rig.tasks[1].sent.count == 1 }
        XCTAssertEqual(rig.tasks[1].sent, [#"{"op":"transcript.subscribe","v":1,"callId":"call_1"}"#])
        XCTAssertEqual(rig.presence.registers, [], "a session that does not ring registers no presence")
        await session.stop()
    }

    // MARK: - The model

    /// The screen's model over a fake channel: it watches while shown, turns frames into
    /// lines, asks the channel to re-subscribe after a gap, fetches the full transcript at
    /// the end and then stops watching.
    func test_MAC_TRANSCRIPT_08_theModelWatchesRendersAndLetsGoAtTheEnd() async throws {
        let channel = FakeChannel()
        let clock = ManualLiveClock()
        let model = LiveTranscriptModel(callId: "call_1", channel: channel, clock: clock) { .success("Ava: Hello") }

        model.activate()
        model.activate()
        XCTAssertEqual(channel.watching, ["call_1"], "one watch however often it is activated")
        XCTAssertEqual(channel.subscribed, ["call_1"])
        model.handle(.connected)
        try model.handle(.event(XCTUnwrap(snapshot("call_1")?.transcriptEvent)))
        XCTAssertEqual(model.phase, .live)
        XCTAssertEqual(model.connection, .open)

        let skipped = try XCTUnwrap(envelope("transcript_segment", data: """
        {"v":1,"callId":"call_1","segment":{"segmentId":"s3","index":2,"epoch":1,"seq":3,"rev":0,"speaker":"caller",\
        "speakerName":null,"text":"Thursday","final":true,"interrupted":false,"language":"en",\
        "startedAt":"t","endedAt":"t"}}
        """)?.transcriptEvent)
        model.handle(.event(skipped))
        XCTAssertEqual(model.lines.count, 2)
        var moved: Int64 = 0
        while channel.resubscribes.isEmpty, moved < 5000 {
            clock.advance(by: 250)
            moved += 250
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(channel.resubscribes, ["call_1"], "a gap still open after two seconds asks again")

        model.handle(.callEnded)
        XCTAssertEqual(model.phase, .ended(.callEnded))
        moved = 0
        while model.finalTranscript != .loaded("Ava: Hello"), moved < 5000 {
            clock.advance(by: 250)
            moved += 250
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.finalTranscript, .loaded("Ava: Hello"))
        XCTAssertEqual(channel.watching, [], "the full transcript in, the call is no longer watched")

        model.handle(.failed)
        XCTAssertTrue(model.fallsBack)
    }
}

/// A recording ``TranscriptChannel``.
@MainActor
final class FakeChannel: TranscriptChannel {
    private var watches: [UUID: (callId: String, subscribed: Bool)] = [:]
    private(set) var resubscribes: [String] = []

    var watching: [String] {
        watches.values.map(\.callId)
    }

    var subscribed: [String] {
        watches.values.filter(\.subscribed).map(\.callId)
    }

    func watchTranscript(
        callId: String,
        subscribed: Bool,
        onUpdate _: @escaping @MainActor (TranscriptFeed) -> Void
    ) -> UUID {
        let id = UUID()
        watches[id] = (callId, subscribed)
        return id
    }

    func stopWatchingTranscript(_ id: UUID) {
        watches[id] = nil
    }

    func setTranscriptSubscribed(_ id: UUID, _ subscribed: Bool) {
        watches[id]?.subscribed = subscribed
    }

    func resubscribeTranscript(callId: String) {
        resubscribes.append(callId)
    }
}

/// A ``DesktopLiveSession`` over the real adapter, a fake task per socket and a manual clock.
@MainActor
private final class SessionRig {
    final class Minter: TelemetryTokenMinter, @unchecked Sendable {
        let clock: ManualLiveClock

        init(clock: ManualLiveClock) {
            self.clock = clock
        }

        func mintTelemetryToken(workspaceId _: String) async -> Result<TelemetryTokenResponse, ApiError> {
            .success(TelemetryTokenResponse(
                success: true,
                token: "a.b.c",
                expiresAt: clock.nowMilliseconds() + 15 * 60 * 1000,
                wsUrl: "wss://telemetry.example.test/ws/telemetry"
            ))
        }
    }

    final class Presence: PresenceAPI, @unchecked Sendable {
        private let lock = NSLock()
        private var registered: [String] = []

        var registers: [String] {
            lock.withLock { registered }
        }

        func registerPresence(token: String) async -> Result<Void, ApiError> {
            lock.withLock { registered.append(token) }
            return .success(())
        }

        func unregisterPresence() async -> Result<Void, ApiError> {
            .success(())
        }
    }

    final class Ring: DesktopRingSink {
        private(set) var started = 0

        func ringStarted(workspaceId _: String, callId _: String, workspaceName _: String?) {
            started += 1
        }

        func ringStopped(workspaceId _: String, callId _: String, reason _: DesktopRingEnd) {}

        func ringWithdrawn(callId _: String) {}
    }

    final class Tasks: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [FakeWebSocketTask] = []

        var list: [FakeWebSocketTask] {
            lock.withLock { all }
        }

        func make() -> FakeWebSocketTask {
            let task = FakeWebSocketTask()
            lock.withLock { all.append(task) }
            return task
        }
    }

    let clock = ManualLiveClock()
    let presence = Presence()
    let ring = Ring()
    private let opened = Tasks()

    var tasks: [FakeWebSocketTask] {
        opened.list
    }

    func start(
        rings: Bool,
        watched: Set<String>,
        onTranscript: @escaping @MainActor (TelemetryUpdate) -> Void
    ) -> DesktopLiveSession {
        let opened = opened
        let transport = URLSessionTelemetryTransport(clock: clock) { _, _ in
            OpenedWebSocket(
                task: opened.make(),
                selectedSubprotocol: TelemetryProtocol.subprotocol,
                delegate: nil,
                onClose: {}
            )
        }
        let session = DesktopLiveSession(
            workspaceId: LiveFixtures.workspaceId,
            workspaceName: nil,
            userId: LiveFixtures.userId,
            minter: Minter(clock: clock),
            presenceAPI: presence,
            installToken: "install-nonce-1",
            transport: transport,
            clock: clock,
            ring: ring,
            rings: rings,
            transcriptCallIds: watched,
            onTranscript: onTranscript
        ) { _ in }
        session.start()
        return session
    }
}
