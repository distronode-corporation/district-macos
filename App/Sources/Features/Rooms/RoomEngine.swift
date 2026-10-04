import AVFoundation
import Foundation
import LiveKit

/// The multi-party room's own LiveKit session.
///
/// ⛔ A SECOND ENGINE BESIDE ``LiveKitCallEngine``, NOT A WIDENING OF IT, AND THAT IS
/// THE WHOLE POINT OF THIS FILE. The softphone's seam is ``CallEngine`` in
/// `DistrictCall`, and that protocol has NO camera member, ``CallCommand`` has no
/// camera case, ``CallEngineEvent`` has no video-track case, and `connect(url:token:)`
/// takes no encryption key. Every one of those absences is deliberate and documented
/// as such in `CallEngine.swift`: "⛔ THERE IS NO CAMERA COMMAND, ON PURPOSE" and
/// "there is no video-track case ... Keeping the box out of this target is what makes
/// that structural instead of a comment." Publishing video through that seam would
/// mean adding members to all three types, in the module the two call state machines
/// are built on, which is shared call-path code and is exactly the change this type
/// exists to avoid.
///
/// ⛔ SO NOTHING IN THE CALL PATH IS TOUCHED BY THIS TYPE. It does not conform to
/// ``CallEngine`` and it is never handed to ``CallStack`` as an engine. What it costs is
/// duplication: the connection-state mapping below is a near-copy of
/// `LiveKitCallEngine`'s, deliberately, because the alternative was one shared
/// implementation whose every change is a change to the softphone.
///
/// ⛔ THE TWO MEET AT THE ONE MICROPHONE (and LiveKit's process-wide `AudioManager`, which
/// both apply the chosen devices to). The overlap is kept out by ``CallStack``, which
/// holds the live room AND the live call and refuses or ends whichever one arrives
/// second.
/// ⛔ A REFUSAL IN ``ActiveRoomModel`` ALONE WOULD BE HALF A GUARD. It covers a room
/// joined during a call and nothing else; a CALL starting during a room is the other
/// half, which is why ``CallStack`` ends the room. See the ⛔ on ``ActiveRoomModel``.
///
/// ⛔ ONE ENGINE PER ROOM, BUILT WHEN THE CREDENTIAL ARRIVES. `LiveKitCallEngine`
/// builds its `Room` in `init`; this one cannot, because the encryption key is part
/// of the token response and `RoomOptions` is fixed at construction. A `Room` does
/// not support a second `connect` after it has disconnected either way, so the object
/// is built for one join and dropped with it.
///
/// ⚠️ `@unchecked Sendable` FOR THE SAME REASON `LiveKitCallEngine` IS: every stored
/// property is a `let`, and the only mutable state is inside the `Room` the SDK owns.
final class RoomEngine: @unchecked Sendable {
    /// ⚠️ READ EXACTLY ONCE, BY ``ActiveRoomModel``. `AsyncStream` hands each element
    /// to a single consumer, so a second `for await` would SPLIT the events between
    /// two readers rather than mirroring them.
    let events: AsyncStream<RoomEngineEvent>

    private let continuation: AsyncStream<RoomEngineEvent>.Continuation

    /// ⚠️ HELD SO THE SDK'S WEAK DELEGATE REFERENCE HAS AN OWNER. `Room` does not
    /// retain its delegate; a bridge that lived only as an argument to `Room.init`
    /// would be deallocated immediately and every callback would go nowhere, with no
    /// error anywhere to say so. `LiveKitCallEngine` records the same trap.
    private let bridge: RoomSessionBridge

    private let room: Room

    /// The microphone and speaker this Mac uses. ⚠️ Applied at each join, as the call
    /// engine does; see ``AudioDevices``.
    private let devices: AudioDevices

