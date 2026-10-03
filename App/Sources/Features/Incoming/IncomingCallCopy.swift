import DistrictCall
import Foundation

/// Every sentence the ringing surface says.
///
/// ⚠️ ITS OWN FILE FOR THE REASON ``DialerCopy`` IS ONE: `swiftlint --strict`
/// promotes the 500-line `file_length` warning to an error, and the model does not
/// have room for this block.
///
/// ⛔ THE RING CARRIES IDENTIFIERS ONLY. No number, no name, no token: neither the
/// telemetry event nor the push names the caller, and the answer route returns a join
/// credential rather than a caller.
///
/// ⚠️ THE APP ASKS AFTERWARDS INSTEAD. ``IncomingCallIdentity`` resolves the caller
/// over the authenticated API once the call has been reported, so the line names the
/// caller when the workspace's own records answered, and names the workspace being
/// called until then. That placeholder is the honest answer for the first second of
/// every ring, for a handset that has not been unlocked since it booted, and for a
/// number nobody has ever saved.
enum IncomingCallCopy {
    /// ⚠️ THE WORKSPACE NAME IS APPENDED ONLY WHEN THE APP HAPPENS TO HOLD ONE. An
    /// answer from the notification of a closed app has not loaded the workspace list
    /// yet, so the name is a bonus rather than a guarantee.
    ///
    /// ⚠️ THE WORKSPACE STAYS ON THE LINE EVEN ONCE THE CALLER IS KNOWN. An
    /// operator holding two businesses needs to know WHICH of their lines rang
    /// before they pick up, and a caller's name does not tell them that.
    ///
    /// - Parameter caller: ``IncomingCallIdentity/displayLine``, or nil while the
    ///   lookup is out or after it resolved nothing. ⚠️ Blank is treated as nil:
    ///   the identity type already refuses to produce one, and a lead of `""` would
    ///   render a line that opens with the separator.
    static func callerLine(caller: String?, workspaceName: String?) -> String {
        let known = caller?.trimmingCharacters(in: .whitespaces) ?? ""
        let lead = known.isEmpty ? "Incoming call" : known
        guard let workspaceName, !workspaceName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return lead
        }
        return "\(lead) · \(workspaceName)"
    }

    /// ⛔ THE MESSAGE WINS OVER THE PHASE ON AN ENDED CALL, which is the same call
    /// the Kotlin screen makes: "the caller hung up" is more useful than the word
    /// "Ended", and the two are never both worth showing.
    ///
    /// - Parameter endedByOperator: whether the end came from THIS SCREEN'S hang-up
    ///   button. ⛔ Supplied by the model, never derived from the state: the reducer
    ///   feeds `.hangUpPressed` from ``IncomingCallModel/hangUp()`` AND from
    ///   ``IncomingCallModel/endForSystem()``, so ``CallEndReason/hungUpLocally`` means "ended on this
    ///   device" and nothing narrower, the same fact the outbound screen carries.
    ///
    /// - Parameter ringEndedByCall: ⚠️ MAC ONLY, see ``IncomingCallModel/ringEndedByCall``:
    ///   the ring ended because the call did, which the reducer records as a timeout.
    ///   It is worded as the caller hanging up, the iOS sentence for a caller gone at
    ///   the answer, so no new copy is introduced.
    static func sentence(
        for state: IncomingCallState,
        endedByOperator: Bool,
        ringEndedByCall: Bool = false
    ) -> String {
        switch state.phase {
        case .idle, .ringing:
            "Ringing…"
        // ⛔ ITS OWN SENTENCE RATHER THAN A SPINNER OVER "Ringing…". The answer
        // round trip plus a room join is a real gap to fill, and the buttons have
        // gone by now; a screen still saying "Ringing…" reads as frozen.
        case .answering:
            "Answering…"
        case .inCall:
            "Connected · \(InCallCopy.duration(state.media?.elapsedSeconds ?? 0))"
        case let .ended(reason):
            InCallCopy.endedSentence(
                reason: ringEndedByCall && reason == .ringTimedOut ? .callerCancelled : reason,
                endedByOperator: endedByOperator,
                seconds: state.media?.elapsedSeconds ?? 0,
                // ⛔ `media != nil` IS THE ANSWERED TEST, AND IT IS THE SAME FACT
                // ``IncomingCallState/media`` DOCUMENTS: it is nil until the room
                // is joined. A call that ended while ringing must not read
                // "Lasted 0:00", which says the opposite of "nobody picked up".
                answered: state.media != nil
            )
        }
    }

    /// The ring panel's title. ⚠️ MAC ONLY (iOS rings in CallKit's screen), and
    /// district-linux's ring heading, word for word.
    static let panelTitle = "Incoming call"

    /// The notice under the Answer button.
    ///
    /// ⚠️ SAID BEFORE THE SYSTEM ASKS, like the dialer's, so the microphone prompt has a visible
    /// reason. The app asks at Answer (``IncomingCallModel/prepareMicrophoneForAnswer()``),
    /// and a request with no explanation is the one people deny permanently.
    static let answerNotice = "Answering turns on your microphone."
}
