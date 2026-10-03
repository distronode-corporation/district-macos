import DistrictCall
import Foundation

/// The platform half of a call, assembled once so no feature has to wire it.
///
/// Ported from district-ios `Platform/CallStack.swift` (see PORTING.md), WITHOUT CALLKIT.
/// The Mac has no CallKit and no VoIP push by decision (plan decision 4): it rings over
/// the telemetry socket while the app runs, and its call surfaces are this app's own
/// windows. So the iOS stack's `CXProvider` and `AVAudioSession` coordinator are gone,
/// and what is left is the part that was never about the OS:
///
///   * A LiveKit `Room` is **one per call**. ``CallEngine``'s own ⛔ says why: it holds a
///     live socket and the audio devices, and the SDK does not support a second `connect`
///     after a disconnect. So the engine is built by ``beginCall()`` and dropped by
///     ``endCall()``.
///   * **Who owns this Mac's audio.** A meeting room and a telephone call both take the
///     one microphone, and a meeting that heard a private customer call (or a caller who
///     heard a meeting) is a breach in both directions. ``hasLiveCall``, ``hasLiveRoom``
///     and ``endRoom(_:)`` make the exclusion mutual, exactly as on iOS.
///
/// ⛔ THE CALL CLAIM IS ALSO THE CALL MODEL'S LIFETIME. iOS anchors a call on the closure
/// it installs in `CallKitBridge.onSystemRequest`; here the anchor is ``callOwner``,
/// held strongly for exactly the length of one call and released on every terminal path.
/// A screen torn down mid-call (another sidebar section chosen, the ring panel closed)
/// therefore leaves the call running with an owner still driving it.
///
/// ⚠️ `@MainActor` BECAUSE BOTH CALL MODELS ARE. Everything underneath is `Sendable`, so
/// reaching the nonisolated engine from here is an ordinary async call.
@MainActor
final class CallStack {
    /// The engine for the call in progress, or nil between calls.
    ///
    /// ⚠️ EXPOSED AS ``CallEngine`` RATHER THAN AS THE CONCRETE TYPE, so a caller cannot
    /// reach a LiveKit symbol through it.
    private(set) var engine: (any CallEngine)?

    /// The model that owns the live telephone call, or nil.
    ///
    /// ⛔ HELD STRONGLY, AND THAT IS THE POINT RATHER THAN A LEAK. See the ⛔ on the type.
    /// ``releaseCall(_:)`` is the only thing that breaks it, and both call models reach it
    /// from their one teardown.
    private(set) var callOwner: (any LiveCallOwner)?

    /// The live meeting room, or nil. ⛔ Held strongly for the reason ``callOwner`` is:
    /// a live microphone must outlive the screen that started it, and something must end
    /// it. See ``endRoom(_:)`` and its callers.
    private(set) var room: (any RoomAudio)?

    /// The outbound dialler that owns the live call, so a dial screen rebuilt around the
    /// call can find it again, or nil. ⛔ WEAK: the claim already keeps it alive.
    weak var softphone: AnyObject?

    /// Carrier hang-ups still on their way. ⛔ Awaited (briefly) before the app quits, so
    /// quitting mid-call cannot leave a telephone ringing an empty room and billing. See
    /// ``trackServerHangUp(_:)``.
    private var pendingHangUps: [UUID: Task<Void, Never>] = [:]

    /// Whether a telephone call is live on this Mac, in either direction.
    ///
    /// ⛔ THE CLAIM, NOT ``engine``. The engine is built at MEDIA time, so `engine == nil`
    /// is true throughout a 30-second ring and the whole outbound window between the Call
    /// press and the dial being accepted; a room guard that tested it would let a meeting
    /// be joined during a live ring.
    var hasLiveCall: Bool {
        callOwner != nil
    }

    /// Whether a meeting room owns this Mac's audio.
    var hasLiveRoom: Bool {
        room != nil
    }

    /// Whether this app may use the microphone, and the one way to ask. ⛔ Asked by both
    /// call models before their media join can fail for want of it.
    let microphone: any MicrophoneAccess

    /// The microphone and speaker the calls use. ⛔ One per process, shared with the
    /// Settings window and every in-call surface, so a choice made in one is the choice
    /// all of them show.
    let devices: AudioDevices

    /// - Parameter microphone: the permission seam. ⚠️ The live one everywhere but a test.
    init(microphone: any MicrophoneAccess = LiveMicrophoneAccess(), devices: AudioDevices = AudioDevices()) {
        self.microphone = microphone
        self.devices = devices
    }

    // MARK: - The call claim

    /// Take the call claim for `owner`.
    ///
    /// - Returns: false when another call already holds it. ⛔ ONE CALL AT A TIME: two
    ///   engines would fight over the one microphone.
    @discardableResult
    func claimCall(_ owner: any LiveCallOwner) -> Bool {
        guard callOwner == nil || callOwner === owner else { return false }
        callOwner = owner
        return true
    }

    /// Give the call claim back. ⛔ Identity-checked, so a model that already released
    /// cannot release a later model's call.
    func releaseCall(_ owner: any LiveCallOwner) {
        guard callOwner === owner else { return }
        callOwner = nil
    }

    /// End whatever is live on this Mac's audio, for a reason nobody pressed.
    ///
    /// ⛔ THE MAC'S ANSWER TO WHAT CALLKIT WOULD HAVE DONE ON iOS. The Mac is about to sleep
    /// or quit, or the session is ending: the call cannot survive any of them (the socket
    /// dies with the network or the process), so it is ended through its own reducer,
    /// which is what sends the carrier hang-up for a placed call. A ring is declined the
    /// same way, and a meeting is left.
    func endEverything(_ reason: RoomAudioYield) async {
        if let owner = callOwner {
            await owner.endForSystem()
        }
        await endRoom(reason)
    }