    /// - Parameter e2eeKey: ⛔ THE PASSPHRASE, HANDED TO THE SDK VERBATIM AND NEVER
    ///   BASE64-DECODED. `RoomTokenResponse.E2EEInfo` carries the rule in full: it
    ///   arrives as the base64 TEXT of 32 random bytes and it is tempting to read
    ///   "base64" as an instruction. Every LiveKit SDK UTF-8-encodes this string and
    ///   runs PBKDF2 over those ASCII bytes; decoding to raw bytes selects a
    ///   different derivation and a different AES key, and the failure mode is not an
    ///   error. Both sides join, both publish, and every track is undecryptable
    ///   noise. ⛔ nil AND EMPTY BOTH MEAN "JOIN UNENCRYPTED", which is a real answer
    ///   rather than a fault; an empty passphrase would derive a real key nobody else
    ///   in the room derives, which is worse than none.
    init(e2eeKey: String?, devices: AudioDevices) {
        let (stream, continuation) = AsyncStream<RoomEngineEvent>.makeStream()
        events = stream
        self.continuation = continuation
        self.devices = devices

        let bridge = RoomSessionBridge(continuation: continuation)
        self.bridge = bridge
        room = Room(delegate: bridge, roomOptions: RoomEngine.options(e2eeKey: e2eeKey))
    }

    /// ⛔ THE ONE EXPRESSION IN THE ROOMS FEATURE THAT NAMES THE SDK'S ENCRYPTION TYPES,
    /// AND IT IS ISOLATED HERE ON PURPOSE. The Linux tier cannot compile a LiveKit
    /// symbol, so the shape of `RoomOptions`, `EncryptionOptions` and `BaseKeyProvider` is
    /// checked only by the app build; keeping it to one function means a correction is
    /// one function rather than a sweep.
    ///
    /// ⚠️ `adaptiveStream` AND `dynacast` ARE ON HERE AND ABSENT FROM THE SOFTPHONE.
    /// `LiveKitCallEngine` says why in its own ⚠️: they are video-only knobs and the
    /// softphone publishes no video. A phone-sized grid of remote cameras is exactly
    /// what they exist for.
    ///
    /// ⚠️ `encryptionOptions`, NOT THE DEPRECATED `e2eeOptions`. The media frames are
    /// encrypted exactly as before (the same shared-key provider, AES-GCM). The newer
    /// type also encrypts data-channel packets; a room on this Mac sends none and reads
    /// none, so nothing it does depends on whether the other participants do.
    private static func options(e2eeKey: String?) -> RoomOptions {
        guard let e2eeKey, !e2eeKey.isEmpty else {
            return RoomOptions(adaptiveStream: true, dynacast: true)
        }
        let provider = BaseKeyProvider(isSharedKey: true, sharedKey: e2eeKey)
        return RoomOptions(
            adaptiveStream: true,
            dynacast: true,
            encryptionOptions: EncryptionOptions(keyProvider: provider)
        )
    }

    /// Join the room.
    ///
    /// ⚠️ PORTED WITHOUT iOS's AUDIO-SESSION HALF. iOS turns LiveKit's `AVAudioSession`
    /// automation back ON here (the softphone turns it off); macOS has no audio session and
    /// the SDK has no such switch there. What the Mac does instead is apply the chosen
    /// microphone and speaker before joining, as ``LiveKitCallEngine`` does. The overlap with
    /// a telephone call is still kept out by ``CallStack``, for the microphone's sake.
    ///
    /// ⚠️ IT EMITS ``RoomEngineEvent/failed(message:)`` AND THEN RETHROWS, the same
    /// contract `CallEngine.connect` documents.
    func connect(url: String, token: String) async throws {
        await devices.applySavedChoice()
        do {
            // ⛔ THE MICROPHONE IS **NOT** PUBLISHED ON THE JOIN, unlike the
            // softphone's `ConnectOptions(enableMicrophone: true)`. A phone call
            // where nobody can hear you is a broken call; a meeting you joined muted
            // is an ordinary meeting. ``ActiveRoomModel`` turns it on afterwards, and
            // only when the role and the OS permission both allow it.
            try await room.connect(url: url, token: token)
        } catch {
            continuation.yield(.failed(message: error.localizedDescription))
            throw error
        }
    }

