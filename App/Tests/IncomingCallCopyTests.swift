@testable import DistrictCall
@testable import DistrictMac
import XCTest

// Ported from district-ios `App/Tests/IncomingCallCopyTests.swift` (see PORTING.md): the
// sentence half only. The iOS file's first class pins `endedReason(for:)`, the
// `CXCallEndedReason` CallKit is told, which this app does not have.

/// The inbound half of the ended-call wording, pinned.
///
/// ⛔ THE DIALLER'S TESTS DO NOT COVER THIS SCREEN: the two machines are separate
/// models. If `sentence(for:)` reached the unattributed one-argument `word(for:)`,
/// an incoming call ending `.hungUpLocally` would render "Call ended · you hung up"
/// whether or not a person had touched the button.
@MainActor
final class IncomingCallSentenceTests: XCTestCase {
    /// ⚠️ `@testable import DistrictCall` IS WHAT MAKES THIS POSSIBLE, and it is the
    /// idiom the package's own suite already uses. ``IncomingCallState/phase`` is
    /// `public internal(set)`, so a state in a chosen phase cannot be built through
    /// the public API at all; the alternative is driving ``IncomingCallController``
    /// through a real event sequence, which would couple a COPY test to the reducer's
    /// transition table and fail for reasons that have nothing to do with wording.
    private func ended(_ reason: CallEndReason) -> IncomingCallState {
        var state = IncomingCallState()
        state.phase = .ended(reason)
        return state
    }

    /// ⛔ THE HEADLINE, AND THE EXACT STRING THAT WAS WRONG.
    func testHungUpLocallyWithoutAttributionDoesNotBlameTheOperator() {
        let sentence = IncomingCallCopy.sentence(for: ended(.hungUpLocally), endedByOperator: false)
        XCTAssertEqual(sentence, "Call ended")
        XCTAssertFalse(sentence.contains("you hung up"))
    }

    func testHungUpLocallyByTheOperatorIsStillSaid() {
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: ended(.hungUpLocally), endedByOperator: true),
            "Call ended · you hung up"
        )
    }

    /// ⚠️ EVERY OTHER REASON IS INDIFFERENT TO THE FLAG, exactly as on the outbound
    /// screen: the withholding must not widen to endings the reducer CAN attribute.
    func testOtherReasonsAreUnaffectedByAttribution() {
        let cases: [(CallEndReason, String)] = [
            (.remoteHungUp, "Call ended · they hung up"),
            (.callerCancelled, "Call ended · the caller hung up"),
            (.ringTimedOut, "Call ended · nobody answered"),
            (.declined, "Call ended · declined"),
        ]
        for (reason, expected) in cases {
            for attributed in [true, false] {
                XCTAssertEqual(
                    IncomingCallCopy.sentence(for: ended(reason), endedByOperator: attributed),
                    expected,
                    "\(reason) should read the same either way"
                )
            }
        }
    }

    /// ⚠️ MAC ONLY. A ring the CALL ended (the socket said `call_ended`) is recorded by the
    /// reducer as a timeout and worded as the caller hanging up, with no new sentence.
    func test_MAC_RING_ENDED_BY_CALL_readsAsTheCallerHangingUp() {
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: ended(.ringTimedOut), endedByOperator: false, ringEndedByCall: true),
            "Call ended · the caller hung up"
        )
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: ended(.ringTimedOut), endedByOperator: false, ringEndedByCall: false),
            "Call ended · nobody answered"
        )
        XCTAssertEqual(
            IncomingCallCopy.sentence(for: ended(.declined), endedByOperator: false, ringEndedByCall: true),
            "Call ended · declined",
            "only the timeout exit is reworded"
        )
    }
}
