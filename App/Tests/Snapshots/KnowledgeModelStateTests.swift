@testable import DistrictMac
import DistrictModel
import XCTest

/// The knowledge model driven through adding a document and changing the knowledge mode,
/// answered by the service's recorded responses (`contracts/`). The file reader's effect on
/// the form is pinned in ``KnowledgeModelFileTests``.
///
/// ⚠️ EACH WRITE IS ANSWERED AFTER `ScreenRules.loaded`: the reads keep their recorded `.get`
/// rules there, which match first, so only a write reaches the rule a test adds.
@MainActor
final class KnowledgeModelStateTests: XCTestCase {
    private static let api = "/api/district"

    private static func add(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/workspace/knowledge", reply)]
    }

    private static func mode(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/workspace/knowledge-mode", reply)]
    }

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (KnowledgeModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "knowledge.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = KnowledgeModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.load()
        return (model, transport)
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

    func testTheRecordedDocumentsAndModeLoad() async {
        let (model, _) = await model(ScreenRules.loaded)
        XCTAssertEqual(model.documents.first?.id, "doc_contract_ready")
        XCTAssertEqual(model.mode, "linked")
        XCTAssertFalse(model.modeUnavailable)
        XCTAssertTrue(model.canChangeMode)
        XCTAssertTrue(model.canReadFile)
        XCTAssertFalse(model.canAdd)
        XCTAssertFalse(model.isResidencyChange(to: .linked))
    }

    /// ⛔ TWO READS, TWO FAILURES: a mode that could not be read leaves the list and no switch.
    func testAFailedModeReadLeavesTheListAndNoSwitch() async {
        let (model, _) = await model([.get("\(Self.api)/workspace/knowledge-mode", .status(500))] + ScreenRules.loaded)
        XCTAssertFalse(model.documents.isEmpty)
        XCTAssertNil(model.mode)
        XCTAssertTrue(model.modeUnavailable)
        XCTAssertFalse(model.canChangeMode)
        XCTAssertTrue(model.isResidencyChange(to: .linked))
    }

    func testAFailedListIsItsOwnState() async {
        let (model, _) = await model([.get("\(Self.api)/workspace/knowledge", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.list else {
            return XCTFail("should have failed: \(model.list)")
        }
        XCTAssertTrue(model.documents.isEmpty)
    }

    func testAnAddedDocumentClearsTheFormAndReReads() async {
        let (model, transport) = await model(Self.add(.fixture("mobile/district-knowledge-create.json")))
        model.editTitle(" Holiday hours ")
        model.editContent("Closed on the 25th.")
        XCTAssertTrue(model.canAdd)
        await model.addDocument()
        XCTAssertTrue(isSaved(model.addSave), "\(model.addSave) \(transport.sentRequests)")
        XCTAssertEqual(model.draftTitle, "")
        XCTAssertEqual(model.draftContent, "")
        XCTAssertEqual(writes(transport).count, 1)
        XCTAssertEqual(transport.sentRequests.filter { $0 == "GET \(Self.api)/workspace/knowledge" }.count, 2)

        model.dismissNotices()
        XCTAssertFalse(isSaved(model.addSave))
    }

    /// ⚠️ AN INCOMPLETE FORM IS MARKED REJECTED AND SENDS NOTHING.
    func testAnIncompleteFormIsRejectedLocally() async {
        let (model, transport) = await model(Self.add(.status(500)))
        model.editTitle("Holiday hours")
        await model.addDocument()
        XCTAssertTrue(model.addRejected)
        XCTAssertTrue(writes(transport).isEmpty)
        model.editContent("Closed on the 25th.")
        XCTAssertFalse(model.addRejected)
    }

    func testARefusedAddKeepsTheForm() async {
        let (model, _) = await model(Self.add(.status(500)))
        model.editTitle("Holiday hours")
        model.editContent("Closed on the 25th.")
        await model.addDocument()
        XCTAssertTrue(isFailed(model.addSave), "\(model.addSave)")
        XCTAssertEqual(model.draftTitle, "Holiday hours")
    }

    func testAModeChangeAdoptsTheStoredMode() async {
        let (model, transport) = await model(Self.mode(.fixture("mobile/district-knowledge-mode-patch.json")))
        await model.setMode(.linked)
        XCTAssertTrue(writes(transport).isEmpty, "the mode already held is not written again")
        await model.setMode(.internal)
        XCTAssertTrue(isSaved(model.modeSave), "\(model.modeSave) \(transport.sentRequests)")
        XCTAssertEqual(model.mode, "internal")
        XCTAssertTrue(model.isResidencyChange(to: .linked))
    }

    func testARefusedModeChangeKeepsTheMode() async {
        let (model, _) = await model(Self.mode(.status(500)))
        await model.setMode(.internal)
        XCTAssertTrue(isFailed(model.modeSave), "\(model.modeSave)")
        XCTAssertEqual(model.mode, "linked")
    }

    func testAFileImportFailureSaysTheFileIsUnreadable() async {
        let (model, _) = await model(ScreenRules.loaded)
        model.fileImportFailed()
        XCTAssertEqual(model.fileRefusal, SettingsCopy.knowledgeFileUnreadable)
        model.editTitle("x")
        XCTAssertNil(model.fileRefusal)
    }

    func testAReadOnlyRoleSendsNoWrite() async {
        let (model, transport) = await model(Self.add(.status(500)), role: nil)
        model.editTitle("Holiday hours")
        model.editContent("Closed on the 25th.")
        XCTAssertFalse(model.canAdd)
        XCTAssertFalse(model.canChangeMode)
        XCTAssertFalse(model.canReadFile)
        await model.addDocument()
        await model.setMode(.internal)
        model.fileImportFailed()
        XCTAssertNil(model.fileRefusal)
        XCTAssertTrue(writes(transport).isEmpty)
    }
}