    /// ⛔ IDEMPOTENT, AND EVERY LEAVE PATH DEPENDS ON IT. `Room.disconnect()` is
    /// non-throwing and absorbs a room that has already gone.
    func disconnect() async {
        await room.disconnect()
    }

    /// ⛔ THE POLARITY IS THE KOTLIN ONE (`enabled`), NOT THE CALLKIT ONE (`muted`).
    /// ``CallEngine/setMuted(_:)`` is stated the other way round because that is what
    /// the platform's own mute action carries; nothing here goes near CallKit, so the
    /// spelling that matches what a screen renders is the honest one.
    ///
    /// - Returns: what the SDK ACCEPTED, never what was asked. A refusal leaves the
    ///   caller holding the truth, which is the one direction that matters: the
    ///   alternative invites somebody to speak on a line nobody can hear.
    func setMicrophone(enabled: Bool) async -> Bool {
        do {
            try await room.localParticipant.setMicrophone(enabled: enabled)
            return enabled
        } catch {
            return !enabled
        }
    }

    /// ⛔ THE ONLY CAMERA PUBLISH IN THIS APPLICATION. The softphone has no camera
    /// command at all (and on iOS CallKit video is declined); rooms are
    /// the exception, and this line is it.
    ///
    /// - Returns: what the SDK accepted. See ``setMicrophone(enabled:)``.
    func setCamera(enabled: Bool) async -> Bool {
        do {
            try await room.localParticipant.setCamera(enabled: enabled)
            return enabled
        } catch {
            return !enabled
        }
    }

    // ⚠️ NO CAMERA FLIP AND NO SPEAKER PREFERENCE, UNLIKE iOS. A Mac has one camera facing
    // the person (iOS flips front and rear), and LiveKit's `isSpeakerOutputPreferred` is an
    // iOS audio-session setting with no macOS counterpart; the output picker replaces it.

    /// Who is in the room right now, and what they are publishing.
    ///
    /// ⛔ PULLED ON DEMAND RATHER THAN PUSHED THROUGH ``events``, AND THAT IS WHAT
    /// KEEPS THE EVENT STREAM `Sendable`. A participant's video track is an SDK
    /// object with no `Sendable` conformance to lean on; putting one in the stream
    /// would either not compile under Swift 6 strict concurrency or would need an
    /// `@unchecked` wrapper around a live media handle. So the stream carries only
    /// ``RoomEngineEvent/rosterChanged`` and the reader asks for the snapshot, on the
    /// main actor, where the tracks are about to be rendered anyway.
    ///
    /// ⛔ THE LOCAL PARTICIPANT IS NOT IN THIS LIST. The Kotlin engine's contract says
    /// the same, and the reason is double counting: a self tile drawn from the same
    /// source appears twice after a reconnect.
    func roster() -> [RoomParticipantSnapshot] {
        room.remoteParticipants.values.map(RoomEngine.snapshot)
    }

    /// The local camera track, for the self tile, or nil when nothing is publishing.
    func localCameraTrack() -> VideoTrack? {
        room.localParticipant.firstCameraVideoTrack
    }

    /// ⚠️ THE SDK'S OWN CLASSIFICATION FOR `isAgent`, NEVER AN IDENTITY PREFIX ALONE.
    /// The transcription Companion joins through the Agents framework with the agent
    /// kind and a default `agent-<jobId>` identity; the prefix is a fallback the web
    /// keeps for a retired browser-side participant. ``ActiveRoomModel`` applies both
    /// tests in the same order the web does.
    ///
    /// ⚠️ A BLANK NAME BECOMES nil, matching `LiveKitCallEngine`: an empty string
    /// would render as a participant whose name is one space wide.
    private static func snapshot(_ participant: RemoteParticipant) -> RoomParticipantSnapshot {
        let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoomParticipantSnapshot(
            identity: participant.identity?.stringValue ?? "",
            name: (name?.isEmpty ?? true) ? nil : name,
            isAgent: participant.kind == .agent,
            isMicrophoneEnabled: participant.isMicrophoneEnabled(),
            isSpeaking: participant.isSpeaking,
            audioLevel: Double(participant.audioLevel),
            video: participant.firstCameraVideoTrack
        )
    }
}

