import DistrictCall
import DistrictData
import DistrictModel
import Foundation
import Observation

/// The outbound softphone: the keypad, and the one call it may have in flight.
///
/// ⛔ IT PLACES CALLS, WHICH MAKES IT THE ONLY MODEL IN THIS APP WHOSE MISTAKES COST
/// MONEY AND RING A STRANGER'S TELEPHONE. Four properties follow from that and are
/// each enforced here rather than left to care, and they are the same four the Kotlin
/// `DialerViewModel` states:
///
///   1. **Nothing dials without an explicit tap.** No `.task` dials on entry, and
///      there is no retry anywhere at any layer. `POST /api/district/calls/dial`
///      writes the `Call` row and instructs the carrier BEFORE it mints the credential
///      it answers with, so a re-send is a second call to the same person, billed
///      again. ``DialRepository``'s own ⛔ says the property holds by construction
///      today; this is the half of it that lives in a screen.
///   2. **One audio owner at a time**, and a second attempt while a call OR A MEETING
///      ROOM is live is refused rather than queued. Two engines would fight over the
///      device's audio focus. ⚠️ The room half is enforced here; see ``RoomAudio``.
///   3. **The number travels exactly as typed.** Normalisation is the server's and it
///      runs BEFORE the DNC lookup and before the dial, so a client-side canonicaliser
///      that disagreed by one character would place a call the compliance check never
///      saw.
///   4. **The call outlives the screen.** See below.
///
/// Ported from district-ios `Features/Dialer/DialerModel.swift` (see PORTING.md), WITHOUT
/// CALLKIT: iOS places the dial only once CallKit has performed its start action; a Mac
/// has no system call surface, so the dial goes out straight after the microphone answer.
///
/// ⛔ THE CALL'S LIFETIME IS THE CALL CLAIM (``CallStack/claimCall(_:)``), AND THAT IS
/// ALSO WHAT KEEPS THIS OBJECT ALIVE. `AppContainer` holds one ``CallStack`` for the
/// process; ``placeCall()`` claims it for this model, strongly, and ``release()`` gives it
/// back on every terminal path. Three things fall out, and all three are the point:
///
///   * A screen torn down mid-call does not end the call. The engine still has its
///     socket and this model is still reading the engine stream, because the container
///     holds it. A model that died with its view would leave a live microphone the user
///     believes is off.
///   * A SECOND dialer cannot steal the first call: ``placeCall()`` refuses while the
///     claim is held.
///   * The claim is a strong reference for exactly the duration of one call, and
///     ``release()`` is the only thing that drops it. It is reached from a single sink
///     (``settle()``) on every terminal phase, plus every refusal.
///
/// ⛔ THERE IS NO `deinit`. It could not do the cleanup anyway (a `@MainActor` class's
/// `deinit` is nonisolated under Swift 6 and cannot touch these stored properties, and
/// it does not need to: while a call is live the claim makes deallocation impossible,
/// and when no call is live there is nothing to clean up. Nothing else here escapes
/// this object: both background tasks capture `self` weakly and are cancelled by
/// ``release()``.
///
/// ⛔ NO VIDEO, EVER, AND THE ENFORCEMENT IS AN ABSENCE. ``CallCommand`` has no camera
/// case and ``CallEngine`` has no camera member, so the softphone cannot publish video
/// even by accident. See the ⛔ on ``InCallView``.
///
/// ⚠️ ITS ``LiveCallControls`` CONFORMANCE ADDS NO CODE: the four members have
/// exactly the protocol's signatures, and the protocol exists so ``InCallView`` can
/// serve the inbound call as well. See the ⛔ on that protocol for why the STATE is
/// not shared the same way.
@MainActor
@Observable
final class DialerModel: LiveCallControls, LiveCallOwner {
    /// What the operator typed, verbatim. ⛔ See property 3 on the type.
    private(set) var entry: String = ""

    /// The live call, or nil when the dialer is on the keypad.
    ///
    /// ⛔ HELD HERE RATHER THAN BEING A DESTINATION, WHICH IS A SAFETY DECISION RATHER
    /// THAN A LAYOUT ONE. See the ⛔ on `Route.dialer`: a relaunched app comes back to an
    /// idle keypad, which is the truth, because the socket died with the process.
    private(set) var call: SoftphoneSession?

