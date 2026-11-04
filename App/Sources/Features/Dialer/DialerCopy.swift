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
    ///
    /// ⛔ A +1 TOLL-FREE NUMBER RINGS NO ONE COUNTRY, AND THE LINE SAYS SO, as the web
    /// dialler does (`ringsNoCountry`; Sean, 2026-11-04, GitLab #2). ``DialPlan`` keeps the
    /// +1 country on the button for 800, 833 … 888, because the flag is where the next digits
    /// are read, but "Rings Canada" under a 1-800 number would claim a country it does not have.
    /// See ``tollFreeNumber(_:)`` for when it is said.
    static func destinationLine(_ reading: DialPlan.Reading) -> String? {
        if let number = tollFreeNumber(reading) {
            return ringsNoCountry(number)
        }
        guard reading.status == .ready else {
            // ⚠️ A `+` and three digits that name no country is already worth saying.
            let unknown = reading.namedItsCountry && reading.iso == nil && reading.national.count > 3
            return unknown && reading.status == .typing ? destinationUnrecognised : nil
        }
        guard let iso = reading.iso else { return destinationUnrecognised }
        return rings(DialPlan.name(iso), reading.international)
    }

    /// The number a +1 toll-free line shows, or nil when the reading is not one.
    ///
    /// ⚠️ THE WEB'S TIMING, NOT THE REST OF THIS LINE'S: said from 8 digits with the calling code
    /// (``DialEntry/minimumDigits``) up to 15, where the web's `resolveDialEntry` reads a number as
    /// `ready`, so a toll-free number still short of its ten digits already says it has no country,
    /// beside Call being off. Grouped only once it is whole; before that the bare `+1800…`, the
    /// web's rule that a half-grouped number reads as a real one.
    static func tollFreeNumber(_ reading: DialPlan.Reading) -> String? {
        guard reading.callingCode == "1", DialPlan.isNANPTollFree(reading.nationalNumber) else { return nil }
        let total = reading.callingCode.count + reading.nationalNumber.count
        guard total >= DialEntry.minimumDigits, total <= DialEntry.maximumDigits else { return nil }
        return reading.status == .ready ? reading.international : "+1" + reading.nationalNumber
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
