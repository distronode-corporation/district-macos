import DistrictCall
import DistrictData
import DistrictLive
import DistrictModel
import Foundation
import Observation

/// One inbound call, from the ring to the hang-up.
///
/// Ported from district-ios `Features/Incoming/IncomingCallModel.swift` (see PORTING.md).
/// iOS is rung by a VoIP push and draws the ring with CallKit; this Mac is rung by the
/// telemetry socket (`DistrictLive.DesktopRingGate`, through ``DesktopLive``) and draws
/// the ring itself (``RingPresenter`` and the ring panel). Everything between the ring and
/// the hang-up is the iOS model's.
///
/// ⛔ ONE PER PROCESS, BUILT IN `DistrictMacApp` BESIDE THE ONE ``AppContainer``, AND IT
/// MUST OUTLIVE EVERY VIEW. A ring can arrive while any section is on screen, and the
/// call it becomes outlives the window that showed the ring. The outbound dialler gets
/// the same lifetime from the call claim (``CallStack/claimCall(_:)``), and the two can
/// never hold it at once, which is what the guard in ``ringing(workspace:call:)``
/// enforces.
///
/// ⛔ THE REDUCER IS ``IncomingCallController`` AND EVERY DECISION LIVES THERE, ON THE
/// LINUX-TESTED TIER. This class is the things that cannot: the clock, the network round
/// trip, the ring the person sees and hears, and the engine.
///
/// ⛔ EVERY ANSWER PATH CONVERGES ON ``IncomingCallEvent/answerPressed``, WHICH IS WHAT
/// MAKES "ONE ANSWER PER CALL" TRUE. The ring panel's button and the notification's
/// Answer feed the SAME event, and the reducer drops a second one because
/// ``IncomingCallPhase/answering`` absorbs it. Two entry points writing the server's
/// rendezvous twice would tell the agent a human took the call twice.
@MainActor
@Observable
final class IncomingCallModel: LiveCallControls, LiveCallOwner, DesktopRingSink {
    /// ⚠️ MIRRORED OUT OF THE REDUCER RATHER THAN COMPUTED FROM IT, so the observation
    /// dependency is a stored property this class writes.
    private(set) var state = IncomingCallState()

    private(set) var session: IncomingCallSession = .unknown

    /// Who is calling, once the workspace's records answered. See ``IncomingCallIdentity``.
    private(set) var caller: IncomingCallIdentity?

    /// The name of the workspace being called, when the shell had one for it.
    private(set) var workspaceName: String?

    /// Whether the ring ended because the CALL ended (the caller hung up, or the
    /// receptionist finished with them) rather than because nobody answered.
    ///
    /// ⚠️ MAC ONLY. iOS never learns that a ringing call ended: CallKit rings on until the
    /// timeout. The telemetry socket says so (`call_ended`, or a `call_updated` the answer
    /// route would refuse), and the reducer has no event for it while ringing, so the ring
    /// ends through ``IncomingCallEvent/ringTimedOut`` (the same exit, which sends nothing
    /// to the server) and this bit words it as "the caller hung up".
    private(set) var ringEndedByCall = false

    /// The workspace being called, for a screen that wants to name it.
    var workspaceId: String? {
        state.workspaceID?.rawValue
    }

    /// The call ringing or live, for the notification handler to compare against.
    var callId: String? {
        state.callID?.rawValue
    }

    /// Whether anything should be on screen. ⚠️ True from the ring all the way through
    /// the ended-call summary, which the user dismisses.
    var isPresented: Bool {
        state.phase != .idle
    }

    /// Whether a ring is sounding now.
    var isRinging: Bool {
        state.phase == .ringing
    }

    /// Called when this model is done with a ring the gate started (answered, declined,
    /// timed out or ended), so the gate can take the next one. Set by ``DesktopLive``.
    var onRingSettled: (() -> Void)?

    // ⚠️ MODULE-VISIBLE RATHER THAN `private`, BECAUSE THE BACKGROUND TASKS THAT DRIVE
    // THEM LIVE IN `IncomingCallTasks.swift` AND SWIFT'S `private` IS FILE-SCOPED (the
    // iOS model's trade, for the same `file_length` reason). ⛔ `state` did NOT widen.
    let calls: CallStack
    let presenter: any RingPresenting
    private let inbound: InboundCallRepository
    /// ⚠️ The call LOG, not ``calls``, which is the live call.
    private let callLog: CallsRepository

    private var controller = IncomingCallController()