/// One remote participant, as much of them as the grid draws.
///
/// ⛔ FILE SCOPE, NOT NESTED IN ``RoomEngine``, for the reason `LiveKitCallEngine`
/// records: a helper nested inside a type that conforms to a protocol with associated
/// types can be picked up as the witness, and the error then surfaces somewhere else
/// entirely.
///
/// ⚠️ DELIBERATELY NOT `Sendable`. It holds a live SDK video track, and it is built
/// and read on the main actor only. See the ⛔ on ``RoomEngine/roster()``.
struct RoomParticipantSnapshot: Identifiable {
    /// ⚠️ THE SERVER-DERIVED IDENTITY, WHICH IS THE EVICTION KEY. LiveKit evicts only
    /// on a REPEATED identity, so this is what stops the same human appearing twice
    /// after a reconnect, and it is what the grid is keyed on.
    var id: String {
        identity
    }

    let identity: String
    let name: String?
    let isAgent: Bool
    /// ⚠️ MARKED IN THE GRID, because "why can I not hear them" is the most common
    /// question in a room and this is usually the answer.
    let isMicrophoneEnabled: Bool
    /// ⚠️ A SERVER-SENT SIGNAL, NOT A LOCAL MEASUREMENT. It arrives on the speaker
    /// update the SFU publishes, which is why ``RoomEngineEvent/speakersChanged`` exists:
    /// the value moves without anybody joining, leaving or publishing anything.
    let isSpeaking: Bool
    /// How loud they are right now, 0 to 1.
    ///
    /// ⛔ READ BY THE PERSONA PREVIEW AND BY NOTHING IN THE GRID, DELIBERATELY. An
    /// audition's whole question is "is the agent actually saying anything", and a
    /// meeting's is not, a per-tile level that redrew the grid every half second would
    /// cost a phone far more than it told anybody.
    let audioLevel: Double
    /// ⚠️ nil IS AN AUDIO-ONLY TILE, NEVER AN OMISSION. Camera-off is the normal way
    /// to be in a meeting; dropping those people would make the room look emptier
    /// than it is, which is the dangerous direction since it is what somebody checks
    /// before saying something private.
    let video: VideoTrack?
}

/// What a room session reports.
///
/// ⛔ VALUE TYPES ONLY, WITH NO HANDLE TO ANYTHING THE SDK OWNS, exactly as
/// ``CallEngineEvent`` requires of itself. The roster arrives as a signal rather than
/// as a payload; see the ⛔ on ``RoomEngine/roster()``.
enum RoomEngineEvent: Sendable, Equatable {
    /// ⚠️ ALSO THE RECOVERY SIGNAL after ``reconnecting``, so it is not only a
    /// first-connect event.
    case connected

    /// ⛔ A BANNER OVER A LIVE MEETING, NEVER A FAILURE AND NEVER A PHASE. A phone
    /// handing over between wifi and its radio reconnects routinely, and the SDK
    /// resumes the session itself; a UI that treated this as failed would tear down
    /// meetings that were about to survive.
    case reconnecting

    case disconnected(reason: String?)

    /// Somebody joined or left, or changed what they publish.
    case rosterChanged

    /// Who is speaking, and how loudly, has changed.
    ///
    /// ⛔ ITS OWN CASE RATHER THAN A ``rosterChanged``, AND THE SEPARATION IS THE POINT.
    /// The SFU publishes speaker updates continuously for the whole of a session, so
    /// folding them into the roster signal would rebuild a meeting's tile grid several
    /// times a second for a change no tile draws. The persona preview is the one reader:
    /// its level meter is the only thing on either screen that this moves.
    case speakersChanged

    case microphoneChanged(enabled: Bool)

    case cameraChanged(enabled: Bool)

    case failed(message: String?)
}

