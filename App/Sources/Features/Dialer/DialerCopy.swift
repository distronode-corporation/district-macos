import DistrictCall
import Foundation

/// Every sentence the dialer says.
///
/// ⚠️ ITS OWN FILE RATHER THAN AN EXTENSION AT THE BOTTOM OF `DialerModel.swift`, AND
/// THAT IS A LINT CEILING RATHER THAN A DESIGN STATEMENT, the same call ``OverviewEntry``
/// makes, for the same reason. `swiftlint --strict` promotes the `file_length` WARNING at
/// 500 lines to an error, and the model crosses it with this block in it.
///
/// ⛔ THE THREE REFUSAL STRINGS ARE FALLBACKS, NOT THE COPY. Every coded refusal shows the
/// SERVER'S own sentence when there is one, because the remedies differ and the dormancy
/// message is the only place the 100-day window and the reactivation instruction are
/// stated at all. These are what a blank message degrades to. See the ⛔ on ``DialOutcome``.
extension DialerModel {
    /// ⚠️ THE SERVER'S SENTENCE WHEN THERE IS ONE. Blank counts as absent, which is the
    /// shared normalisation rule ``ApiErrorEnvelope`` follows.
    static func refusalText(_ message: String?, fallback: String) -> FailureText {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FailureText(message: trimmed.isEmpty ? fallback : trimmed, action: .none)
    }

    /// ⛔ NOT RETRYABLE. A second tap places a second call
    /// or meets the identical refusal; see the ⛔ on ``FailureText/Action``.
    static var busy: FailureText {
        FailureText(message: busyMessage, action: .none)
    }

    /// ⛔ NOTHING WAS PLACED, AND THE SENTENCE SAYS THAT BEFORE IT SAYS WHY. A refused microphone is
    /// answered before the carrier hears of the call (see ``startAfterMicrophone(attempt:)``), so there
    /// is no call to end and nothing billed. It names the one remedy there is: macOS does not show the
    /// question a second time once somebody said no.
    /// ⚠️ "System Settings" WHERE iOS SAYS "Settings": the Mac's app is called System Settings.
    static var microphoneOff: FailureText {
        FailureText(message: microphoneOffMessage, action: .none)
    }

    /// ⛔ THE ROOM SIDE OF THE SAME REFUSAL ``RoomsCopy/busyWithCall`` MAKES, AND THE
    /// PAIR IS THE POINT: one process owns one `AVAudioSession`, so whichever surface
    /// is asked SECOND says so. Without this half, a dial from inside a live meeting
    /// would simply be allowed.
    ///
    /// ⚠️ IT NAMES THE REMEDY RATHER THAN THE MECHANISM. "Leave the room" is something
    /// the operator can do; "two audio owners" is not.
    ///
    /// ⛔ AN INBOUND CALL IS NOT REFUSED THIS WAY AND MUST NEVER BE. It arrives from
    /// somebody who cannot be shown a sentence, so the room yields to it instead, see
    /// the ⛔ on ``RoomAudioYield/telephoneCall``.
    static var inRoom: FailureText {
        FailureText(message: inRoomMessage, action: .none)
    }

    /// The line under the field: where the call rings and the whole number that is sent.
    ///
    /// ⛔ THIS SENTENCE IS THE GUARD AGAINST A WRONG-COUNTRY DIAL (see the ⛔ at the top
    /// of `DialerEntry.swift`). "Rings Switzerland · +41 65 550 12 34" is what the operator
    /// reads in the second before pressing Call, and the number in it is exactly the one
    /// the dial API receives.
    ///
    /// ⚠️ AN UNKNOWN CODE SAYS SO PLAINLY RATHER THAN GUESSING. Naming the wrong
    /// country is worse than naming none, because a wrong name is read as
    /// confirmation. It stays dialable, as it was: see ``DialRegion/unrecognised``.
    ///
    /// ⚠️ nil UNTIL THE NUMBER IS COMPLETE, when there is nothing to send yet; the flag on
    /// the button already names the country while the digits are being typed.
    static func destinationLine(_ reading: DialPlan.Reading) -> String? {
        guard reading.status == .ready else {
            // ⚠️ A `+` and three digits that name no country is already worth saying.
            let unknown = reading.namedItsCountry && reading.iso == nil && reading.national.count > 3
            return unknown && reading.status == .typing ? destinationUnrecognised : nil
        }
        guard let iso = reading.iso else { return destinationUnrecognised }
        return rings(DialPlan.name(iso), reading.international)
    }

    /// Why the Call button is off, in the operator's terms, or nil when there is nothing
    /// to correct.
    ///
    /// ⚠️ ``DialPlan/Status/empty`` RETURNS nil because the entry hint already occupies
    /// that moment, and a number still being typed is not a mistake.
    ///
    /// ⛔ A WRONG LENGTH IS SAID ONLY ONCE THE OPERATOR STOPS (`lengthChecked`: the field
    /// lost focus or Return was pressed), as the web dialler does (MR !102). Every
    /// ten-digit number passes through eight and nine digits on the way, so a sentence
    /// said while typing would flash on every number; until then Call is simply off. The
    /// next keystroke clears it (``DialerModel/onEntryChange(_:)``). `+4165550123` (eight
    /// digits after `+41`, and every Swiss number has nine) is the case it explains.
    static func entryProblem(_ reading: DialPlan.Reading, lengthChecked: Bool) -> String? {
        switch reading.status {
        case .empty, .ready:
            nil
        case .needsCountry:
            entryNeedsCountry
        // ⚠️ AN INCOMPLETE NUMBER IS A WRONG LENGTH ONLY WITH A COUNTRY AND DIGITS TO MEASURE:
        // a lone `+`, a trunk `0` or an unknown code (said by the line above) is not.
        case .typing:
            lengthChecked && reading.iso != nil && !reading.nationalNumber.isEmpty ? entryWrongLength : nil
        case .tooLong:
            lengthChecked ? entryWrongLength : nil
        // ⛔ THE ONLY REFUSAL HERE THAT IS NOT A CORRECTION. Every other case tells the
        // operator how to fix the number; this one tells them to leave the app, because
        // District cannot place an emergency call and must not pretend it might. Naming
        // somewhere that can place the call is the load-bearing half.
        // ⚠️ "a phone" WHERE iOS SAYS "the Phone app": a Mac has no Phone app to name, and
        // the hand-off has to point somewhere that can actually place the call.
        case .emergency:
            entryEmergencyNumber
        }
    }

    /// What an empty field says: how to type a number in the country on the button, or
    /// to choose one.
    static func entryHint(country: String?) -> String {
        guard let country else { return entryHintNone }
        return entryHintLocal(DialPlan.name(country))
    }
}
