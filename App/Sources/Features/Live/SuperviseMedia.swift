import DistrictCall
import Foundation

/// What a live supervision asks of this Mac: the call claim, and one engine per leg.
///
/// ⛔ A SEAM SO ``SuperviseModel``'S ORDER IS TESTED WITHOUT LIVEKIT. The reducer
/// (`SuperviseSession`, district-core-swift) decides; the model performs its commands in
/// order through this, and `SuperviseModelTests` records what reached it. The one
/// conformance the app ships is ``CallStackSuperviseMedia``.
///
/// ⛔ NO CALLKIT ON A MAC (``CallStack``). Where district-ios starts a system call, this
/// claims the Mac's one call slot: a supervision then holds ``CallStack/hasLiveCall`` like a
/// placed or answered call, a dial or a room join is refused during it, a ring arriving
/// falls back the way it does over any call, and sleep, quit and sign-out end it through
/// ``LiveCallOwner/endForSystem()``. A takeover is a second ROOM under the same claim.
@MainActor
protocol SuperviseMedia: AnyObject {
    /// Whether a phone call or a meeting room already holds this Mac. ⚠️ Two answers,
    /// because the sentence differs: ``SuperviseCopy/busyWithCall`` or
    /// ``SuperviseCopy/busyInRoom``.
    var hasLiveCall: Bool { get }
    var hasLiveRoom: Bool { get }

    /// The microphone permission. ⛔ Asked before a takeover only: a listener publishes
    /// nothing, so listening needs no permission at all.
    var microphone: any MicrophoneAccess { get }

    /// Take the Mac's call slot for `owner`. False when another call holds it.
    func claim(_ owner: SuperviseModel) -> Bool
    /// Give the claim back. ⛔ Only `owner`'s.
    func release(_ owner: SuperviseModel)

    /// Build a fresh engine for one leg and hand back its events. ⛔ The previous leg's
    /// engine is torn down first.
    func beginLeg(_ leg: SuperviseLeg) async -> AsyncStream<CallEngineEvent>
    /// One command for the engine that exists. ⚠️ Dropped when there is none.
    func perform(_ command: CallCommand) async
    /// Drop the engine, if any. ⛔ Not a hang-up; the reducer has already disconnected.
    func endLeg()
}

/// ``SuperviseMedia`` over the process's one ``CallStack``.
///
/// ⛔ THE SAME CLAIM AND THE SAME ONE-ENGINE SLOT AS THE DIALLER AND THE ANSWERED CALL, so the
/// overlap rules are the ones those already keep.
@MainActor
final class CallStackSuperviseMedia: SuperviseMedia {
    private let stack: CallStack

    init(stack: CallStack) {
        self.stack = stack
    }

    var hasLiveCall: Bool {
        stack.hasLiveCall
    }

    var hasLiveRoom: Bool {
        stack.hasLiveRoom
    }

    var microphone: any MicrophoneAccess {
        stack.microphone
    }

    func claim(_ owner: SuperviseModel) -> Bool {
        guard stack.claimCall(owner) else { return false }
        stack.supervisor = owner
        return true
    }

    func release(_ owner: SuperviseModel) {
        if stack.supervisor === owner {
            stack.supervisor = nil
        }
        stack.releaseCall(owner)
    }

    func beginLeg(_ leg: SuperviseLeg) async -> AsyncStream<CallEngineEvent> {
        // ⛔ THE LISTEN LEG NEVER PUBLISHES THE MICROPHONE, and both legs count the people
        // already in the room (district-ios #101, xhigh review item 1): the room emptying is how
        // `SuperviseSession` knows the call ended.
        await stack.beginCall(publishingMicrophone: leg == .takeover, announcingPresentParticipants: true)
    }

    func perform(_ command: CallCommand) async {
        await stack.perform(command)
    }

    func endLeg() {
        stack.endCall()
    }
}