    /// The ring this model owns, or nil. ⚠️ The Mac's stand-in for the CallKit UUID: a
    /// fresh value per ring, so a late timer or lookup for an earlier ring changes nothing.
    var ringID: UUID?

    /// True while ``CallStack/callOwner`` is this model.
    private var claimed = false

    private var answerTask: Task<Void, Never>?
    var engineTask: Task<Void, Never>?
    var tickTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?

    init(
        calls: CallStack,
        inbound: InboundCallRepository,
        callLog: CallsRepository,
        presenter: any RingPresenting
    ) {
        self.calls = calls
        self.inbound = inbound
        self.callLog = callLog
        self.presenter = presenter
    }

    convenience init(container: AppContainer, presenter: any RingPresenting) {
        self.init(
            calls: container.callStack,
            inbound: container.inboundCalls,
            callLog: container.calls,
            presenter: presenter
        )
    }

    // MARK: - What the ring gate hands over

    /// The gate says this Mac should ring for `callId`.
    func ringStarted(workspaceId: String, callId: String, workspaceName: String?) {
        ringing(workspace: WorkspaceID(workspaceId), call: CallID(callId), workspaceName: workspaceName)
    }

    /// The gate says the ring for `callId` is over.
    ///
    /// ⛔ ONLY A RING THAT IS STILL RINGING IS ENDED HERE. The gate keeps its own 30 s
    /// timer, and its `stopRinging` for a call this model has already ANSWERED would
    /// otherwise tear down a conversation thirty seconds in. ``DesktopRingEnd/cleared``
    /// is this model's own doing, echoed back, and changes nothing.
    func ringStopped(workspaceId: String, callId: String, reason: DesktopRingEnd) {
        guard state.phase == .ringing, state.callID?.rawValue == callId else { return }
        switch reason {
        case .cleared:
            return
        case .timedOut:
            ringEndedByCall = false
        case .callEnded, .noLongerAnswerable:
            ringEndedByCall = true
        }
        Task { await apply(.ringTimedOut) }
    }

    /// The live session stopped while `callId` rang (the Mac is going to sleep, the app is
    /// quitting, the setting was switched off). ⚠️ The ring is taken away with no summary:
    /// nobody declined it and nobody missed it in any sense worth a screen.
    func ringWithdrawn(callId: String) {
        guard state.phase == .ringing, state.callID?.rawValue == callId else { return }
        Task { await withdraw() }
    }

    // MARK: - What the notification hands over

    /// The notification's Answer button.
    ///
    /// ⚠️ IT CAN NAME A CALL THIS MODEL IS NOT RINGING. The APNs alert reaches a Mac whose
    /// app was closed (or whose socket missed the ring), and pressing Answer launches the
    /// app straight into this. That call is rung here first, so the reducer sees the
    /// ordinary ring-then-answer, and the server decides whether it can still be answered
    /// (a call that has ended answers "the caller hung up").
    func notificationAnswered(workspaceId: String, callId: String) {
        let alreadyRinging = state.phase == .ringing && state.callID?.rawValue == callId
        let start = alreadyRinging
            ? nil
            : ringing(workspace: WorkspaceID(workspaceId), call: CallID(callId), workspaceName: nil)
        Task {
            await start?.value
            // ⛔ ONLY THE CALL THAT IS RINGING NOW, and only while it rings: a second press,
            // or a press for a call this model refused to ring, answers nothing.
            guard state.phase == .ringing, state.callID?.rawValue == callId else { return }
            await apply(.answerPressed)
        }
    }

    /// The notification's Decline button. ⚠️ Only for the call ringing here; declining
    /// anything else has nothing to do, because a decline sends nothing to the server.
    func notificationDeclined(callId: String) {
        guard state.phase == .ringing, state.callID?.rawValue == callId else { return }
        declinePressed()
    }

    /// The session gate moved. ⛔ A ring that is waiting on ``IncomingCallSession/unknown``
    /// is resolved here, in both directions.
    func sessionChanged(_ phase: AuthPhase) {
        switch phase {
        case .checking:
            session = .unknown
        case .signedIn:
            session = .usable
        // ⚠️ `unavailable` COUNTS AS UNUSABLE. See the ⚠️ on ``IncomingCallSession``.
        case .signedOut, .unavailable:
            session = .unusable
            endForNoSession()
        }
    }

    // MARK: - What the user may do

