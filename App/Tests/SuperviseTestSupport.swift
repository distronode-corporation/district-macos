import DistrictCall
import DistrictLive
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import Foundation

/// This Mac as a supervision sees it, recording every step in order.
///
/// ⚠️ ONE LOG FOR THE CLAIM AND THE ENGINES TOGETHER, because the order across them is the
/// contract: the claim before the seat, the listen room left before the coach room is joined.
@MainActor
final class FakeSuperviseMedia: SuperviseMedia {
    var hasLiveCall = false
    var hasLiveRoom = false
    /// What a second claim answers: another call holding this Mac's slot.
    var refusesClaim = false
    let fakeMicrophone: FakeMicrophoneAccess
    private(set) var log: [String] = []
    private(set) var isClaimed = false
    /// Every engine built, in order: a test can speak as one the session has already left.
    private(set) var engines: [(leg: SuperviseLeg, events: AsyncStream<CallEngineEvent>.Continuation)] = []

    init(microphone: FakeMicrophoneAccess = FakeMicrophoneAccess(status: .granted)) {
        fakeMicrophone = microphone
    }

    var microphone: any MicrophoneAccess {
        fakeMicrophone
    }

    func claim(_: SuperviseModel) -> Bool {
        guard !refusesClaim else { return false }
        log.append("claim")
        isClaimed = true
        return true
    }

    func release(_: SuperviseModel) {
        log.append("release")
        isClaimed = false
    }

    /// When set, building a leg's engine waits here (an end during the room swap).
    var holdsBeginLeg = false
    private var heldBeginLeg: CheckedContinuation<Void, Never>?

    var isHoldingBeginLeg: Bool {
        heldBeginLeg != nil
    }

    func releaseBeginLeg() {
        let held = heldBeginLeg
        heldBeginLeg = nil
        held?.resume()
    }

    func beginLeg(_ leg: SuperviseLeg) async -> AsyncStream<CallEngineEvent> {
        log.append("beginLeg \(leg)")
        if holdsBeginLeg {
            await withCheckedContinuation { heldBeginLeg = $0 }
        }
        let (stream, continuation) = AsyncStream<CallEngineEvent>.makeStream()
        engines.append((leg, continuation))
        return stream
    }

    /// When set, a connect waits here until the test lets it go (a join still in flight).
    var holdsConnect = false
    private var heldConnect: CheckedContinuation<Void, Never>?

    var isHoldingConnect: Bool {
        heldConnect != nil
    }

    func releaseConnect() {
        let held = heldConnect
        heldConnect = nil
        held?.resume()
    }

    func perform(_ command: CallCommand) async {
        switch command {
        case let .connect(url, token):
            log.append("connect \(url) \(token)")
            if holdsConnect {
                await withCheckedContinuation { heldConnect = $0 }
            }
        case .disconnect: log.append("disconnect")
        case let .setMuted(muted): log.append("setMuted \(muted)")
        case let .setSpeakerphone(enabled): log.append("speaker \(enabled)")
        }
    }

    func endLeg() {
        log.append("endLeg")
    }

    /// The newest engine for `leg` reports something.
    func engine(_ leg: SuperviseLeg, _ event: CallEngineEvent) {
        engines.last { $0.leg == leg }?.events.yield(event)
    }

    /// The `index`th engine built reports something, current or not.
    func engine(at index: Int, _ event: CallEngineEvent) {
        engines[index].events.yield(event)
    }

    func clearLog() {
        log = []
    }
}

/// The three routes, answered as the test says, with what each was asked.
final class FakeSuperviseServer: SuperviseServing, @unchecked Sendable {
    private let lock = NSLock()
    private var monitorResults: [Result<CallMonitorResponse, ApiError>] = []
    private var takeoverResults: [Result<CallTakeoverResponse, ApiError>] = []
    private var whisperResults: [Result<Void, ApiError>] = []
    private var detailResult: Result<CallSummary, ApiError> = .failure(.transport("unscripted"))
    private var asked: [String] = []
    private var whisperGate: CheckedContinuation<Void, Never>?
    private var monitorGate: CheckedContinuation<Void, Never>?
    /// When set, a whisper waits here until the test resumes it.
    var holdsWhispers = false
    /// When set, the next monitor answer waits here (an answer for an abandoned Listen).
    var holdsMonitor = false

    var requests: [String] {
        lock.withLock { asked }
    }

    var isHoldingWhisper: Bool {
        lock.withLock { whisperGate != nil }
    }

    var isHoldingMonitor: Bool {
        lock.withLock { monitorGate != nil }
    }

    func answerMonitor(_ result: Result<CallMonitorResponse, ApiError>) {
        lock.withLock { monitorResults.append(result) }
    }

    func answerTakeover(_ result: Result<CallTakeoverResponse, ApiError>) {
        lock.withLock { takeoverResults.append(result) }
    }

    func answerWhisper(_ result: Result<Void, ApiError>) {
        lock.withLock { whisperResults.append(result) }
    }

    func answerDetail(_ result: Result<CallSummary, ApiError>) {
        lock.withLock { detailResult = result }
    }

