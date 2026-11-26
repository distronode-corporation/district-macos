@testable import DistrictMac
import DistrictModel
import XCTest

/// The contact detail model driven through its four mutations and their failures, answered by
/// the service's recorded responses (`contracts/`).
///
/// ⚠️ UNIT TESTS, NOT IMAGES: ``ContactDetailView`` builds its model in its own `@State`, so a
/// screen snapshot can only show the state its first read settles into (the detail suite draws
/// that). The states after a rename, an enrich, a clear or a delete are pinned on the model.
@MainActor
final class ContactDetailModelStateTests: XCTestCase {
    private static let api = "/api/district"
    private static let contactId = "contact_contract_1"

    /// The writes, after the reads: none of these paths is read, so the order only keeps
    /// the overrides a test puts first ahead of them.
    private static let writes: [FixtureTransport.Rule] = [
        .any("\(api)/contacts/update", .fixture("mobile/district-contact-update.json")),
        .any("\(api)/contacts/enrich", .fixture("mobile/district-enrich.json")),
        .any("\(api)/contacts/clear-intel", .fixture("mobile/district-clear-intel.json")),
        .any("\(api)/contacts/delete", .fixture("mobile/district-contact-delete.json")),
    ]

    private static let loaded = ScreenRules.loaded + writes

