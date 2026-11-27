@testable import DistrictMac
import DistrictModel
import XCTest

/// The scheduling section's own model driven through its status read and the enable, answered
/// by the service's recorded responses (`contracts/`). The hand-off is pinned in
/// ``SchedulingHandOffTests``.
@MainActor
final class SchedulingModelStateTests: XCTestCase {
    private static let api = "/api/district"

    private static func status(_ name: String) -> FixtureTransport.Rule {
        .get("\(api)/scheduling/status", .fixture("mobile/\(name)"))
    }

    private static func enable(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/scheduling/enable", reply)]
    }

    private func model(_ rules: [FixtureTransport.Rule]) async -> (SchedulingModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "scheduling.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        return (SchedulingModel(container: app.container, workspaceId: app.workspaceId), transport)
    }

    func testTheReadyStatusLoadsAndIsNotProvisioning() async {
        let (model, _) = await model(ScreenRules.loaded)
        XCTAssertFalse(model.isProvisioning)
        await model.load()
        guard case .ready = model.state else {
            return XCTFail("should be ready: \(model.state)")
        }
        XCTAssertFalse(model.isProvisioning)
    }

    func testAProvisioningTenantIsProvisioning() async {
        let (model, _) = await model([Self.status("district-scheduling-status-provisioning.json")] + ScreenRules.loaded)
        await model.load()
        XCTAssertTrue(model.isProvisioning, "\(model.state)")
    }

    func testAFailedReadIsTheFailureState() async {
        let (model, _) = await model(ScreenRules.failing)
        await model.load()
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
    }

    /// ⛔ A POLL THAT FAILS IS SILENT: the state it found stays on screen.
    func testAFailedPollKeepsTheState() async {
        let (model, _) = await model(ScreenRules.failing)
        await model.load(.poll)
        guard case .loading = model.state else {
            return XCTFail("a failed poll should change nothing: \(model.state)")
        }
        await model.load(.manual)
        guard case .failed = model.state else {
            return XCTFail("a manual read should fail: \(model.state)")
        }
    }

    func testAnEnableThatWorkedSaysNothingAndReReads() async {
        let (model, transport) = await model(Self.enable(.fixture("mobile/district-scheduling-enable.json")))
        await model.enable()
        XCTAssertNil(model.notice, "\(transport.sentRequests)")
        XCTAssertFalse(model.busy)
        XCTAssertTrue(transport.sentRequests.contains("GET \(Self.api)/scheduling/status"))
        guard case .ready = model.state else {
            return XCTFail("should be ready: \(model.state)")
        }
    }

    /// The route's own words when it answers but did not enable, and the fallback without them.
    func testAnEnableTheRouteRefusedCarriesItsWords() async {
        let (worded, _) = await model(Self.enable(.json(#"{"ok":false,"status":"error","error":"Region not ready."}"#)))
        await worded.enable()
        XCTAssertEqual(worded.notice, "Region not ready.")

        let (bare, _) = await model(Self.enable(.json(#"{"ok":false,"status":"error","error":null}"#)))
        await bare.enable()
        XCTAssertEqual(bare.notice, SchedulingCopy.enableFailedFallback)
        bare.dismissNotice()
        XCTAssertNil(bare.notice)
    }

    func testEnableRefusalsAreWordedByStatus() async {
        let (forbidden, _) = await model(Self.enable(.status(403)))
        await forbidden.enable()
        XCTAssertEqual(forbidden.notice, SchedulingCopy.notEligible)

        let (limited, _) = await model(Self.enable(.status(429)))
        await limited.enable()
        XCTAssertEqual(limited.notice, SchedulingCopy.tooManyAttempts)

        let (failed, _) = await model(Self.enable(.status(500)))
        await failed.enable()
        XCTAssertNotNil(failed.notice)
        XCTAssertNotEqual(failed.notice, SchedulingCopy.notEligible)
    }
}