    func releaseWhisper() {
        let gate: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { whisperGate = nil }
            return whisperGate
        }
        gate?.resume()
    }

    func releaseMonitor() {
        let gate: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { monitorGate = nil }
            return monitorGate
        }
        gate?.resume()
    }

    func monitor(callId: SupervisedCallID, platform: ClientPlatform) async -> Result<CallMonitorResponse, ApiError> {
        let result: Result<CallMonitorResponse, ApiError> = lock.withLock {
            asked.append("monitor \(callId.value) \(platform.rawValue)")
            return monitorResults.isEmpty ? .failure(.transport("unscripted")) : monitorResults.removeFirst()
        }
        if lock.withLock({ holdsMonitor }) {
            lock.withLock { holdsMonitor = false }
            await withCheckedContinuation { continuation in
                lock.withLock { monitorGate = continuation }
            }
        }
        return result
    }

    func takeOver(workspaceId: String, callId: String) async -> Result<CallTakeoverResponse, ApiError> {
        lock.withLock {
            asked.append("takeOver \(workspaceId) \(callId)")
            return takeoverResults.isEmpty ? .failure(.transport("unscripted")) : takeoverResults.removeFirst()
        }
    }

    func detail(workspaceId: String, callId: String) async -> Result<CallSummary, ApiError> {
        lock.withLock {
            asked.append("detail \(workspaceId) \(callId)")
            return detailResult
        }
    }

    func whisper(workspaceId _: String, callId _: String, text: String) async -> Result<Void, ApiError> {
        lock.withLock { asked.append("whisper \(text)") }
        if holdsWhispers {
            await withCheckedContinuation { continuation in
                lock.withLock { whisperGate = continuation }
            }
        }
        return lock.withLock {
            whisperResults.isEmpty ? .success(()) : whisperResults.removeFirst()
        }
    }
}

/// The Mac's socket, as a supervision's transcript sees it: it records the watches and
/// delivers nothing unless a test says so.
@MainActor
final class SuperviseTranscriptChannel: TranscriptChannel {
    private(set) var watches: [UUID: String] = [:]

    func watchTranscript(
        callId: String,
        subscribed _: Bool,
        onUpdate _: @escaping @MainActor (TranscriptFeed) -> Void
    ) -> UUID {
        let id = UUID()
        watches[id] = callId
        return id
    }

    func stopWatchingTranscript(_ id: UUID) {
        watches[id] = nil
    }

    func setTranscriptSubscribed(_: UUID, _: Bool) {}

    func resubscribeTranscript(callId _: String) {}
}

/// A minter and a transport for a feed no test opens: either answering means a socket was opened.
private struct UnusedMinter: TelemetryTokenMinter {
    func mintTelemetryToken(workspaceId _: String) async -> Result<TelemetryTokenResponse, ApiError> {
        .failure(.transport("no socket in this test"))
    }
}

private struct UnusedTransport: TelemetrySocketTransport {
    func connect(to _: URL, subprotocols _: [String]) async throws -> any TelemetrySocket {
        throw URLError(.notConnectedToInternet)
    }
}

enum SuperviseFixtures {
    static let workspaceId = "ws_1"
    /// ⚠️ cuid-shaped: a `Call.id` carries no `_` (``SupervisedCallID``).
    static let callId = "cmh1live0001"

    static let listenSeat = CallMonitorResponse(success: true, token: "listen.jwt", url: "wss://sfu.example.test")
    static let coachSeat = CallTakeoverResponse(
        success: true,
        url: "wss://sfu.example.test",
        token: "coach.jwt",
        roomName: "inbound_ws_1_cmh1live0001"
    )

    /// A call-log row, as the feed and the detail route answer it. `receptionistOnCall` nil
    /// leaves the key out, as a server before live supervise does.
    static func call(
        id: String = callId,
        receptionistOnCall: Bool? = true,
        status: String = "in-progress",
        createdAt: String = "2026-11-05T18:00:00.000Z"
    ) throws -> CallSummary {
        let receptionist = receptionistOnCall.map { #","receptionistOnCall":\#($0)"# } ?? ""
        let json = """
        {"id":"\(id)","type":"inbound","number":"Marie Tremblay","status":"\(status)","duration":"1m 5s",\
        "time":"t","aiSummary":"","transcript":"","callerName":"","summary":"",\
        "from":"+15555550100","direction":"inbound","durationRaw":65,\
        "createdAt":"\(createdAt)"\(receptionist)}
        """
        return try JSONDecoder().decode(CallSummary.self, from: Data(json.utf8))
    }

    /// A telemetry event for the call, as the broadcaster relays it.
    static func envelope(_ type: TelemetryEventType, _ data: WireJSON, callId: String = callId) -> TelemetryEnvelope {
        TelemetryEnvelope(
            workspaceId: workspaceId,
            callId: callId,
            eventType: type,
            data: data,
            timestamp: "2026-11-05T18:00:00.000Z"
        )
    }

    /// Feed dependencies that are never activated by these tests: no socket is opened.
    static func feedDependencies() -> LiveEventFeed.Dependencies {
        LiveEventFeed.Dependencies(
            minter: UnusedMinter(),
            transport: UnusedTransport(),
            clock: ManualLiveClock(),
            jitter: { 0 }
        )
    }

    @MainActor
    static func model(
        call: CallSummary,
        role: WorkspaceRole? = .agency,
        server: FakeSuperviseServer,
        media: FakeSuperviseMedia
    ) -> SuperviseModel {
        SuperviseModel(
            call: call,
            workspaceId: workspaceId,
            role: role,
            server: server,
            media: media,
            transcript: LiveTranscriptModel(callId: call.id, channel: SuperviseTranscriptChannel()) {
                .success("")
            },
            events: LiveEventFeed(workspaceId: workspaceId, dependencies: feedDependencies())
        )
    }
}