    /// The recorded contact with its dossier status set to `status`, for the states the
    /// recording (`complete`) does not reach: nothing stored yet, or a crawl in flight.
    private static func detail(dgiStatus status: String?) -> FixtureTransport.Rule {
        .get("\(api)/contacts/get", .edited("mobile/district-contact-detail.json") { body in
            var contact = body["contact"] as? [String: Any] ?? [:]
            contact["dgiStatus"] = status ?? NSNull()
            if status == nil {
                contact["intelligence"] = NSNull()
                contact["company"] = NSNull()
            }
            body["contact"] = contact
        })
    }

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (ContactDetailModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "contact.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = ContactDetailModel(
            container: app.container,
            workspaceId: app.workspaceId,
            contactId: Self.contactId,
            role: role
        )
        await model.load()
        return (model, transport)
    }

    private func loaded(
        _ model: ContactDetailModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> LoadedContact? {
        guard case let .content(contact) = model.state else {
            XCTFail("contact not loaded: \(model.state)", file: file, line: line)
            return nil
        }
        return contact
    }

    private func sent(_ transport: FixtureTransport, _ path: String) -> Bool {
        transport.sentRequests.contains { !$0.hasPrefix("GET") && $0.contains("\(Self.api)/contacts/\(path)") }
    }

    // MARK: - Reading

    func testTheRecordedContactLoadsWithACompleteDossier() async {
        let (model, _) = await model(Self.loaded)
        XCTAssertEqual(loaded(model)?.contact.name, "Contract Test Caller")
        XCTAssertTrue(model.canMutate)
        XCTAssertFalse(model.isEnriching)
        XCTAssertFalse(model.isEnrichable)
        XCTAssertTrue(model.isClearable)
        XCTAssertEqual(model.pollGeneration, 0)
    }

    func testAFailedReadIsTheFailureState() async {
        let (model, _) = await model([.get("\(Self.api)/contacts/get", .status(500))] + Self.loaded)
        guard case .failed = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
        XCTAssertFalse(model.isEnriching)
        XCTAssertFalse(model.isEnrichable)
        XCTAssertFalse(model.isClearable)
    }

    /// ⛔ A 404 IS "NOT AVAILABLE", with nothing to retry.
    func testANotFoundReadSaysTheContactIsNotAvailable() async {
        let (model, _) = await model([.get("\(Self.api)/contacts/get", .refusal(404, code: "not_found"))] + Self.loaded)
        guard case let .failed(failure) = model.state else {
            return XCTFail("should have failed: \(model.state)")
        }
        XCTAssertEqual(failure.message, ContactsCopy.contactNotAvailable)
    }

    /// ⛔ THE POLL'S GATE OPENS ON THE TRANSITION INTO AN IN-FLIGHT STATUS.
    func testACrawlInFlightOpensThePoll() async {
        let (model, _) = await model([Self.detail(dgiStatus: "crawling")] + Self.loaded)
        XCTAssertTrue(model.isEnriching)
        XCTAssertFalse(model.isEnrichable)
        XCTAssertEqual(model.pollGeneration, 1)
    }

    // MARK: - Mutations

    func testARenameWritesAndReReads() async {
        let (model, transport) = await model(Self.loaded)
        await model.rename(to: "  Ada Lovelace  ")
        XCTAssertTrue(sent(transport, "update"), "\(transport.sentRequests)")
        XCTAssertEqual(loaded(model)?.saving, false)
        XCTAssertNil(loaded(model)?.mutationFailure)
    }

    /// ⚠️ A BLANK OR UNCHANGED NAME IS NOT AN EDIT AND SENDS NOTHING.
    func testABlankOrUnchangedNameSendsNothing() async {
        let (model, transport) = await model(Self.loaded)
        await model.rename(to: "   ")
        await model.rename(to: "Contract Test Caller")
        XCTAssertFalse(sent(transport, "update"))
        XCTAssertEqual(loaded(model)?.saving, false)
    }

    func testARefusedRenameKeepsTheContactAndSaysWhy() async {
        let rules: [FixtureTransport.Rule] = [.any("\(Self.api)/contacts/update", .status(500))] + Self.loaded
        let (model, _) = await model(rules)
        await model.rename(to: "Ada Lovelace")
        XCTAssertEqual(loaded(model)?.contact.name, "Contract Test Caller")
        XCTAssertEqual(loaded(model)?.saving, false)
        XCTAssertNotNil(loaded(model)?.mutationFailure)

        model.clearMutationFailure()
        XCTAssertNil(loaded(model)?.mutationFailure)
    }

    func testEnrichIsOfferedOnlyWithNothingStoredAndQueuesOneCrawl() async {
        let (model, transport) = await model([Self.detail(dgiStatus: nil)] + Self.loaded)
        XCTAssertTrue(model.isEnrichable)
        XCTAssertFalse(model.isClearable)
        await model.enrich()
        XCTAssertTrue(sent(transport, "enrich"), "\(transport.sentRequests)")
        XCTAssertEqual(loaded(model)?.saving, false)
        XCTAssertNil(loaded(model)?.mutationFailure)
    }

    /// ⛔ ONE TAP IS ONE CRAWL: a contact whose dossier is complete is not enriched again.
    func testEnrichIsRefusedWhenADossierIsStored() async {
        let (model, transport) = await model(Self.loaded)
        await model.enrich()
        XCTAssertFalse(sent(transport, "enrich"))
    }

    func testAFailedEnrichSaysWhy() async {
        let rules: [FixtureTransport.Rule] = [
            Self.detail(dgiStatus: "failed"),
            .any("\(Self.api)/contacts/enrich", .status(500)),
        ] + Self.loaded
        let (model, _) = await model(rules)
        XCTAssertTrue(model.isEnrichable)
        XCTAssertTrue(model.isClearable)
        await model.enrich()
        XCTAssertNotNil(loaded(model)?.mutationFailure)
    }

    func testClearIntelWritesAndReReads() async {
        let (model, transport) = await model(Self.loaded)
        await model.clearIntel()
        XCTAssertTrue(sent(transport, "clear-intel"), "\(transport.sentRequests)")
        XCTAssertEqual(loaded(model)?.saving, false)
        XCTAssertNil(loaded(model)?.mutationFailure)
    }

    func testDeleteAnswersTrueAndAFailedOneFalse() async {
        let (model, transport) = await model(Self.loaded)
        let deleted = await model.delete()
        XCTAssertTrue(deleted, "\(transport.sentRequests)")

        let rules: [FixtureTransport.Rule] = [.any("\(Self.api)/contacts/delete", .status(500))] + Self.loaded
        let (refused, _) = await self.model(rules)
        let refusedDeleted = await refused.delete()
        XCTAssertFalse(refusedDeleted)
        XCTAssertNotNil(loaded(refused)?.mutationFailure)
    }

    /// ⛔ A ROLE THE SERVER WOULD REFUSE NEVER SENDS A WRITE.
    func testAReadOnlyRoleSendsNoWrite() async {
        let (model, transport) = await model([Self.detail(dgiStatus: nil)] + Self.loaded, role: nil)
        XCTAssertFalse(model.canMutate)
        await model.rename(to: "Ada Lovelace")
        await model.enrich()
        await model.clearIntel()
        let deleted = await model.delete()
        XCTAssertFalse(deleted)
        for path in ["update", "enrich", "clear-intel", "delete"] {
            XCTAssertFalse(sent(transport, path), path)
        }
    }
}
