import DistrictCall
@testable import DistrictMac
import Foundation
import XCTest

/// A call asks for the microphone before it can fail for want of one.
///
/// ⚠️ EVERY CONTAINER HERE POINTS AT `https://calls.invalid`. The `.invalid` TLD is reserved and never
/// resolves, so a path that did reach the network fails on this Mac and no credential is sent
/// anywhere. ⛔ That is what keeps the dial tests honest about a
/// telephone: nothing here can ring one, even if the model under test regressed into dialling.
///
/// ⚠️ THE MODELS RUN THEIR WORK IN TASKS THEY OWN AND EXPOSE NO COMPLETION TO AWAIT, so each test polls
/// for the state it expects, with a bound, rather than sleeping a fixed time and hoping.
@MainActor
final class MicrophoneAccessTests: XCTestCase {
    private let unreachable = URL(string: "https://calls.invalid")!
    private let dialable = "+14165550100"

    // MARK: - Dialling

    /// ⛔ A REFUSED MICROPHONE PLACES NOTHING. The dial route is reached only from
    /// `beginDial(attempt:)`, which runs only after a grant. A refusal that ends with no session
    /// and no claim therefore dialled nothing.
    func testADeniedMicrophoneDialsNothingAndSaysWhy() async {
        let microphone = FakeMicrophoneAccess(status: .denied)
        let container = AppContainer(baseURL: unreachable, microphone: microphone)
        let model = DialerModel(container: container, workspaceId: "ws_1", role: .agency)
        model.onEntryChange(dialable)
        XCTAssertTrue(model.canPlaceCall, "the fixture number must be dialable or this test proves nothing")

        model.placeCall()
        await waitUntil { microphone.requestCount == 1 && !model.placing }

        XCTAssertEqual(model.refusal?.message, DialerModel.microphoneOff.message)
        XCTAssertNil(model.call, "a session exists only once the dial goes out, which follows a grant")
        XCTAssertFalse(container.callStack.hasLiveCall, "a refusal must drop the claim on the call stack")
    }

    /// ⚠️ A GRANT CHANGES NOTHING DOWNSTREAM: the dial goes out, and whatever the unresolvable host
    /// then answers, the reason the call did not proceed is never the microphone.
    ///
    /// ⚠️ MAC: iOS hands the start to CallKit here and pins its watchdog; a Mac dials straight after
    /// the grant, so the attempt ends at the unresolvable host.
    func testAGrantedMicrophoneDialsAndEndsWithTheNetworksReason() async {
        let microphone = FakeMicrophoneAccess(status: .granted)
        let container = AppContainer(baseURL: unreachable, microphone: microphone)
        let model = DialerModel(container: container, workspaceId: "ws_1", role: .agency)
        model.onEntryChange(dialable)

        model.placeCall()
        XCTAssertTrue(model.placing, "the press is placing until the microphone answers")
        XCTAssertTrue(container.callStack.softphone === model, "the press registers the model that owns it")
        await waitUntil(timeout: 15, state: "placing=\(model.placing) refusal=\(String(describing: model.refusal))") {
            microphone.requestCount == 1 && !model.placing && model.call == nil && !container.callStack.hasLiveCall
        }

        XCTAssertNotNil(model.refusal, "with no carrier reachable the attempt must end with a reason")
        XCTAssertNotEqual(model.refusal?.message, DialerModel.microphoneOff.message)
        XCTAssertNil(DialerModel.attached(to: container.callStack, workspaceId: "ws_1"), "a refused dial")
    }

    // MARK: - Answering

    // ⚠️ THE AT-ANSWER CASE IS `MacIncomingCallModelTests.test_MAC_INCOMING_12`, without iOS's
    // foreground condition: every Mac answer is a press with the app able to show the alert.
}