    /// ⛔ IT FEEDS THE REDUCER RATHER THAN CALLING THE ROUTE: the reducer guarantees exactly
    /// one ``IncomingCallCommand/requestAnswer(workspace:call:)`` per call.
    func answerPressed() {
        Task { await apply(.answerPressed) }
    }

    /// ⛔ NOTHING IS SENT TO THE SERVER FOR A DECLINE: a decline and a Mac nobody was at
    /// must be indistinguishable from outside.
    func declinePressed() {
        Task { await apply(.declinePressed) }
    }

    /// ⛔ "you hung up" IS A CLAIM ABOUT A PERSON AND THE REDUCER CANNOT MAKE IT.
    /// ``IncomingCallEvent/hangUpPressed`` is fed by ``hangUp()`` AND by ``endForSystem()``
    /// (sleep, quit, sign-out), so ``CallEndReason/hungUpLocally`` means "ended on this Mac"
    /// and nothing narrower. This bit is written on exactly one path, and cleared when the
    /// next call rings, because the ended sentence is drawn after teardown.
    private(set) var endedByOperator = false

    func hangUp() async {
        endedByOperator = true
        await apply(.hangUpPressed)
    }

    /// ⚠️ STRAIGHT TO THE REDUCER: there is no system call UI on a Mac for the microphone
    /// state to disagree with.
    func toggleMute() {
        Task { await apply(.muteToggled) }
    }

    /// ⚠️ NEVER OFFERED ON A MAC (no earpiece); kept because ``LiveCallControls`` serves
    /// both platforms' shapes. See ``LiveKitCallEngine/setSpeakerphone(_:)``.
    func toggleSpeaker() async {
        await apply(.speakerToggled)
    }

    func dismissEndedCall() {
        Task { await apply(.dismissed) }
    }

    /// The Mac is sleeping or quitting, or the session is ending. A ring is declined and a
    /// call is hung up; neither is attributed to the person.
    func endForSystem() async {
        switch state.phase {
        case .ringing:
            await withdraw()
        case .answering, .inCall:
            await apply(.hangUpPressed)
        case .idle, .ended:
            break
        }
    }

    // MARK: - Starting one ring

    /// ⛔ ONE CALL AT A TIME, AND THE CLAIM IS THE TEST. A second ring while a call is live
    /// is DROPPED rather than queued or allowed to replace: one engine owns the microphone,
    /// and a replacement would tear down a conversation to ring about another. The dropped
    /// call reaches the server's rendezvous timeout and goes back to the receptionist.
    ///
    /// - Returns: the task that applies the ring, or nil when the ring was dropped.
    @discardableResult
    private func ringing(workspace: WorkspaceID, call: CallID, workspaceName: String?) -> Task<Void, Never>? {
        // ⛔ AN ENDED-CALL SUMMARY IS NOT A CALL IN PROGRESS: a caller who was cut off and
        // dials straight back must ring, so the summary is cleared first.
        if state.phase.isEnded, !calls.hasLiveCall {
            controller.handle(.dismissed)
            state = controller.state
        }
        endedByOperator = false
        ringEndedByCall = false
        guard state.phase == .idle, !calls.hasLiveCall else {
            onRingSettled?()
            return nil
        }
        // ⛔ NEVER RING A MAC THAT CANNOT ANSWER.
        guard session != .unusable else {
            onRingSettled?()
            return nil
        }
        guard calls.claimCall(self) else {
            onRingSettled?()
            return nil
        }
        let ring = UUID()
        ringID = ring
        claimed = true
        self.workspaceName = workspaceName
        let start = Task {
            await apply(.ringing(workspace: workspace, call: call, atMilliseconds: Self.nowMilliseconds()))
            armRingTimeout(ring: ring)
        }
        // ⛔ LAST, AND IT MAY NEVER MOVE AHEAD OF THE GUARDS ABOVE. One request, never
        // retried; a caller's number is never logged. See ``IncomingCallIdentity``.
        caller = nil
        identityTask = Task { @MainActor [self] in
            let found = await IncomingCallIdentity.lookUp(callLog, workspace: workspace, call: call)
            guard let found, ringID == ring, !state.phase.isEnded, state.phase != .idle else { return }
            caller = found
        }
        return start
    }

    /// ⚠️ THE DECLINE EXIT (it sends nothing to the server), then straight past the summary.
    private func withdraw() async {
        await apply(.declinePressed)
        await apply(.dismissed)
    }

    /// The gate resolved to "there is no session". End a ring that is waiting on it.
    private func endForNoSession() {
        guard ringID != nil, !state.phase.isEnded, state.phase != .idle else { return }
        Task { await apply(state.phase == .ringing ? .declinePressed : .hangUpPressed) }
    }

