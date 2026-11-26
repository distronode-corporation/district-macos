@testable import DistrictMac
import DistrictModel
import XCTest

/// The messaging accounts model driven through its writes and the credential probe, answered
/// by the service's recorded responses (`contracts/`).
///
/// ⚠️ UNIT TESTS, NOT IMAGES: ``MessagingView`` builds its model in its own `@State`, so a
/// screen snapshot can only show the list its first read settles into. The states after a
/// write or a probe are pinned on the model.
///
/// ⚠️ EACH TEST ANSWERS ITS ONE KIND OF WRITE WITH ONE RECORDING, matched as any request on a
/// messaging path after `ScreenRules.loaded`: the list's own GET matches the `.get` rule there
/// first, so only the write reaches the rule added here.
@MainActor
final class MessagingModelStateTests: XCTestCase {
    private static let api = "/api/district"

    private static func writes(_ reply: FixtureTransport.Reply) -> [FixtureTransport.Rule] {
        ScreenRules.loaded + [.any("\(api)/.*messaging.*", reply)]
    }

    /// A Twilio draft with both secrets typed, which the probe and the save accept.
    private static let twilio = MessagingDraft(secrets: ["accountSid": "AC-test", "authToken": "token-test"])

    private func model(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async -> (MessagingModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "messaging.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let model = MessagingModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.loadAccounts()
        return (model, transport)
    }

    private func writesSent(_ transport: FixtureTransport) -> [String] {
        transport.sentRequests.filter { !$0.hasPrefix("GET") && $0.contains("messaging") }
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

    // MARK: - Reading

    func testTheRecordedAccountsLoad() async {
        let (model, _) = await model(ScreenRules.loaded)
        XCTAssertEqual(model.accounts.first?.id, "acct-twilio")
        XCTAssertTrue(model.canEditNow)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.isProbing)
    }

    func testAFailedReadLeavesNothingToEdit() async {
        let (model, _) = await model([.get("\(Self.api)/workspace/messaging", .status(500))] + ScreenRules.loaded)
        guard case .failed = model.load else {
            return XCTFail("should have failed: \(model.load)")
        }
        XCTAssertNil(model.response)
        XCTAssertTrue(model.accounts.isEmpty)
        XCTAssertFalse(model.canEditNow)
        model.startEditing(accountId: nil)
        XCTAssertNil(model.draft)
    }

    // MARK: - Row writes

    func testSetDefaultWritesAndReReads() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-set-default.json")))
        await model.setDefault(accountId: "acct-telnyx")
        XCTAssertTrue(isSaved(model.defaultSave), "\(model.defaultSave) \(transport.sentRequests)")
        XCTAssertEqual(writesSent(transport).count, 1)

        model.dismissNotices()
        XCTAssertFalse(isSaved(model.defaultSave))
    }

