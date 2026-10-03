import Foundation

/// The microphone question an outbound call asks before anything else does.
///
/// ⛔ ITS OWN FILE FOR THE REASON `DialerTasks.swift` IS ONE: `DialerModel.swift` sits near the
/// ceiling and `swiftlint --strict` promotes the 500-line `file_length` warning to an error.
extension DialerModel {
    /// Ask for the microphone, then dial.
    ///
    /// ⛔ ASKED BEFORE THE CARRIER, AND THE ORDER MATTERS. The media join publishes the microphone
    /// and the engine refuses to record without an existing grant, so a dial that asked nothing
    /// would fail only at the join: after `POST /api/district/calls/dial` had already rung the
    /// callee on a real, billed line. A refusal here places nothing at all.
    ///
    /// ⚠️ THE CLAIM IS ALREADY HELD WHILE THE ALERT IS UP, so ``CallStack/hasLiveCall`` is true for
    /// those seconds: a room cannot be joined and a ring is not shown. That is the interval a press
    /// on Call has always claimed; the alert only lengthens it, once per install.
    ///
    /// ⚠️ NO START WATCHDOG, UNLIKE iOS, which waits for CallKit to perform its start action and
    /// gives up on one that never comes. Here the dial follows the answer directly.
    func startAfterMicrophone(attempt: UUID) async {
        guard await calls.microphone.request() else {
            await abandonStart(attempt: attempt, because: Self.microphoneOff)
            return
        }
        await beginDial(attempt: attempt)
    }
}
