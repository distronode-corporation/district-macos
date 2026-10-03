import Foundation

/// Whether this Mac is in a position to answer at all.
///
/// ⛔ THREE STATES, NOT A `Bool`, BECAUSE AN ANSWER FROM THE NOTIFICATION OF A CLOSED
/// APP ARRIVES BEFORE THE SESSION GATE HAS RESOLVED. ``unknown`` is the ordinary
/// state for the first moments of that launch: the ring stands, and the answer is
/// only refused once the gate says there is nothing to answer WITH. A `Bool`
/// defaulting to false would end that ring before anyone could reach it.
///
/// ⚠️ ``AuthPhase/unavailable(_:)`` MAPS TO ``unusable`` EVEN THOUGH THE SESSION
/// MAY BE INTACT. That phase means "we could not check", a locked Keychain, a
/// throttled refresh, and in every one of those cases the answer request has no
/// bearer to send, so it would 401 and present as a refusal anyway. Ending the
/// call honestly is better than a spinner that resolves into an error.
enum IncomingCallSession: Equatable {
    case unknown
    case usable
    case unusable
}