    /// Why the last dial did not happen, or nil.
    ///
    /// ⚠️ SHOWN ON THE KEYPAD RATHER THAN OVER A CALL SCREEN, because a refused dial
    /// produced no call and there is nothing to show it over. Cleared the moment the
    /// entry changes.
    private(set) var refusal: FailureText?

    /// The recent inbound callers, or why they could not be read.
    ///
    /// ⛔ A FAILED READ MUST NOT DISABLE THE KEYPAD, and the enforcement is structural:
    /// ``canPlaceCall`` does not mention this property. See ``DialerCallbacksState``.
    private(set) var callbacks: DialerCallbacksState = .loading

    /// True between the press and the dial going out (the microphone question).
    ///
    /// ⚠️ ITS OWN FLAG RATHER THAN A PHASE, because there is no session yet, and the
    /// button still has to say something.
    private(set) var placing = false

    /// ⛔ `allowsMutation` ON THE OPTIONAL, NOT `role != .viewer`. A role the wire did
    /// not recognise is nil, and `nil != .viewer` is TRUE, so the shorter expression
    /// would hand an unknown role the ability to spend the workspace's minutes.
    let canDial: Bool

    let calls: CallStack

    /// ⚠️ MODULE-VISIBLE, WITH ``workspaceId``, BECAUSE `DialerServerHangUp.swift`
    /// SPENDS BOTH. Immutable `let`s: there is no setter to hand a view.
    let dial: DialRepository

    /// ⚠️ `callLog` BECAUSE `calls` ABOVE IS THE LIVE CALL, not the log of past ones.
    private let callLog: CallsRepository
    let workspaceId: String

    /// Why the last carrier hang-up did not go through. ⛔ DIAGNOSIS ONLY, never
    /// user-facing, which is why the SETTER widens where ``refusal``'s did not.
    var lastServerHangUpFailure: String?

    /// The attempt this model owns, or nil between calls. ⚠️ The Mac's stand-in for the
    /// CallKit UUID: a fresh value per press, so a late answer for an earlier attempt is
    /// recognised as late.
    private var attemptID: UUID?

    /// The number pinned at the press. ⛔ See ``placeCall()``.
    private var pendingNumber = ""

    /// True while ``CallStack/callOwner`` is this model.
    private var claimed = false

    /// ⛔ "you hung up" IS A CLAIM ABOUT A PERSON AND THE REDUCER CANNOT MAKE IT.
    /// ``SoftphoneEvent/hangUpPressed`` is fed by ``hangUp()`` AND by ``endForSystem()``
    /// (sleep, quit, sign-out), so ``CallEndReason/hungUpLocally`` means "ended on this
    /// Mac" and nothing narrower. This bit is written on exactly one path, and cleared at
    /// the next press rather than in ``release()`` because the summary is drawn AFTER
    /// teardown.
    private(set) var endedByOperator = false

    // ⚠️ MODULE-VISIBLE RATHER THAN `private`, ALONG WITH ``calls`` AND ``apply(_:)``,
    // BECAUSE THE TASKS THAT WRITE THEM LIVE IN `DialerTasks.swift` AND SWIFT'S `private`
    // IS FILE-SCOPED. It is a `file_length` consequence, not an invitation.
    var engineTask: Task<Void, Never>?
    var tickTask: Task<Void, Never>?

    init(container: AppContainer, workspaceId: String, role: WorkspaceRole?) {
        calls = container.callStack
        dial = container.dial
        callLog = container.calls
        self.workspaceId = workspaceId
        canDial = WorkspaceRole.allowsMutation(role)
    }

    // MARK: - What the keypad may do

    /// ⚠️ CLEARS THE PREVIOUS REFUSAL, because it was about a different number.
    func onEntryChange(_ value: String) {
        entry = value
        refusal = nil
    }

