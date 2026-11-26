import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The Inbox's sheets: the new-message compose, the thread's assignment, the WhatsApp
/// template list and the report form, each in the states a person reaches them in.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class InboxSheetScreenTests: ScreenSnapshotCase {
    /// The compose's size at its presentation site in the Inbox.
    private static let composeSize = CGSize(width: 520, height: 560)
    /// The assignment and template sheets size themselves (their `idealWidth` and `idealHeight`).
    private static let assignSize = CGSize(width: 460, height: 420)
    private static let templateSize = CGSize(width: 500, height: 440)
    /// The report form's size at both its presentation sites (a call, a conversation).
    private static let reportSize = CGSize(width: 440, height: 320)

    /// The first contact in `district-contacts.json`, a conversation in `district-conversations.json`.
    private static let threadKey = "contact:contact_contract_1"
    /// A member of `district-members.json` who may be assigned.
    private static let operatorEmail = "operator@contract.test"

    // MARK: - Compose

    func testCompose() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("new", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.composeSize
            ) { app in
                Self.compose(app) { _ in }
            }
        }
        // A number typed in the To box: the "Message …" row above the contacts it matches.
        try await assertView("typed-en", rules: ScreenRules.loaded, size: Self.composeSize) { app in
            Self.compose(app) { model in model.query = "416555" }
        }
        // A contact chosen: the channel and the message box.
        try await assertView("contact-en", rules: ScreenRules.loaded, size: Self.composeSize) { app in
            Self.compose(app) { model in
                if let contact = model.matches.first {
                    model.choose(contact)
                }
            }
        }
        // ⚠️ THE SEND REFUSED. The typed message lives in the sheet's own `@State`, out of a
        // test's reach, so the box is empty under the failure the model keeps.
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.composeSize
        ) { app in
            Self.compose(app) { model in
                if let contact = model.matches.first {
                    model.choose(contact)
                }
                _ = await model.send(body: "Your appointment is confirmed for Thursday.", subject: "Appointment")
            }
        }
    }

    /// The compose, and `then` run on its model once the sheet's own read of the contact
    /// window has answered (``ComposeModel/prepare()`` resets the model first).
    private static func compose(
        _ app: SignedInApp,
        then action: @escaping @MainActor (ComposeModel) async -> Void
    ) -> AnyView {
        let model = ComposeModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
        once({
            if case .ready = model.contactsState {
                return true
            }
            return false
        }, { await action(model) })
        return AnyView(ComposeSheet(model: model, onSent: { _ in })
            .macSheetSize(width: composeSize.width, height: composeSize.height)
            .districtTheme())
    }

    // MARK: - Assign

    func testAssign() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("members", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.assignSize
            ) { app in
                Self.assign(app, current: nil)
            }
        }
        // Assigned already: the tick on the operator's row.
        try await assertView("assigned-en", rules: ScreenRules.loaded, size: Self.assignSize) { app in
            Self.assign(app, current: Self.operatorEmail)
        }
        // The assignment refused: the sheet stays up and says so.
        try await assertView(
            "failed-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.assignSize
        ) { app in
            Self.assign(app, current: nil) { model in
                _ = await model.assign(Self.operatorEmail)
            }
        }
        try await assertView("load-failed-en", rules: ScreenRules.failing, size: Self.assignSize) { app in
            Self.assign(app, current: nil)
        }
    }

    private static func assign(
        _ app: SignedInApp,
        current: String?,
        then action: (@MainActor (ThreadAssignModel) async -> Void)? = nil
    ) -> AnyView {
        let model = ThreadAssignModel(
            inbox: app.container.inbox,
            workspaces: app.container.workspaces,
            workspaceId: app.workspaceId,
            threadKey: threadKey,
            current: current
        )
        if let action {
            once({
                if case .ready = model.members {
                    return true
                }
                return false
            }, { await action(model) })
        }
        return AnyView(ThreadAssignSheet(model: model, onAssigned: {}).districtTheme())
    }

    // MARK: - WhatsApp templates

    func testWhatsAppTemplates() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("list", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.templateSize
            ) { app in
                Self.templates(app)
            }
        }
        try await assertView("failed-en", rules: ScreenRules.failing, size: Self.templateSize) { app in
            Self.templates(app)
        }
    }

    private static func templates(_ app: SignedInApp) -> AnyView {
        let model = ThreadModel(
            container: app.container,
            workspaceId: app.workspaceId,
            role: .agency,
            threadKey: "addr:14165550177",
            replyTargets: [ReplyTarget(to: "+14165550177", channel: MessageChannel.whatsapp)]
        )
        return AnyView(WhatsAppTemplateSheet(model: model).districtTheme())
    }

    // MARK: - Report

    func testReport() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("call", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.reportSize
            ) { app in
                Self.report(app, target: .call(callId: "call_contract_answered"))
            }
        }
        try await assertView("conversation-en", rules: ScreenRules.loaded, size: Self.reportSize) { app in
            Self.report(app, target: .conversation(threadKey: Self.threadKey, name: "Contract Test Caller"))
        }
    }

    private static func report(_ app: SignedInApp, target: ReportTarget) -> AnyView {
        AnyView(ReportSheet(container: app.container, workspaceId: app.workspaceId, target: target)
            .macSheetSize(width: reportSize.width, height: reportSize.height)
            .districtTheme())
    }
}
