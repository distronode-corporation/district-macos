@testable import DistrictMac
import DistrictModel
import XCTest

/// The receptionist's capabilities and the caller enrichment switch, driven through their
/// saves, answered by the service's recorded responses (`contracts/`).
///
/// ⚠️ EACH WRITE IS ANSWERED AFTER `ScreenRules.loaded`: the configuration read keeps its
/// recorded `.get` rule there, which matches first, so only a write reaches the rule added.
@MainActor
final class CapabilitiesModelStateTests: XCTestCase {
    private static let api = "/api/district"

    private static func write(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/workspace/.*", reply)]
    }

    private func model(_ rules: [FixtureTransport.Rule]) async -> (CapabilitiesModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "capabilities.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = CapabilitiesModel(container: app.container, workspaceId: app.workspaceId)
        await model.loadConfig()
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

    /// ⚠️ A STORED TOOL THIS BUILD DOES NOT KNOW IS SHOWN AFTER THE CATALOGUE, unlabelled.
    func testTheStoredToolsAreRowsWithTheUnknownOneLast() async {
        let (model, _) = await model(ScreenRules.loaded)
        XCTAssertTrue(model.hasStoredTools)
        XCTAssertTrue(model.canEditTools)
        let rows = model.rows
        XCTAssertEqual(rows.count, CapabilityCatalog.ids.count + 1)
        XCTAssertEqual(rows.last?.id, "transfer_to_creator")
        XCTAssertNil(rows.last?.label)
        XCTAssertEqual(rows.first { $0.id == "send_sms" }?.enabled, false)
        XCTAssertEqual(rows.first { $0.id == "book_appointment" }?.enabled, true)
        XCTAssertFalse(model.toolsDirty)
        XCTAssertTrue(model.enrichmentEnabled)
        XCTAssertFalse(model.enrichmentDirty)
        XCTAssertFalse(model.canSaveEnrichment)
    }

    func testEveryCatalogueEntryHasALabel() {
        for id in CapabilityCatalog.ids {
            XCTAssertNotNil(CapabilityCatalog.label(for: id), id)
        }
        XCTAssertNil(CapabilityCatalog.label(for: "not_a_tool"))
    }

    /// ⛔ NO STORED LIST MEANS EVERY TOOL IS ON AND NOTHING CAN BE EDITED: writing a list
    /// would turn the server's default into a restriction nobody chose.
    func testNoStoredListShowsEveryToolOnAndLocksThem() async {
        let rules: [FixtureTransport.Rule] = [
            .get("\(Self.api)/workspace/config", .fixture("mobile/district-workspace-config-sparse.json")),
        ] + ScreenRules.loaded
        let (model, _) = await model(rules)
        XCTAssertFalse(model.hasStoredTools)
        XCTAssertFalse(model.canEditTools)
        XCTAssertNil(model.pendingTools)
        XCTAssertEqual(model.rows.count, CapabilityCatalog.ids.count)
        XCTAssertTrue(model.rows.allSatisfy(\.enabled))
        model.toggleTool("send_sms", to: false)
        XCTAssertFalse(model.toolsDirty)
    }

    func testAFailedReadHasNoRows() async {
        let (model, _) = await model([.get("\(Self.api)/workspace/config", .status(500))] + ScreenRules.loaded)
        XCTAssertTrue(model.rows.isEmpty)
        model.toggleEnrichment(to: false)
        XCTAssertFalse(model.enrichmentDirty)
    }

    func testToggledToolsAreSavedAndTheReReadIsAdopted() async {
        let (model, transport) = await model(Self.write(.fixture("mobile/district-tools-patch.json")))
        model.toggleTool("send_sms", to: true)
        model.toggleTool("dispatch_email", to: false)
        XCTAssertTrue(model.toolsDirty)
        XCTAssertTrue(model.canSaveTools)
        XCTAssertEqual(model.pendingTools, [
            "search_knowledge_base", "transfer_to_agent", "book_appointment", "transfer_to_creator",
            "leave_message", "send_sms",
        ])
        await model.saveTools()
        XCTAssertTrue(isSaved(model.toolsSave), "\(model.toolsSave) \(transport.sentRequests)")
        XCTAssertEqual(writes(transport).count, 1)
        // The re-read is the recorded configuration, so nothing is pending any more.
        XCTAssertFalse(model.toolsDirty)

        model.dismissNotices()
        XCTAssertFalse(isSaved(model.toolsSave))
    }

    func testARefusedToolsSaveKeepsTheToggles() async {
        let (model, _) = await model(Self.write(.status(500)))
        model.toggleTool("send_sms", to: true)
        await model.saveTools()
        XCTAssertTrue(isFailed(model.toolsSave), "\(model.toolsSave)")
        XCTAssertTrue(model.toolsDirty)
    }

    func testTheEnrichmentSwitchSavesAndAdoptsTheReRead() async {
        let (model, transport) = await model(Self.write(.fixture("mobile/district-persona-patch.json")))
        model.toggleEnrichment(to: false)
        XCTAssertFalse(model.enrichmentEnabled)
        XCTAssertTrue(model.enrichmentDirty)
        XCTAssertTrue(model.canSaveEnrichment)
        await model.saveEnrichment()
        XCTAssertTrue(isSaved(model.enrichmentSave), "\(model.enrichmentSave) \(transport.sentRequests)")
        XCTAssertFalse(model.enrichmentDirty)
    }

    func testARefusedEnrichmentSaveKeepsTheDraft() async {
        let (model, _) = await model(Self.write(.status(500)))
        model.toggleEnrichment(to: false)
        await model.saveEnrichment()
        XCTAssertTrue(isFailed(model.enrichmentSave), "\(model.enrichmentSave)")
        XCTAssertTrue(model.enrichmentDirty)
    }

    /// ⚠️ NOTHING TO SAVE SENDS NOTHING.
    func testNothingDirtySendsNothing() async {
        let (model, transport) = await model(Self.write(.status(500)))
        await model.saveTools()
        await model.saveEnrichment()
        XCTAssertTrue(writes(transport).isEmpty)
    }
}