    // MARK: - The engine

    /// Build the engine for one call and hand back everything it will report.
    ///
    /// ⛔ THE RETURNED STREAM IS READ EXACTLY ONCE. `AsyncStream` delivers each element to
    /// a SINGLE consumer, so a second `for await` silently splits the events between two
    /// readers.
    ///
    /// ⛔ IT TAKES THE AUDIO OFF A LIVE ROOM FIRST, WHICH IS WHY IT IS ASYNC AND AWAITED.
    /// "One owner" is only true if the previous one is gone before the next one starts.
    /// On the outbound path this is a no-op (a dial is refused while a room is live), so
    /// only an inbound answer reaches here with a room to yield.
    ///
    /// ⚠️ IT TEARS DOWN A PREVIOUS ENGINE RATHER THAN LEAKING ONE, though reaching here
    /// with one would be a bug in the caller.
    func beginCall() async -> AsyncStream<CallEngineEvent> {
        await endRoom(.telephoneCall)
        endCall()
        let engine = LiveKitCallEngine(devices: devices)
        self.engine = engine
        return engine.events
    }

    /// Release the engine once the call's reducer has reached a terminal phase.
    ///
    /// ⚠️ NOT A HANG-UP. The reducers emit ``CallCommand/disconnect`` themselves; this drops
    /// the object afterwards, and its disconnect is belt and braces (idempotent by
    /// contract). ⚠️ Fire and forget.
    func endCall() {
        guard let previous = engine else { return }
        engine = nil
        Task { await previous.disconnect() }
    }

    /// Perform one reducer's command list. ⛔ IN ORDER, SEQUENTIALLY: the order is part of
    /// ``CallCommand``'s contract.
    func perform(_ commands: [CallCommand]) async {
        for command in commands {
            await perform(command)
        }
    }

    /// ⛔ A COMMAND WITH NO ENGINE IS DROPPED: only a `disconnect` on a path that never
    /// connected (a refused dial, a declined ring) can arrive here without one.
    ///
    /// ⚠️ THE CONNECT ERROR IS SWALLOWED, as ``CallEngine/connect(url:token:)`` asks: the
    /// engine has already emitted ``CallEngineEvent/failed(message:)``.
    func perform(_ command: CallCommand) async {
        guard let engine else { return }
        switch command {
        case let .connect(url, token):
            try? await engine.connect(url: url, token: token)
        case .disconnect:
            await engine.disconnect()
        case let .setMuted(muted):
            await engine.setMuted(muted)
        case let .setSpeakerphone(enabled):
            await engine.setSpeakerphone(enabled)
        }
    }

    // MARK: - The carrier hang-up that must outlive the call

    /// Keep `work` (a carrier hang-up) until it finishes, so ``drainServerHangUps(within:)``
    /// can wait for it before the app quits.
    func trackServerHangUp(_ work: @escaping @Sendable () async -> Void) {
        let id = UUID()
        pendingHangUps[id] = Task { [weak self] in
            await work()
            self?.finishedServerHangUp(id)
        }
    }

    private func finishedServerHangUp(_ id: UUID) {
        pendingHangUps[id] = nil
    }

    /// Wait for every carrier hang-up still on its way, for at most `seconds`.
    ///
    /// ⚠️ BOUNDED, because a quit must not hang on a network that has gone. A hang-up that
    /// does not make it is the same outcome as a Mac that lost power mid-call.
    ///
    /// ⚠️ A RACE, NOT A CANCELLATION: awaiting a task's value is not interrupted by
    /// cancelling the waiter, so the deadline resumes the caller itself and the requests
    /// carry on in the background for as long as the process lives.
    func drainServerHangUps(within seconds: Double) async {
        let pending = Array(pendingHangUps.values)
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resume = ResumeOnce(continuation)
            Task {
                for task in pending {
                    await task.value
                }
                resume.fire()
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                resume.fire()
            }
        }
    }

    // MARK: - The room claim

    /// Record that a room owns this Mac's audio. ⚠️ LAST WRITER WINS, safe only because
    /// `ActiveRoomModel.join()` refuses while ``hasLiveRoom`` is true.
    func claimRoom(_ owner: any RoomAudio) {
        room = owner
    }

    /// Give the claim back. ⛔ Identity-checked.
    func releaseRoom(_ owner: any RoomAudio) {
        guard room === owner else { return }
        room = nil
    }

    /// End the live room, if there is one, and tell it why.
    ///
    /// ⛔ THE CLAIM IS DROPPED BEFORE THE ROOM IS TOLD, WHICH IS WHAT KEEPS THIS IDEMPOTENT.
    func endRoom(_ reason: RoomAudioYield) async {
        guard let room else { return }
        self.room = nil
        await room.yieldAudio(reason)
    }
}

/// The model that owns a live telephone call, as ``CallStack`` needs to see it.
///
/// ⚠️ A PROTOCOL RATHER THAN THE TWO MODELS, so this tier names no feature type, and
/// `AnyObject` because the claim is an identity.
@MainActor
protocol LiveCallOwner: AnyObject {
    /// End the call because the Mac is sleeping or quitting, or the session is ending.
    /// ⚠️ Not a press: the ended-call summary must not say "you hung up".
    func endForSystem() async
}

/// Resumes a continuation the first time it is fired, and never again.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }
}
