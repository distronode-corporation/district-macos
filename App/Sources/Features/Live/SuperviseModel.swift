import DistrictCall
import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import Observation

/// The three supervise routes, behind a seam so a test can stand in for the server.
///
/// ⚠️ THE CORE'S `CallsRepository` IS THE ONE CONFORMANCE (district-core-swift 8.2.0): the app
/// never builds a request by hand, and the core's `EndpointID` table is the one list of what
/// it calls. None of the three is ever retried, there or here.
protocol SuperviseServing: Sendable {
    func monitor(callId: SupervisedCallID, platform: ClientPlatform) async -> Result<CallMonitorResponse, ApiError>
    func takeOver(workspaceId: String, callId: String) async -> Result<CallTakeoverResponse, ApiError>
    func whisper(workspaceId: String, callId: String, text: String) async -> Result<Void, ApiError>
    func detail(workspaceId: String, callId: String) async -> Result<CallSummary, ApiError>
}

extension CallsRepository: SuperviseServing {}

/// One person supervising one live call: listen in, a note to the receptionist, take over,
/// hand back. Ported from district-ios #101 (`SuperviseModel.swift`), without CallKit.
///
/// ⛔ IT DECIDES NOTHING ABOUT THE CALL. `SuperviseSession` (district-core-swift, `DistrictCall`)
/// is the state machine, tested on Linux: the takeover is asked for while still listening, a
/// refusal leaves the person listening, a grant leaves the listen room before the coach room is
/// joined. This model feeds it events and performs its commands IN ORDER, through
/// ``SuperviseServing`` and ``SuperviseMedia``.
///
/// ⛔ THE SUPERVISION OUTLIVES THE SCREEN, FOR THE DIALLER'S REASON. Listen takes the Mac's call
/// claim (``CallStack/claimCall(_:)``), which holds this object strongly, and ``release()`` drops
/// it on every terminal path. A Live screen left mid-call leaves the person listening, a screen
/// rebuilt around the call finds this model again through ``CallStack/supervisor``, and sleep,
/// quit and sign-out end it through ``endForSystem()``.
///
/// ⛔ A COLLEAGUE'S OWN SOFTPHONE CALL OFFERS LISTEN ONLY (Sean, 2026-11-05): the session is
/// built from the row's `receptionistOnCall`, so `mayWhisper` and `mayTakeOver` are false there.
/// The routes' 409 `call_has_no_receptionist` stays the fallback.
@MainActor
@Observable
final class SuperviseModel {
    let workspaceId: String
    let callId: String

    /// The call as the Live list read it when the screen opened.
    let call: CallSummary

    /// Where the supervision stands. ⛔ The only writer is ``apply(_:)``.
    private(set) var session: SuperviseSession

    /// Why Listen or Take over did nothing before the session moved (another call, a room, a
    /// microphone this app may not use). ⚠️ Cleared by the next press.
    private(set) var startRefusal: String?

    /// The note being written. ⚠️ Kept through a failed send, cleared by a delivered one.
    var draft = ""
    /// True while a note is on its way. ⛔ One at a time (single-flight).
    private(set) var sending = false
    /// Why the last note did not go, or nil.
    private(set) var whisperProblem: String?

    /// The call's live transcript, the call screen's own model.
    let transcript: LiveTranscriptModel
    /// The workspace's call events: the call ending, and the receipt for a note.
    let events: LiveEventFeed

    // ⚠️ MODULE-VISIBLE FOR `SuperviseModel+Steps.swift`, WHICH IS SPLIT OUT FOR
    // `type_body_length` AND NOTHING ELSE. Swift's `private` is file-scoped.
    let server: any SuperviseServing
    let media: any SuperviseMedia
    var claimed = false
    var engineLeg: SuperviseLeg?
    var legTask: Task<Void, Never>?
    /// Bumped by every Listen press. ⛔ An answer for an attempt the person abandoned (Stop, then
    /// Listen again) is dropped by comparing it (district-ios #101, max review item 7).
    var attempt = 0

    init(
        call: CallSummary,
        workspaceId: String,
        role: WorkspaceRole?,
        server: any SuperviseServing,
        media: any SuperviseMedia,
        transcript: LiveTranscriptModel,
        events: LiveEventFeed
    ) {
        self.call = call
        callId = call.id
        self.workspaceId = workspaceId
        var session = SuperviseSession(call: call, role: role)
        // ⛔ A ROW THAT HAS ALREADY ENDED OPENS ON "The call has ended." (district-ios #101, xhigh
        // review item 3), never on Listen and a note box for a call that is over.
        if CallWire.hasEnded(call.status) {
            session.handle(.callEnded)
        }
        self.session = session
        self.server = server
        self.media = media
        self.transcript = transcript
        self.events = events
        events.onEvent = { [weak self] in self?.received($0) }
        // ⚠️ EVERY OPEN, THE FIRST INCLUDED: the server replays no call events, so whatever ended
        // the call while no socket was open is only in the call's row.
        events.onOpen = { [weak self] in
            Task { await self?.refresh() }
        }
    }

    /// Read the call's row again, and end the supervision if the call is over.
    func refresh() async {
        guard case let .success(row) = await server.detail(workspaceId: workspaceId, callId: callId),
              CallWire.hasEnded(row.status)
        else { return }
        await apply(.callEnded)
        transcript.callEnded()
    }

    var state: SuperviseState {
        session.state
    }

