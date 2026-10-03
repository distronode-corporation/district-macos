/// A live meeting room, as the CALL path needs to see one.
///
/// ⛔ IT EXISTS SO THE OVERLAP GUARD POINTS BOTH WAYS. `ActiveRoomModel` refuses to
/// join while a telephone call is live, but the dangerous direction is the other
/// one: a guard on `CallStack.onSystemRequest == nil` sees only another TELEPHONE
/// CALL, not a room. Without this seam an operator in a meeting with the microphone
/// live could answer a customer call and have `LiveKitCallEngine.connect` take the
/// audio session while the room's own microphone track was never muted: the meeting
/// hears the whole private call and the caller hears the meeting, in both directions
/// at once. ⚠️ On a Mac there is no `AVAudioSession` to fight over, but there is one
/// microphone, and the breach is the same.
///
/// ⛔ A PROTOCOL RATHER THAN THE MODEL, FOR THE REASON ``CallStack/engine`` IS
/// EXPOSED AS ``CallEngine``. The platform tier must not be able to reach a LiveKit
/// symbol or a feature type through this seam, and `RoomEngine` imports the SDK.
///
/// ⚠️ `AnyObject` BECAUSE THE CLAIM IS AN IDENTITY. ``CallStack`` releases a claim
/// only for the object that holds it, so a model that already yielded cannot
/// release a later model's room out from under it.
@MainActor
protocol RoomAudio: AnyObject, Sendable {
    /// Give up this device's audio: disconnect the room, and say on screen why.
    ///
    /// ⛔ LEAVE, NOT MUTE, AND THE CHOICE IS ARGUED ON ``RoomAudioYield``.
    ///
    /// ⚠️ AWAITED BY THE CALLER, so the room is gone before the call's engine is
    /// built. See ``CallStack/beginCall()``.
    func yieldAudio(_ reason: RoomAudioYield) async
}

/// Why a room is being asked to give up this device's audio.
///
/// ⛔ THE OPERATOR IS ALWAYS TOLD WHICH ONE HAPPENED, WHICH IS THE WHOLE REASON
/// THIS IS AN ENUM RATHER THAN A BARE CALL. A meeting that vanishes with no
/// sentence is the "never render a failure as an absence" rule broken in the one
/// place it costs the most: the person is mid-conversation with other people.
enum RoomAudioYield: Sendable, Equatable {
    /// A telephone call took the audio.
    ///
    /// ⛔ THE CALL WINS AND THE ROOM YIELDS, WHICH IS THE OPPOSITE OF THE OUTBOUND
    /// RULE NEXT DOOR, AND BOTH ARE DELIBERATE. An OUTBOUND dial is a press: the
    /// operator is right there, so it is refused with a sentence naming the room
    /// and nothing is torn down. An INBOUND call is revenue arriving from someone
    /// who cannot be told anything: silently refusing it, or ringing a handset that
    /// then answers into a meeting, are both worse than ending the meeting. So the
    /// call is answered and the room is given up.
    ///
    /// ⛔ AND IT IS A FULL DISCONNECT RATHER THAN A MUTE. Muting the room's
    /// microphone would stop the private call bleeding INTO the meeting and would
    /// leave the meeting's audio playing into the call, which is the same breach
    /// wearing one direction instead of two. Leaving the room is the only act that
    /// restores a single owner.
    ///
    /// ⚠️ IT HAPPENS AT THE ANSWER, NEVER AT THE RING. A ring costs the room
    /// nothing (the ring panel takes no audio device), so tearing a meeting down for
    /// a call the operator then declines would be a defect of its own.
    case telephoneCall

    /// The signed-in shell that draws the room screen has gone.
    ///
    /// ⛔ A SIGN-OUT DESTROYS THE WHOLE SHELL, SO THE MEETING WOULD OTHERWISE RUN ON
    /// WITH NO SCREEN AND NO CONTROLS: a live microphone and camera while the app
    /// shows a sign-in form.
    case sessionEnded

    /// The app switched to a different workspace.
    ///
    /// ⛔ A ROOM BELONGS TO THE WORKSPACE THAT MINTED ITS TOKEN. A ring notification
    /// or a Universal Link naming another tenant puts the shell back on its loading
    /// state, which renders instead of the tabs and destroys the room screen with
    /// them, so the same gap applies.
    case workspaceChanged

    /// The Mac is going to sleep, or the app is quitting.
    ///
    /// ⚠️ MAC ONLY. A sleeping Mac drops its network, so the meeting would end anyway,
    /// and a meeting that came back on wake with the microphone live would be a
    /// surprise nobody asked for. It is left and offered back, like the others.
    case sleep
}