    // MARK: - The one sink

    /// Apply one event, perform what it asked for, then settle.
    ///
    /// ⛔ EVERY EVENT GOES THROUGH HERE, WHICH IS WHAT MAKES ``release()`` TOTAL. The
    /// commands are performed IN ORDER and sequentially.
    func apply(_ event: IncomingCallEvent) async {
        let before = state.phase
        let commands = controller.handle(event)
        // ⚠️ WRITTEN BACK BEFORE THE AWAIT, so an interleaved event reads the new state.
        state = controller.state
        if before == .ringing, state.phase != .ringing {
            onRingSettled?()
        }
        await perform(commands)
        await settle()
    }

    private func perform(_ commands: [IncomingCallCommand]) async {
        for command in commands {
            await perform(command)
        }
    }

    private func perform(_ command: IncomingCallCommand) async {
        switch command {
        // ⚠️ THE RING IS THIS APP'S TO DRAW ON A MAC, unlike iOS where CallKit's screen is
        // the ring: the sound, the notification and the dock bounce. The panel follows
        // ``isPresented``.
        case let .startRinging(workspace, call):
            presenter.startRinging(workspaceId: workspace.rawValue, callId: call.rawValue)
        case .stopRinging:
            presenter.stopRinging()
        case let .requestAnswer(workspace, call):
            // ⛔ SPAWNED RATHER THAN AWAITED HERE: the round trip ends in another event, and
            // awaiting it inside this loop would re-enter ``apply(_:)`` mid-flight.
            answerTask = Task { @MainActor [weak self] in
                await self?.requestAnswer(workspace: workspace, call: call)
            }
        // ⚠️ NO-OPS ON A MAC: there is no system call record to keep in step. The call log
        // is the record, written by the carrier's webhooks.
        case .reportCallActive, .reportCallEnded:
            break
        case let .engine(engineCommand):
            await calls.perform(engineCommand)
        }
    }

    /// React to the phase the reducer has just reached.
    private func settle() async {
        switch state.phase {
        case .inCall:
            startTicking()
        case .ended:
            await release()
        case .idle, .ringing, .answering:
            break
        }
    }

    /// ⛔ THE ONE EXIT, AND IT DROPS THE CLAIM LAST.
    ///
    /// ⚠️ THE STATE IS NOT RESET HERE. ``IncomingCallPhase/ended(_:)`` is a screen the user
    /// leaves, and ``IncomingCallEvent/dismissed`` is what clears it.
    private func release() async {
        answerTask?.cancel()
        answerTask = nil
        engineTask?.cancel()
        engineTask = nil
        tickTask?.cancel()
        tickTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        identityTask?.cancel()
        identityTask = nil
        guard claimed else { return }
        claimed = false
        ringID = nil
        calls.releaseCall(self)
        calls.endCall()
    }

    // MARK: - The answer round trip

    /// ⛔ CALLED ONCE PER CALL AND NEVER RETRIED. `calls/answer` writes the rendezvous the
    /// agent's transfer is blocked on, so a second attempt races a call being connected.
    private func requestAnswer(workspace: WorkspaceID, call: CallID) async {
        // ⛔ THE MICROPHONE IS ASKED FIRST AND ITS ANSWER GATES NOTHING; see
        // ``prepareMicrophoneForAnswer()``. A call that ended while the alert was up must
        // not write the rendezvous afterwards, and ``release()`` cancels this.
        await prepareMicrophoneForAnswer()
        guard !Task.isCancelled else { return }
        let outcome = await inbound.answer(callId: call.rawValue, workspaceId: workspace.rawValue)
        switch outcome {
        case let .success(.joinable(response)):
            // ⛔ BEFORE THE EVENT: the reducer answers `.answerJoinable` with a connect, and
            // ``CallStack/perform(_:)`` drops a command with no engine. ⛔ AWAITED: it also
            // takes the audio off a live room.
            await startEngine()
            await apply(.answerJoinable(url: response.url, token: response.token))
        case .success(.callerGone):
            await apply(.answerRejected(.callerGone))
        case let .success(.refused(message)):
            await apply(.answerRejected(.refused(message: message)))
        case let .failure(error):
            await apply(.answerRejected(.refused(message: FailureText.from(error).message)))
        }
    }

    /// ⚠️ THE WALL CLOCK, because the reducer's bound is a timestamp.
    static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
