@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import XCTest

/// The call directory, call handling, devices and report models driven through their writes,
/// answered by the service's recorded responses (`contracts/`).
///
/// ⚠️ EACH WRITE IS ANSWERED AFTER `ScreenRules.loaded`: the reads keep their recorded `.get`
/// rules there, which match first, so only a write reaches the rule a test adds.
@MainActor
final class SettingsModelStateTests: XCTestCase {
    private static let api = "/api/district"

    private func app(_ rules: [FixtureTransport.Rule]) async -> (ScreenSnapshotCase.SignedInApp, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "settings.\(UUID().uuidString)") ?? .standard
        return await (ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults), transport)
    }

    private func writes(_ transport: FixtureTransport) -> [String] {
        transport.sentRequests.filter { !$0.hasPrefix("GET") }
    }

    private func isSaved(_ state: SettingsSaveState) -> Bool {
        if case .saved = state {
            return true
        }
        return false
    }

    private func isFailed(_ state: SettingsSaveState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    // MARK: - Call directory

    private static func directoryWrite(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/workspace/.*", reply)]
    }

    private func directory(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (DirectoryModel, FixtureTransport) {
        let (app, transport) = await app(rules)
        let model = DirectoryModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.loadConfig()
        return (model, transport)
    }

    func testTheRecordedDirectoryLoadsIntoDrafts() async {
        let (model, _) = await directory(ScreenRules.loaded)
        XCTAssertEqual(model.drafts?.map(\.name), ["Ops desk", "On-call engineer"])
        XCTAssertFalse(model.notEditable)
        XCTAssertTrue(model.canSave)
        XCTAssertFalse(model.wouldSaveEmpty)
    }

    func testAFailedConfigReadLeavesNoDrafts() async {
        let (model, _) = await directory([.get("\(Self.api)/workspace/config", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.load else {
            return XCTFail("should have failed: \(model.load)")
        }
        XCTAssertNil(model.drafts)
        XCTAssertFalse(model.canSave)
        model.addRow()
        XCTAssertNil(model.drafts)
    }

    func testEditingAddingAndRemovingRowsThenSaving() async throws {
        let (model, transport) = await directory(Self.directoryWrite(.fixture("mobile/district-directory-patch.json")))
        let first = try XCTUnwrap(model.drafts?.first)
        model.editName(first.id, "Front desk")
        model.editNumber(first.id, " +14165550100 ")
        model.editType(first.id, "department")
        model.addRow()
        XCTAssertEqual(model.drafts?.count, 3)
        // ⚠️ A BLANK ROW IS NOT SENT.
        let added = try XCTUnwrap(model.drafts?.last)
        XCTAssertTrue(added.isBlank)
        XCTAssertTrue(added.isIncomplete)
        XCTAssertEqual(model.drafts?.first?.rendered(), .object([
            "name": .string("Front desk"),
            "phoneNumber": .string("+14165550100"),
            "type": .string("department"),
        ]))
        model.editType(first.id, nil)
        model.removeRow(added.id)
        XCTAssertEqual(model.drafts?.count, 2)

        await model.saveDirectory()
        XCTAssertTrue(isSaved(model.save), "\(model.save) \(transport.sentRequests)")
        XCTAssertEqual(writes(transport).count, 1)
        // The re-read is the truth, so the drafts are the recorded rows again.
        XCTAssertEqual(model.drafts?.first?.name, "Ops desk")

        model.dismissNotices()
        XCTAssertFalse(isSaved(model.save))
    }

    func testRemovingEveryRowWouldSaveEmpty() async {
        let (model, _) = await directory(ScreenRules.loaded)
        for row in model.drafts ?? [] {
            model.removeRow(row.id)
        }
        XCTAssertTrue(model.wouldSaveEmpty)
    }

    func testARefusedDirectorySaveKeepsTheEdits() async throws {
        let (model, _) = await directory(Self.directoryWrite(.status(500)))
        let first = try XCTUnwrap(model.drafts?.first)
        model.editName(first.id, "Front desk")
        await model.saveDirectory()
        XCTAssertTrue(isFailed(model.save), "\(model.save)")
        XCTAssertEqual(model.drafts?.first?.name, "Front desk")
    }

    func testAReadOnlyRoleCannotEditTheDirectory() async throws {
        let (model, transport) = await directory(Self.directoryWrite(.status(500)), role: nil)
        let first = try XCTUnwrap(model.drafts?.first)
        model.editName(first.id, "Front desk")
        model.addRow()
        model.removeRow(first.id)
        await model.saveDirectory()
        XCTAssertEqual(model.drafts?.first?.name, "Ops desk")
        XCTAssertEqual(model.drafts?.count, 2)
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(writes(transport).isEmpty)
    }

    // MARK: - Call handling

    private static func callHandlingWrite(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/workspace/call-handling", reply)]
    }

    private func callHandling(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (CallHandlingModel, FixtureTransport) {
        let (app, transport) = await app(rules)
        let model = CallHandlingModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.load()
        return (model, transport)
    }

    func testCallHandlingSavesAndAdoptsTheReply() async {
        let (
            model,
            transport
        ) = await callHandling(Self
            .callHandlingWrite(.fixture("mobile/district-call-handling-patch.json")))
        XCTAssertEqual(model.draft, CallHandlingSetting(mode: "ai_then_app", ringSeconds: 15))
        XCTAssertFalse(model.isDirty)
        XCTAssertFalse(model.canSave)
        model.select(mode: "app_first")
        model.setRing(25)
        XCTAssertTrue(model.isDirty)
        await model.saveChanges()
        XCTAssertTrue(isSaved(model.save), "\(model.save) \(transport.sentRequests)")
        XCTAssertEqual(model.draft, CallHandlingSetting(mode: "app_first", ringSeconds: 25))
        XCTAssertFalse(model.isDirty)
        model.dismissNotices()
        XCTAssertFalse(isSaved(model.save))
    }

    /// ⚠️ AN UNKNOWN MODE IS NOT SELECTABLE, AND AN UNCHANGED DRAFT SENDS NOTHING.
    func testAnUnknownModeAndAnUnchangedDraftSendNothing() async {
        let (model, transport) = await callHandling(Self.callHandlingWrite(.status(500)))
        model.select(mode: "not_a_mode")
        XCTAssertFalse(model.isDirty)
        await model.saveChanges()
        XCTAssertTrue(writes(transport).isEmpty)
    }

    func testARefusedCallHandlingSaveKeepsTheDraft() async {
        let (model, _) = await callHandling(Self.callHandlingWrite(.status(500)))
        model.select(mode: "app_first")
        await model.saveChanges()
        XCTAssertTrue(isFailed(model.save), "\(model.save)")
        XCTAssertEqual(model.draft?.mode, "app_first")
        XCTAssertTrue(model.isDirty)
    }

    func testAFailedCallHandlingReadHasNoDraft() async {
        let (
            model,
            _
        ) = await callHandling([.get("\(Self.api)/workspace/call-handling", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.load else {
            return XCTFail("should have failed: \(model.load)")
        }
        XCTAssertNil(model.draft)
        model.select(mode: "app_first")
        model.setRing(25)
        XCTAssertNil(model.draft)
    }

    func testAReadOnlyRoleCannotChangeCallHandling() async {
        let (model, transport) = await callHandling(Self.callHandlingWrite(.status(500)), role: nil)
        model.select(mode: "app_first")
        model.setRing(25)
        await model.saveChanges()
        XCTAssertFalse(model.isDirty)
        XCTAssertTrue(writes(transport).isEmpty)
    }

    // MARK: - Devices

    private static func devicesWrite(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("/api/auth/native/.*", reply)]
    }

    private func devices(_ rules: [FixtureTransport.Rule]) async -> (DevicesModel, FixtureTransport) {
        let (app, transport) = await app(rules)
        let model = DevicesModel(container: app.container)
        await model.load()
        return (model, transport)
    }

    func testRevokingAnotherDeviceReReadsTheList() async {
        let (model, transport) = await devices(Self.devicesWrite(.fixture("mobile/district-device-revoke.json")))
        guard case let .ready(rows) = model.list else {
            return XCTFail("devices not ready: \(model.list)")
        }
        XCTAssertEqual(rows.count, 2)
        let signedOut = await model.revoke(deviceId: "device-contract-android-1")
        XCTAssertFalse(signedOut)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.mutationFailure, "\(transport.sentRequests)")
        XCTAssertFalse(model.nothingRevoked)
        XCTAssertEqual(transport.sentRequests.filter { $0 == "GET /api/auth/native/devices" }.count, 2)
    }

    /// ⚠️ A REVOKE THAT ENDED NOTHING SAYS SO.
    func testARevokeThatEndedNothingSaysSo() async {
        let (model, _) = await devices(Self.devicesWrite(.json(#"{"success":true,"revoked":0}"#)))
        _ = await model.revoke(deviceId: "device-contract-ios-2")
        XCTAssertTrue(model.nothingRevoked)
        model.dismissNotices()
        XCTAssertFalse(model.nothingRevoked)
    }

    /// ⛔ REVOKING THIS DEVICE, OR ALL OF THEM, SIGNS THIS ONE OUT, so the list is not re-read.
    func testRevokingThisDeviceOrAllSignsOut() async {
        let (model, transport) = await devices(Self.devicesWrite(.fixture("mobile/district-device-revoke.json")))
        let this = await model.revoke(deviceId: model.thisDeviceId)
        XCTAssertTrue(this, "\(transport.sentRequests)")
        let all = await model.revokeAll()
        XCTAssertTrue(all, "\(transport.sentRequests)")
        XCTAssertEqual(transport.sentRequests.filter { $0 == "GET /api/auth/native/devices" }.count, 1)
    }

    func testARefusedRevokeSaysWhy() async {
        let (model, _) = await devices(Self.devicesWrite(.status(500)))
        let signedOut = await model.revoke(deviceId: "device-contract-android-1")
        XCTAssertFalse(signedOut)
        XCTAssertNotNil(model.mutationFailure)
        let all = await model.revokeAll()
        XCTAssertFalse(all)
        XCTAssertNotNil(model.mutationFailure)
        model.dismissNotices()
        XCTAssertNil(model.mutationFailure)
    }

    func testAFailedDeviceReadIsItsOwnState() async {
        let (model, _) = await devices([.get("/api/auth/native/devices", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.list else {
            return XCTFail("should have failed: \(model.list)")
        }
    }

    // MARK: - Report content

    private func report(_ reply: FixtureTransport.Reply, target: ReportTarget) async -> ReportContentModel {
        let (app, _) = await app(ScreenRules.loaded + [.any("\(Self.api)/support/requests", reply)])
        return ReportContentModel(container: app.container, workspaceId: app.workspaceId, target: target)
    }

    func testAFiledReportConfirms() async {
        let model = await report(
            .fixture("mobile/district-support-request-create.json"),
            target: .conversation(threadKey: "thread-1", name: "Contract Test Caller")
        )
        XCTAssertFalse(model.headline.isEmpty)
        XCTAssertFalse(model.isSending)
        await model.submit(note: "Abusive messages")
        guard case .done = model.state else {
            return XCTFail("should be done: \(model.state)")
        }
        model.reset()
        XCTAssertEqual(model.state, .idle)
    }

    func testARefusedReportSaysWhy() async {
        let model = await report(.status(500), target: .call(callId: "call_1"))
        XCTAssertFalse(model.headline.isEmpty)
        await model.submit(note: "")
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
    }
}