    /// Whether Listen may be pressed now.
    var mayListen: Bool {
        state.mayListen && !claimed
    }

    // MARK: - Listen, stop, take over, hand back

    /// The person pressed Listen.
    ///
    /// ⛔ ONE CALL ON THIS MAC: refused, with a sentence, while a phone call or a meeting room
    /// holds it, as a dial is.
    func listen() async {
        guard mayListen else { return }
        startRefusal = nil
        if media.hasLiveRoom {
            startRefusal = SuperviseCopy.busyInRoom
            return
        }
        guard !media.hasLiveCall, media.claim(self) else {
            startRefusal = SuperviseCopy.busyWithCall
            return
        }
        claimed = true
        attempt += 1
        await apply(.listenPressed)
    }

    /// Stop listening, or Hand back: both are leaving the room.
    func stop() async {
        guard claimed else { return }
        await apply(.stopPressed)
    }

    /// The person confirmed Take over.
    ///
    /// ⛔ THE MICROPHONE IS ASKED BEFORE THE SERVER, as the dialler asks it before the carrier.
    /// A refusal here leaves the person listening and asks the server nothing: a coach seat
    /// whose microphone cannot start would only put the assistant on hold for silence.
    func takeOver() async {
        guard state.mayTakeOver else { return }
        guard await media.microphone.request() else {
            whisperProblem = nil
            startRefusal = SuperviseCopy.takeOverJoinFailed
            return
        }
        startRefusal = nil
        await apply(.takeOverPressed)
    }

    /// The mute control, offered once the call is taken over.
    func toggleMute() async {
        guard state.phase == .takenOver else { return }
        await apply(.muteToggled)
    }

    // MARK: - The note

    /// Send the note.
    ///
    /// ⛔ NEVER RETRIED (the route publishes before it answers, so a lost answer may follow a
    /// note already acted on), and ONE AT A TIME: a second press while one is on its way is
    /// dropped rather than queued.
    func sendWhisper() async {
        guard state.mayWhisper, !sending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.utf16.count <= SuperviseCopy.whisperLimit else {
            whisperProblem = SuperviseCopy.whisperTooLong(SuperviseCopy.whisperLimit)
            return
        }
        sending = true
        whisperProblem = nil
        // ⛔ THE PREVIOUS RECEIPT GOES BEFORE THE SEND, NOT AFTER ITS ANSWER (district-ios #101,
        // xhigh review item 6): the agent can answer this note before the route's 200 arrives,
        // and clearing then would wipe this note's own receipt. The website clears first too.
        await apply(.whisperSent)
        let result = await server.whisper(workspaceId: workspaceId, callId: callId, text: text)
        sending = false
        switch result {
        case .success:
            draft = ""
        case let .failure(error):
            whisperProblem = SuperviseCopy.refusal(error, fallback: SuperviseCopy.whisperFailed)
        }
    }

    // MARK: - What the socket says

    private func received(_ envelope: TelemetryEnvelope) {
        guard envelope.callId == callId else { return }
        if let receipt = envelope.whisperReceipt {
            Task { await apply(.whisperReceipt(receipt)) }
            return
        }
        let over = envelope.callStatus.map(CallWire.hasEnded) == true
        let ended = envelope.eventType == .callEnded || (envelope.eventType == .callUpdated && over)
        guard ended else { return }
        Task {
            await apply(.callEnded)
            transcript.callEnded()
        }
    }

    // MARK: - The one sink

    /// Apply one event, perform what it asked for, then settle.
    ///
    /// ⛔ EVERY EVENT GOES THROUGH HERE, WHICH IS WHAT MAKES ``release()`` TOTAL. The commands
    /// are performed IN ORDER and one after another, because the order is part of
    /// `SuperviseCommand`'s contract: the listen room is left before the coach room is joined.
    func apply(_ event: SuperviseEvent) async {
        var next = session
        let commands = next.handle(event)
        // ⚠️ WRITTEN BACK BEFORE THE AWAITS, so an event that interleaves reads the new state.
        session = next
        for command in commands {
            await perform(command)
        }
        await settle()
        // ⛔ A DROP IS CHECKED AGAINST THE CALL'S ROW (district-ios #101, max review item 3): a
        // room that was deleted because the call ended ends as "The call has ended.", not as a
        // drop.
        if case .some(.listenDropped) = state.problem, event.isEngine {
            Task { await refresh() }
        } else if case .some(.takeoverDropped) = state.problem, event.isEngine {
            Task { await refresh() }
        }
    }

    /// ⛔ THE ONE EXIT, AND IT DROPS THE CLAIM LAST: the claim is this object's only strong
    /// reference while no screen shows it. ⚠️ Safe to call with nothing claimed.
    func release() async {
        legTask?.cancel()
        legTask = nil
        engineLeg = nil
        guard claimed else { return }
        claimed = false
        media.endLeg()
        media.release(self)
    }
}

extension SuperviseModel: SupervisionEnding, LiveCallOwner {
    func endSupervision() async {
        await stop()
    }

    /// The Mac is sleeping or quitting, or the person signed out. ⚠️ Leaving the room, as Stop
    /// listening and Hand back do: nothing on the call is the supervisor's to hang up.
    func endForSystem() async {
        await stop()
    }
}

private extension SuperviseEvent {
    var isEngine: Bool {
        if case .engine = self {
            return true
        }
        return false
    }
}