    /// Read the recent inbound calls the operator might return. ⚠️ IDEMPOTENT AND SAFE
    /// TO REPLAY, unlike everything else here, because it is a GET and dials nothing.
    func loadCallbacks() async {
        switch await callLog.recentCallbacks(workspaceId: workspaceId) {
        case let .success(rows):
            callbacks = .ready(rows)
        case let .failure(error):
            // ⛔ A FAILURE, NEVER AN EMPTY LIST.
            callbacks = .failed(FailureText.from(error))
        }
    }

    // MARK: - Placing one call

    /// The operator pressed Call.
    ///
    /// ⛔ IT ASKS THE MICROPHONE, THEN DIALS. See ``startAfterMicrophone(attempt:)``: a dial
    /// that asked nothing would fail only at the media join, after the carrier had already
    /// rung the callee on a real, billed line.
    func placeCall() {
        guard canPlaceCall else { return }
        // ⛔ THE PROCESS HOLDS ONE CALL. See property 2 on the type. This also covers an
        // inbound call (or a ring) already holding the claim.
        guard !calls.hasLiveCall else {
            refusal = Self.busy
            return
        }
        // ⛔ AND ONE AUDIO OWNER, WHICH IS A WIDER STATEMENT THAN THE LINE ABOVE. Dialling
        // from inside a live room would put the meeting on the call and the call in the
        // meeting.
        //
        // ⛔ REFUSED RATHER THAN YIELDED, WHICH IS THE OPPOSITE OF WHAT AN INBOUND CALL
        // DOES, AND THE ASYMMETRY IS THE DECISION. This is a deliberate press by an
        // operator who can be told a sentence; an inbound call is revenue arriving from
        // somebody who cannot, so that one wins and the room is left. See the ⛔ on
        // ``RoomAudioYield/telephoneCall``.
        guard !calls.hasLiveRoom else {
            refusal = Self.inRoom
            return
        }
        guard calls.claimCall(self) else {
            refusal = Self.busy
            return
        }
        refusal = nil
        placing = true
        // ⚠️ CLEARED HERE, NOT IN ``release()``. See the ⛔ on the property.
        endedByOperator = false
        // ⛔ THE NUMBER IS PINNED AT THE PRESS, NOT READ AGAIN AT DIAL TIME. The keypad is
        // still on screen while the microphone question is up, so a field read later
        // could dial a DIFFERENT number from the one the operator pressed Call on. The
        // field is disabled while `placing` for the same reason.
        pendingNumber = entry
        let attempt = UUID()
        attemptID = attempt
        claimed = true
        // ⚠️ AND FINDABLE: a dial screen rebuilt around this call re-attaches to this model
        // through ``CallStack/softphone`` (weak; the claim keeps it alive).
        calls.softphone = self
        Task { await startAfterMicrophone(attempt: attempt) }
    }

    /// End the call this model owns. ⚠️ IDEMPOTENT: ``SoftphonePhase/ended(_:)`` is
    /// terminal and absorbs a second press, so the disconnect is emitted exactly once.
    func hangUp() async {
        guard attemptID != nil else { return }
        // ⛔ THE ONLY PLACE THIS IS SET. See the ⛔ on the property.
        endedByOperator = true
        await apply(.hangUpPressed)
    }

    /// ⚠️ STRAIGHT TO THE REDUCER: there is no system call UI on a Mac for the microphone
    /// state to disagree with (iOS routes this through CallKit for that reason).
    func toggleMute() {
        Task { await apply(.muteToggled) }
    }

    /// ⚠️ NEVER OFFERED ON A MAC, which has no earpiece; see ``InCallView``.
    func toggleSpeaker() async {
        await apply(.speakerToggled)
    }

    /// Dismiss the ended-call summary and return to the keypad.
    func dismissEndedCall() {
        guard let session = call, case .ended = session.state.phase else { return }
        call = nil
    }

    /// The Mac is sleeping or quitting, or the session is ending.
    ///
    /// ⛔ A LIVE CALL ENDS THROUGH THE REDUCER, which is what sends the carrier hang-up: a
    /// call that simply lost its socket would leave the far end talking to an empty room,
    /// billed. A press still waiting on the microphone question places nothing.
    func endForSystem() async {
        if call != nil {
            await apply(.hangUpPressed)
        } else if placing {
            refusal = nil
            await release()
        }
    }