/// Turns `RoomDelegate` callbacks into ``RoomEngineEvent`` values.
///
/// ⛔ AN `NSObject` BECAUSE `RoomDelegate` IS AN `@objc` PROTOCOL WHOSE MEMBERS ARE
/// ALL `@objc optional`, AND THAT MAKES EVERY SIGNATURE HERE LOAD-BEARING IN A WAY
/// THE COMPILER CANNOT CHECK. An optional requirement whose selector does not match
/// is not an error: the method simply never fires, and the symptom is a room that
/// connects and then reports nothing at all. `LiveKitCallEngine`'s own bridge carries
/// the identical warning, and the four callbacks it shares with this one are copied
/// from it verbatim precisely so that a selector proven on the Mac once is proven for
/// both.
///
/// ⚠️ THE CALLBACKS ARE NONISOLATED AND TOUCH NOTHING BUT THE CONTINUATION.
/// `AsyncStream.Continuation` is `Sendable` and `yield` is safe from any thread, so
/// nothing here needs an actor hop and nothing here may grow one.
private final class RoomSessionBridge: NSObject, RoomDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<RoomEngineEvent>.Continuation

    init(continuation: AsyncStream<RoomEngineEvent>.Continuation) {
        self.continuation = continuation
    }

    /// ⛔ `.disconnected` IS DELIBERATELY NOT MAPPED HERE, matching the softphone's
    /// bridge. `didDisconnectWithError` is the callback that carries the reason and
    /// the one that ends the session; yielding a bare disconnect from here as well
    /// would race it, and whichever arrived first would win.
    @objc
    func room(
        _ room: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        switch connectionState {
        case .connected:
            continuation.yield(.connected)
        case .reconnecting:
            continuation.yield(.reconnecting)
        default:
            break
        }
    }

    @objc
    func room(_ room: Room, didStartReconnectWithMode mode: ReconnectMode) {
        continuation.yield(.reconnecting)
    }

    @objc
    func room(_ room: Room, didCompleteReconnectWithMode mode: ReconnectMode) {
        continuation.yield(.connected)
    }

    @objc
    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        continuation.yield(.failed(message: error?.localizedDescription))
    }

    /// ⚠️ A nil ERROR IS THE CLEAN DISCONNECT.
    @objc
    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        continuation.yield(.disconnected(reason: error?.localizedDescription))
    }

    /// ⚠️ THE SELECTOR IS COPIED FROM `RoomDelegate` VERBATIM, like every other one
    /// here. An `@objc optional` requirement whose selector does not match is not an
    /// error: the method simply never fires, and the symptom would be a preview whose
    /// level meter never moves while the agent is plainly talking.
    @objc
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        continuation.yield(.speakersChanged)
    }

    @objc
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        continuation.yield(.rosterChanged)
    }

    @objc
    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        continuation.yield(.rosterChanged)
    }

    /// ⛔ THE FOUR TRACK CALLBACKS ARE WHY A TILE APPEARS AT ALL. A participant who
    /// joins with the camera off and turns it on later produces no join event, only a
    /// subscribe; without these the grid would draw them as audio-only for the rest
    /// of the meeting.
    @objc
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        continuation.yield(.rosterChanged)
    }

    @objc
    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        continuation.yield(.rosterChanged)
    }

    @objc
    func room(
        _ room: Room,
        participant: Participant,
        trackPublication: TrackPublication,
        didUpdateIsMuted isMuted: Bool
    ) {
        continuation.yield(.rosterChanged)
    }

    /// ⚠️ THE LOCAL SIDE, AND IT IS WHAT MAKES THE TWO TOGGLES HONEST. The state
    /// mirrors what the SDK actually published rather than what was asked for.
    @objc
    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        continuation
            .yield(publication.kind == .video ? .cameraChanged(enabled: true) : .microphoneChanged(enabled: true))
    }

    @objc
    func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        let kind = publication.kind
        continuation.yield(kind == .video ? .cameraChanged(enabled: false) : .microphoneChanged(enabled: false))
    }
}
