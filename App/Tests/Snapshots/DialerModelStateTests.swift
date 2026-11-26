@testable import DistrictMac
import DistrictModel
import XCTest

/// The dialer's model up to the point a call would need a microphone: the entry, the recent
/// callbacks read and a placed call the denied microphone stops, answered by the service's
/// recorded responses (`contracts/`).
///
/// ⛔ NO CALL IS EVER DIALLED HERE. The harness's microphone is denied
/// (``ScreenSnapshotCase/SignedInApp``), so a placed call stops before the dial request.
@MainActor
final class DialerModelStateTests: XCTestCase {
    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (DialerModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "dialer.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = DialerModel(container: app.container, workspaceId: app.workspaceId, role: role)
        return (model, transport)
    }

    func testTheRecentCallbacksLoad() async {
        let (model, transport) = await model(ScreenRules.loaded)
        await model.loadCallbacks()
        guard case .ready = model.callbacks else {
            return XCTFail("callbacks not ready: \(model.callbacks) \(transport.sentRequests)")
        }
    }

    func testFailedCallbacksAreTheirOwnState() async {
        let (model, _) = await model(ScreenRules.failing)
        await model.loadCallbacks()
        guard case .failed = model.callbacks else {
            return XCTFail("callbacks should have failed: \(model.callbacks)")
        }
    }

    /// ⚠️ AN INCOMPLETE NUMBER IS NOT PLACED: the length check is shown instead.
    func testAnIncompleteNumberShowsTheLengthCheck() async {
        let (model, _) = await model(ScreenRules.loaded)
        model.onEntryChange("416")
        XCTAssertFalse(model.lengthChecked)
        XCTAssertFalse(model.canPlaceCall)
        model.placeCall()
        XCTAssertTrue(model.lengthChecked)
        XCTAssertNil(model.call)
        model.onEntryChange("4165")
        XCTAssertFalse(model.lengthChecked)
        model.checkLength()
        XCTAssertTrue(model.lengthChecked)
    }

    /// ⛔ A DENIED MICROPHONE STOPS THE CALL BEFORE ANY DIAL REQUEST, and the claim is released.
    func testADeniedMicrophoneStopsThePlacedCallBeforeTheDial() async {
        let (model, transport) = await model(ScreenRules.loaded)
        model.onEntryChange("+1 416 555 1234")
        XCTAssertTrue(model.canPlaceCall, "\(model.destination)")
        model.placeCall()
        await waitUntil(timeout: 5, state: "\(String(describing: model.refusal)) placing=\(model.placing)") {
            model.refusal != nil && !model.placing
        }
        XCTAssertNil(model.call)
        XCTAssertFalse(model.calls.hasLiveCall)
        XCTAssertFalse(transport.sentRequests.contains { $0.contains("/dial") })
        // Nothing to hang up, and nothing ended to dismiss.
        await model.hangUp()
        model.dismissEndedCall()
        await model.endForSystem()
        XCTAssertNil(model.call)
    }

    func testAReadOnlyRoleCannotPlaceACall() async {
        let (model, _) = await model(ScreenRules.loaded, role: nil)
        XCTAssertFalse(model.canDial)
        model.onEntryChange("+1 416 555 1234")
        XCTAssertFalse(model.canPlaceCall)
        model.placeCall()
        XCTAssertFalse(model.placing)
        XCTAssertNil(model.call)
    }
}