    func testAChannelDefaultWritesAndReReads() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-channel-default.json")))
        await model.setChannelDefault(channel: "sms", accountId: "acct-telnyx")
        XCTAssertTrue(isSaved(model.channelSave), "\(model.channelSave) \(transport.sentRequests)")
    }

    func testDeleteWritesAndReReads() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-delete.json")))
        await model.deleteAccount(accountId: "acct-telnyx")
        XCTAssertTrue(isSaved(model.deleteSave), "\(model.deleteSave) \(transport.sentRequests)")
    }

    /// ⛔ A REFUSED ROW WRITE RE-READS THE LIST AND SAYS WHY.
    func testARefusedDeleteSaysWhyAndKeepsTheList() async {
        let (model, _) = await model(Self.writes(.status(500)))
        await model.deleteAccount(accountId: "acct-telnyx")
        XCTAssertTrue(isFailed(model.deleteSave), "\(model.deleteSave)")
        XCTAssertFalse(model.accounts.isEmpty)
    }

    func testAReadOnlyRoleSendsNoWrite() async {
        let (model, transport) = await model(Self.writes(.status(500)), role: nil)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.canEditNow)
        await model.setDefault(accountId: "acct-telnyx")
        await model.setChannelDefault(channel: "sms", accountId: "acct-telnyx")
        await model.deleteAccount(accountId: "acct-telnyx")
        model.editCreatorCell("+14165550100")
        await model.saveCreatorCell()
        XCTAssertTrue(writesSent(transport).isEmpty)
    }

    // MARK: - The creator cell

    func testTheCreatorCellSavesAndClears() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-meta.json")))
        XCTAssertFalse(model.canSaveCreatorCell)
        model.editCreatorCell("  +14165550100 ")
        XCTAssertTrue(model.canSaveCreatorCell)
        await model.saveCreatorCell()
        XCTAssertTrue(isSaved(model.metaSave), "\(model.metaSave) \(transport.sentRequests)")
        XCTAssertEqual(model.creatorCellDraft, "")
    }

    /// ⚠️ A FAILURE LEAVES THE TYPED NUMBER ON SCREEN.
    func testAFailedCreatorCellKeepsTheNumber() async {
        let (model, _) = await model(Self.writes(.status(500)))
        model.editCreatorCell("+14165550100")
        await model.saveCreatorCell()
        XCTAssertTrue(isFailed(model.metaSave), "\(model.metaSave)")
        XCTAssertEqual(model.creatorCellDraft, "+14165550100")
    }

    // MARK: - The account draft and the probe

    func testEditingAnAccountOpensItsDraftAndClosingDropsIt() async {
        let (model, _) = await model(ScreenRules.loaded)
        model.startEditing(accountId: "acct-twilio")
        XCTAssertEqual(model.draft?.accountId, "acct-twilio")
        XCTAssertEqual(model.draft?.provider, "twilio")
        model.startEditing(accountId: "acct-missing")
        XCTAssertEqual(model.draft?.accountId, "acct-twilio")
        model.editDraft(nil)
        XCTAssertNil(model.draft)
        // ⚠️ AN EDIT WITH NO DRAFT OPEN IS DROPPED.
        model.editDraft(Self.twilio)
        XCTAssertNil(model.draft)
        model.startEditing(accountId: nil)
        XCTAssertEqual(model.draft?.isCreate, true)
    }

    func testCredentialsThatAuthenticatePass() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-test.json")))
        model.startEditing(accountId: nil)
        model.editDraft(Self.twilio)
        await model.testCredentials()
        guard case .passed = model.probe else {
            return XCTFail("probe should have passed: \(model.probe) \(transport.sentRequests)")
        }
    }

    /// The carrier's own words, forwarded.
    func testRejectedCredentialsCarryTheCarriersWords() async {
        let (model, _) = await model(Self.writes(.fixture("mobile/district-messaging-test-rejected.json")))
        model.startEditing(accountId: nil)
        model.editDraft(Self.twilio)
        await model.testCredentials()
        guard case let .rejected(message) = model.probe else {
            return XCTFail("probe should have been rejected: \(model.probe)")
        }
        XCTAssertEqual(message, "Authenticate (20003)")
    }

    /// ⛔ A STATUS FAILURE IS NOT EVIDENCE ABOUT THE CREDENTIALS.
    func testAProbeThatCouldNotAskIsUnreachable() async {
        let (model, _) = await model(Self.writes(.status(500)))
        model.startEditing(accountId: nil)
        model.editDraft(Self.twilio)
        await model.testCredentials()
        guard case .unreachable = model.probe else {
            return XCTFail("probe should be unreachable: \(model.probe)")
        }
        // Editing the draft retires the probe's answer.
        model.editDraft(Self.twilio)
        guard case .idle = model.probe else {
            return XCTFail("probe should be idle: \(model.probe)")
        }
    }

    func testSavingANewAccountClosesTheDraftAndReReads() async {
        let (model, transport) = await model(Self.writes(.fixture("mobile/district-messaging-upsert.json")))
        model.startEditing(accountId: nil)
        model.editDraft(Self.twilio)
        await model.saveAccount()
        XCTAssertTrue(isSaved(model.accountSave), "\(model.accountSave) \(transport.sentRequests)")
        XCTAssertNil(model.draft)
    }

    /// ⚠️ A REFUSED SAVE KEEPS THE DRAFT AND ITS TYPED SECRETS.
    func testARefusedSaveKeepsTheDraft() async {
        let (model, _) = await model(Self.writes(.status(500)))
        model.startEditing(accountId: nil)
        model.editDraft(Self.twilio)
        await model.saveAccount()
        XCTAssertTrue(isFailed(model.accountSave), "\(model.accountSave)")
        XCTAssertEqual(model.draft?.value(for: "authToken"), "token-test")
    }
}
