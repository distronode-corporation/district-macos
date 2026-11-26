import DistrictData
import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The workspace settings' sheets and editors: a messaging account, new and edited, the
/// persona preview, and the Voice Studio's editor on each leg of the chain.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class SettingsSheetScreenTests: ScreenSnapshotCase {
    /// The account sheet's and the preview's sizes at their presentation sites.
    private static let accountSize = CGSize(width: 520, height: 620)
    private static let previewSize = CGSize(width: 460, height: 420)
    /// The leg editor is a card on the Voice Studio screen, drawn alone at a sheet's size.
    private static let editorSize = CGSize(width: 560, height: 620)

    /// The BYOK Twilio account in `district-messaging.json`.
    private static let twilioAccount = "acct-twilio"

    // MARK: - Messaging account

    func testMessagingAccount() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("new", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.accountSize
            ) { app in
                await Self.account(app, editing: nil)
            }
            try await assertView(
                Self.named("edit", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.accountSize
            ) { app in
                await Self.account(app, editing: Self.twilioAccount)
            }
        }
        // The edit saved and refused: the draft stays, and the sheet says why.
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.accountSize
        ) { app in
            await Self.account(app, editing: Self.twilioAccount) { model in
                await model.saveAccount()
            }
        }
        // New credentials typed and tested, and the test could not reach the carrier.
        try await assertView(
            "test-failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.accountSize
        ) { app in
            await Self.account(app, editing: nil) { model in
                guard var draft = model.draft else { return }
                draft.label = "Twilio (backup)"
                draft.secrets = ["accountSid": "sid-for-a-test", "authToken": "token-for-a-test"]
                model.editDraft(draft)
                await model.testCredentials()
            }
        }
    }

    /// The account sheet over the recorded account list, opened for `accountId` (nil: a new
    /// account), and `then` run on the open draft.
    private static func account(
        _ app: SignedInApp,
        editing accountId: String?,
        then action: (@MainActor (MessagingModel) async -> Void)? = nil
    ) async -> AnyView {
        let model = MessagingModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        await model.loadAccounts()
        model.startEditing(accountId: accountId)
        await action?(model)
        return AnyView(MessagingAccountSheet(model: model)
            .macSheetSize(width: accountSize.width, height: accountSize.height)
            .sheetPage().districtTheme())
    }

    // MARK: - Persona preview

    func testPersonaPreview() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("idle", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.previewSize
            ) { app in
                try await Self.preview(app)
            }
        }
    }

    /// The preview of the persona form as the recorded configuration fills it, which is what
    /// the Persona screen hands the sheet when it opens.
    private static func preview(_ app: SignedInApp) async throws -> AnyView {
        let persona = PersonaModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        await persona.loadConfig()
        let form = try XCTUnwrap(persona.previewForm, "the recorded persona gave no preview form")
        return AnyView(PersonaPreviewView(container: app.container, workspaceId: app.workspaceId, form: form)
            .macSheetSize(width: previewSize.width, height: previewSize.height)
            .sheetPage().districtTheme())
    }

    // MARK: - Voice Studio leg editor

    func testVoiceStudioEar() async throws {
        try await leg(.stt)
    }

    func testVoiceStudioTurns() async throws {
        try await leg(.turn)
    }

    func testVoiceStudioBrain() async throws {
        try await leg(.llm)
    }

    func testVoiceStudioMouth() async throws {
        try await leg(.tts)
    }

    private func leg(
        _ leg: VoiceStudioLeg,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named(leg.rawValue, locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.editorSize,
                file: file,
                testName: testName,
                line: line
            ) { app in
                let model = VoiceStudioModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
                await model.loadStudio()
                model.selectLeg(leg)
                let session = try XCTUnwrap(model.session, "the recorded Voice Studio did not load")
                return AnyView(ScrollView {
                    VoiceStudioLegEditor(model: model, session: session)
                        .padding(DistrictSpacing.gutter)
                }
                .sheetPage().districtTheme())
            }
        }
    }
}
