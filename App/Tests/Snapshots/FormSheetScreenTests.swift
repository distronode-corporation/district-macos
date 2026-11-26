import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The sheets that add or change one thing: a contact, a desk ticket, the desk's settings, a
/// meeting's record, one phone number's actions and the workspace picker, each new, filled
/// from the recorded answers, and refused where the sheet can be.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class FormSheetScreenTests: ScreenSnapshotCase {
    /// Each sheet's size at its presentation site.
    private static let contactSize = CGSize(width: 420, height: 360)
    private static let ticketSize = CGSize(width: 480, height: 560)
    private static let deskSettingsSize = CGSize(width: 520, height: 600)
    private static let numberSize = CGSize(width: 460, height: 260)
    /// The record and the picker size themselves (their `idealWidth` and `idealHeight`).
    private static let recordSize = CGSize(width: 600, height: MacSheetFit.height(560))
    private static let pickerSize = CGSize(width: 460, height: 420)

    // MARK: - Create contact

    func testCreateContact() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("new", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.contactSize
            ) { app in
                try await Self.createContact(app, refused: false)
            }
        }
        // ⚠️ THE CREATE REFUSED. The typed fields live in the sheet's own `@State`, out of a
        // test's reach, so they are empty above the failure the model keeps.
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.contactSize
        ) { app in
            try await Self.createContact(app, refused: true)
        }
    }

    private static func createContact(_ app: SignedInApp, refused: Bool) async throws -> AnyView {
        let model = ContactsModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        if refused {
            await model.create(name: "Ada Lovelace", phoneNumber: "+14165550123", email: "")
        }
        return AnyView(CreateContactSheet(model: model)
            .macSheetSize(width: contactSize.width, height: contactSize.height)
            .districtTheme())
    }

    // MARK: - New desk ticket

    func testDeskCompose() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("new", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.ticketSize
            ) { app in
                await Self.deskCompose(app, submitting: nil)
            }
        }
        // Refused before any request: a subject under three characters and no message.
        try await assertView("incomplete-en", rules: ScreenRules.loaded, size: Self.ticketSize) { app in
            await Self.deskCompose(app, submitting: DeskComposerState())
        }
        var complete = DeskComposerState()
        complete.subject = "Printer offline"
        complete.message = "The front desk printer stopped answering this morning."
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.ticketSize
        ) { app in
            await Self.deskCompose(app, submitting: complete)
        }
    }

    private static func deskCompose(_ app: SignedInApp, submitting draft: DeskComposerState?) async -> AnyView {
        let model = DeskModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        if let draft {
            _ = await model.createTicket(draft)
        }
        return AnyView(DeskComposeSheet(model: model)
            .macSheetSize(width: ticketSize.width, height: ticketSize.height)
            .districtTheme())
    }

    // MARK: - Desk settings

    func testDeskSettings() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("loaded", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.deskSettingsSize
            ) { app in
                Self.deskSettings(app, role: .agency)
            }
        }
        // A viewer: the note above controls it may not change.
        try await assertView("viewer-en", rules: ScreenRules.loaded, size: Self.deskSettingsSize) { app in
            Self.deskSettings(app, role: .viewer)
        }
        try await assertView("failed-en", rules: ScreenRules.failing, size: Self.deskSettingsSize) { app in
            Self.deskSettings(app, role: .agency)
        }
    }

    private static func deskSettings(_ app: SignedInApp, role: WorkspaceRole) -> AnyView {
        AnyView(DeskSettingsView(container: app.container, workspaceId: app.workspaceId, role: role, onDismiss: {})
            .macSheetSize(width: deskSettingsSize.width, height: deskSettingsSize.height)
            .districtTheme())
    }

    // MARK: - Meeting record

    func testMeetingRecord() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("record", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.recordSize
            ) { app in
                await Self.meetingRecord(app)
            }
        }
        try await assertView("failed-en", rules: ScreenRules.failing, size: Self.recordSize) { app in
            await Self.meetingRecord(app)
        }
    }

    /// The record of the first meeting in `district-meetings.json`, opened as its row does.
    private static func meetingRecord(_ app: SignedInApp) async -> AnyView {
        let model = RoomsLobbyModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        await model.openMeeting("meeting_contract_live")
        return AnyView(MeetingRecordSheet(state: model.record, onClose: {}).districtTheme())
    }

    // MARK: - One number's actions

    func testNumberActions() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("own", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.numberSize
            ) { app in
                try await Self.numberActions(app, row: 0, role: .agency)
            }
        }
        // A number held on Distronode's carrier account: no Configure and no Release.
        try await assertView("managed-en", rules: ScreenRules.loaded, size: Self.numberSize) { app in
            try await Self.numberActions(app, row: 1, role: .agency)
        }
        try await assertView("viewer-en", rules: ScreenRules.loaded, size: Self.numberSize) { app in
            try await Self.numberActions(app, row: 0, role: .viewer)
        }
        let configured = Self.writes(".*", .fixture("mobile/district-number-configure.json")) + ScreenRules.loaded
        try await assertView("configured-en", rules: configured, size: Self.numberSize) { app in
            try await Self.numberActions(app, row: 0, role: .agency, configuring: true)
        }
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.numberSize
        ) { app in
            try await Self.numberActions(app, row: 0, role: .agency, configuring: true)
        }
    }

    private static func numberActions(
        _ app: SignedInApp,
        row: Int,
        role: WorkspaceRole,
        configuring: Bool = false
    ) async throws -> AnyView {
        let number = try listedNumber(row)
        let model = NumberProvisioningModel(container: app.container, workspaceId: app.workspaceId, role: role)
        if configuring {
            await model.configure(phoneNumber: number.phoneNumber)
        }
        return AnyView(NumberActionsSheet(model: model, number: number)
            .macSheetSize(width: numberSize.width, height: numberSize.height)
            .districtTheme())
    }

    /// Row `index` of `district-provider-numbers.json`: 0 is the workspace's own line, 1 a
    /// managed one.
    private static func listedNumber(_ index: Int) throws -> ListedNumber {
        let rows = try Fixtures.object("mobile/district-provider-numbers.json")["numbers"] as? [Any] ?? []
        guard rows.indices.contains(index) else { throw Fixtures.Missing.fixture("numbers[\(index)]") }
        return try JSONDecoder().decode(ListedNumber.self, from: JSONSerialization.data(withJSONObject: rows[index]))
    }

    // MARK: - Workspace picker

    func testWorkspacePicker() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("list", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.pickerSize
            ) { app in
                await Self.picker(app)
            }
        }
        // One region did not answer: the workspaces that did, and the note under them.
        let partial: [FixtureTransport.Rule] = [
            .get("/api/district/workspace/list", .fixture("mobile/district-workspace-list-partial.json")),
        ]
        try await assertView("partial-en", rules: partial + ScreenRules.loaded, size: Self.pickerSize) { app in
            await Self.picker(app)
        }
    }

    private static func picker(_ app: SignedInApp) async -> AnyView {
        let name = "snapshots.picker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let model = WorkspaceSessionModel(
            container: app.container,
            selection: WorkspaceSelectionStore(defaults: defaults)
        )
        await model.load()
        return AnyView(WorkspacePickerSheet(workspaceSession: model).districtTheme())
    }
}
