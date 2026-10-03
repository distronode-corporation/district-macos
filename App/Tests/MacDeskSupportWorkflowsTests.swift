import DistrictData
@testable import DistrictMac
import DistrictModel
import XCTest

/// The pure decisions behind the Desk, Support and Workflows screens.
///
/// ⚠️ MAC ONLY: district-ios tests only the Desk's single-flight create
/// (``DeskModelCreateTests``). Every expectation here is the behaviour the iOS source
/// documents beside the code, pinned so a later port cannot drift from it unnoticed.
final class MacDeskSupportWorkflowsTests: XCTestCase {
    // MARK: - Desk

    /// ⛔ `waiting` IS WORDED FROM THE CUSTOMER'S SIDE, and a status this build predates is
    /// shown as itself rather than painted "Resolved".
    func test_MAC_DESK_1_statusesAreWordedAndUnknownOnesShownAsThemselves() {
        XCTAssertEqual(DeskView.label(forWire: "open"), "Open")
        XCTAssertEqual(DeskView.label(forWire: "waiting"), "Waiting on customer")
        XCTAssertEqual(DeskView.label(forWire: "resolved"), "Resolved")
        XCTAssertEqual(DeskView.label(forWire: "escalated"), "escalated")
    }

    func test_MAC_DESK_2_anUnmodelledStatusIsNeutral() {
        XCTAssertEqual(DeskView.tone(forWire: "open"), .warning)
        XCTAssertEqual(DeskView.tone(forWire: "waiting"), .info)
        XCTAssertEqual(DeskView.tone(forWire: "resolved"), .success)
        XCTAssertEqual(DeskView.tone(forWire: "escalated"), .neutral)
    }

    // MARK: - Support

    /// ⛔ A REFUSED RESUBMIT DISARMS THE CONTROL: the only way on is a fresh look at the
    /// thread, never a second identical write.
    func test_MAC_SUPPORT_1_aRefusedRepeatDisarmsAndAnAllowedOneDoesNot() {
        let failure = FailureText(message: "No.", action: .none)
        let refused = SupportWriteState.failed(failure, .refused)
        XCTAssertFalse(refused.isArmed)
        XCTAssertTrue(refused.refusedRepeat)
        XCTAssertEqual(refused.notice, "No.")

        let allowed = SupportWriteState.failed(failure, .allowed)
        XCTAssertTrue(allowed.isArmed)
        XCTAssertFalse(allowed.refusedRepeat)
    }

    func test_MAC_SUPPORT_2_aSendInFlightIsNotArmedAndSaysNothing() {
        XCTAssertFalse(SupportWriteState.sending.isArmed)
        XCTAssertTrue(SupportWriteState.sending.isSending)
        XCTAssertNil(SupportWriteState.sending.notice)
        XCTAssertTrue(SupportWriteState.idle.isArmed)
    }

    /// The three things a new request can come back as, each in its own words.
    func test_MAC_SUPPORT_3_eachFilingOutcomeHasItsOwnSentence() {
        let filed = SupportFilingCopy.notice(for: .filed(issueKey: "DS-1"))
        let deduplicated = SupportFilingCopy.notice(for: .deduplicated)
        let pending = SupportFilingCopy.notice(for: .pending)
        XCTAssertEqual(Set([filed, deduplicated, pending]).count, 3)
        XCTAssertEqual(filed, SupportCopy.filed)
    }

    // MARK: - Workflows

    /// ⚠️ A TRIGGER THIS BUILD DOES NOT KNOW IS SHOWN AS ITS WIRE VALUE, never dropped.
    func test_MAC_WORKFLOWS_1_triggersAreLabelledAndUnknownOnesKept() {
        XCTAssertEqual(WorkflowTrigger.label("call_ended_unanswered"), "After a missed call")
        XCTAssertEqual(WorkflowTrigger.label("brand_new_trigger"), "brand_new_trigger")
    }

    func test_MAC_WORKFLOWS_2_runAndActionTonesAreNeutralWhenUnmodelled() {
        XCTAssertEqual(Tone.forRunStatus("success"), .success)
        XCTAssertEqual(Tone.forRunStatus("partial"), .warning)
        XCTAssertEqual(Tone.forRunStatus("failed"), .danger)
        XCTAssertEqual(Tone.forRunStatus("queued"), .neutral)
        XCTAssertEqual(Tone.forActionOutcome("ok"), .success)
        XCTAssertEqual(Tone.forActionOutcome("skipped"), .neutral)
    }
}