    // MARK: - Dialling

    /// Place the dial.
    func beginDial(attempt: UUID) async {
        guard call == nil, attemptID == attempt else { return }
        placing = false
        call = SoftphoneSession(number: pendingNumber)
        await apply(.dialRequested)
        // ⛔ THE NUMBER AS TYPED. See property 3 on the type.
        let outcome = await dial.dial(workspaceId: workspaceId, to: pendingNumber)
        // ⛔ THE CALL CAN END WHILE THE DIAL IS IN FLIGHT (a hang-up a second after the
        // press, measured on iOS), and the answer is NOT dropped, because that is where
        // the money goes: the server has ALREADY dialled a telephone and the body carries
        // the only `callId` this client will ever hold. See ``abandonPlacedCall(_:)``.
        guard attemptID == attempt else {
            await abandonPlacedCall(outcome)
            return
        }
        switch outcome {
        case let .success(outcome):
            await accept(outcome)
        case let .failure(error):
            await refuse(FailureText.from(error))
        }
    }

    /// ⛔ THE THREE REFUSALS CARRY THE SERVER'S OWN SENTENCE. Their remedies differ, and
    /// a client that paraphrased would tell the operator something the server did not
    /// say. See the ⛔ on ``DialOutcome``.
    private func accept(_ outcome: DialOutcome) async {
        switch outcome {
        case let .placed(response):
            // ⛔ BEFORE THE EVENT, because the reducer answers `.dialAccepted` with
            // ``CallCommand/connect(url:token:)`` and ``CallStack/perform(_:)`` drops a
            // command that arrives with no engine.
            await startEngine()
            await apply(.dialAccepted(response))
        case let .doNotCall(message):
            await refuse(Self.refusalText(message, fallback: Self.doNotCallFallback))
        case let .subscriptionInactive(message):
            await refuse(Self.refusalText(message, fallback: Self.subscriptionFallback))
        case let .workspaceDormant(message):
            await refuse(Self.refusalText(message, fallback: Self.dormantFallback))
        }
    }

    /// ⛔ THE REDUCER IS TOLD BEFORE THE STATE IS CLEARED, and then the call is dropped
    /// because NOTHING WAS PLACED.
    private func refuse(_ text: FailureText) async {
        await apply(.dialRefused)
        call = nil
        refusal = text
        await release()
    }

    // MARK: - The one sink

    /// Apply one event, perform what it asked for, then settle.
    ///
    /// ⛔ EVERY EVENT GOES THROUGH HERE, WHICH IS WHAT MAKES ``release()`` TOTAL. The
    /// commands are performed IN ORDER and sequentially.
    func apply(_ event: SoftphoneEvent) async {
        guard var session = call else { return }
        let commands = session.handle(event)
        // ⚠️ WRITTEN BACK BEFORE THE AWAIT, so an interleaved event reads the new state.
        call = session
        await perform(commands)
        await settle()
    }

    /// React to the phase the reducer has just reached.
    private func settle() async {
        guard let session = call else { return }
        switch session.state.phase {
        case .connected:
            startTicking()
        case .ended:
            await release()
        case .idle, .dialing, .connecting, .ringing:
            break
        }
    }

    /// ⛔ THE ONE EXIT, AND IT DROPS THE CLAIM LAST. Releasing the claim drops the
    /// container's only strong reference to this object.
    ///
    /// ⚠️ SAFE TO CALL WITH NOTHING CLAIMED.
    private func release() async {
        engineTask?.cancel()
        engineTask = nil
        tickTask?.cancel()
        tickTask = nil
        placing = false
        guard claimed else { return }
        claimed = false
        attemptID = nil
        calls.releaseCall(self)
        calls.endCall()
    }

    // MARK: - The press that dialled nothing

    /// ⚠️ THE ONE WRITER OF ``refusal`` OUTSIDE THIS FILE'S OWN METHODS, which is why it
    /// stays here: `private(set)` is what stops a view assigning a refusal the keypad never
    /// earned.
    func abandonStart(attempt: UUID, because text: FailureText) async {
        guard attemptID == attempt, call == nil else { return }
        refusal = text
        await release()
    }
}
