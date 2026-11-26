import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The Developer tab's write sheets: the API key create sheet and the one-time reveal of the
/// key it mints, and the webhook editor (add and edit) and the one-time reveal of its secret.
///
/// ⚠️ THE TWO REVEALS ARE DRAWN ON THEIR OWN. Each is a sheet the create sheet presents over
/// itself, which a window drawn in-process does not show, so the create is run against the
/// recorded answer and the reveal is built from what the model kept.
///
/// ⚠️ THE WEBHOOK EDITOR'S OUTCOME LINE SITS UNDER ITS 26 SWITCHES, below the sheet's fold, so its
/// failed and saved images show the form as it stood when the write answered.
final class SchedulingDeveloperSheetTests: SchedulingSheetSnapshotCase {
    // MARK: - API key

    func testAPIKeyCreate() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingAPIKeyCreateSheet(model: Self.keyModel(app)))
        }
        try await sheet("named") { app in
            let model = Self.keyModel(app)
            model.name = "Zapier"
            return AnyView(SchedulingAPIKeyCreateSheet(model: model))
        }
    }

    func testAPIKeyCreateFailed() async throws {
        let rules = [Self.failing("apiKeys.create")]
        try await sheet("failed", rules: rules) { app in
            let model = Self.keyModel(app)
            model.name = "Zapier"
            await model.create()
            return AnyView(SchedulingAPIKeyCreateSheet(model: model))
        }
        // The failure line's Retry with the name cleared: the one way the name check is reached,
        // since the create button is off while the name is empty.
        try await sheet("retried-without-a-name", rules: rules) { app in
            let model = Self.keyModel(app)
            model.name = "Zapier"
            await model.create()
            model.name = " "
            await model.create()
            return AnyView(SchedulingAPIKeyCreateSheet(model: model))
        }
    }

    func testAPIKeyReveal() async throws {
        let rules: [FixtureTransport.Rule] = [
            .scheduling("apiKeys.create", .fixture("mobile/district-scheduling-api-key-created.json")),
        ]
        try await sheetInBothLanguages("minted", rules: rules) { app in
            try await Self.revealed(app, copied: false)
        }
        try await sheet("copied", rules: rules) { app in
            try await Self.revealed(app, copied: true)
        }
    }

    // MARK: - Webhook

    func testWebhookAdd() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingWebhookEditorSheet(model: Self.webhookModel(app, mode: .create)))
        }
        try await sheet("refused") { app in
            let model = Self.webhookModel(app, mode: .create)
            model.draft.url = "http://localhost:8080/hook"
            await model.submit()
            return AnyView(SchedulingWebhookEditorSheet(model: model))
        }
        try await sheet("failed", rules: [Self.failing("webhooks.create")]) { app in
            let model = Self.webhookModel(app, mode: .create)
            model.draft.url = "https://hooks.contract.test/bookings"
            model.draft.events = [.bookingCreated, .bookingCancelled]
            await model.submit()
            return AnyView(SchedulingWebhookEditorSheet(model: model))
        }
    }

    func testWebhookSecret() async throws {
        let rules: [FixtureTransport.Rule] = [
            .scheduling("webhooks.create", .fixture("mobile/district-scheduling-webhook-created.json")),
        ]
        try await sheetInBothLanguages("minted", rules: rules) { app in
            let model = Self.webhookModel(app, mode: .create)
            model.draft.url = "https://hooks.contract.test/bookings"
            model.draft.events = [.bookingCreated, .bookingCancelled]
            await model.submit()
            let secret = try XCTUnwrap(model.minted)
            return AnyView(SchedulingWebhookSecretSheet(secret: secret))
        }
    }

    func testWebhookEdit() async throws {
        try await sheetInBothLanguages("edit") { app in
            let hook = try await Self.webhook(app, at: 0)
            return AnyView(SchedulingWebhookEditorSheet(model: Self.webhookModel(app, mode: .edit(hook))))
        }
        // The recorded second webhook listens only for `recording.completed`, which the editor
        // no longer offers, and names no fields, so no event is ticked and the defaults are.
        try await sheet("unoffered-event") { app in
            let hook = try await Self.webhook(app, at: 1)
            return AnyView(SchedulingWebhookEditorSheet(model: Self.webhookModel(app, mode: .edit(hook))))
        }
        // ⚠️ AN EVENT THIS BUILD DOES NOT KNOW, ADDED TO THE RECORDED FIRST WEBHOOK: the corpus
        // records none, and a newer scheduler can answer one, which the sheet names before a
        // save would drop it.
        let unknown: [FixtureTransport.Rule] = [
            .scheduling("webhooks.list", .edited("mobile/district-scheduling-webhooks.json") { body in
                var data = body["data"] as? [String: Any] ?? [:]
                var items = data["items"] as? [[String: Any]] ?? []
                items[0]["events"] = ["booking.created", "booking.paid"]
                data["items"] = items
                body["data"] = data
            }),
        ]
        try await sheet("unknown-event", rules: unknown) { app in
            let hook = try await Self.webhook(app, at: 0)
            return AnyView(SchedulingWebhookEditorSheet(model: Self.webhookModel(app, mode: .edit(hook))))
        }
        // ⚠️ THE PATCH IS ANSWERED WITH THE RECORDED CREATE: the corpus records no
        // `webhooks.patch` answer, and the create's row is the same webhook with its secret.
        let saved: [FixtureTransport.Rule] = [
            .scheduling("webhooks.patch", .fixture("mobile/district-scheduling-webhook-created.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let hook = try await Self.webhook(app, at: 0)
            let model = Self.webhookModel(app, mode: .edit(hook))
            await model.submit()
            return AnyView(SchedulingWebhookEditorSheet(model: model))
        }
    }

    // MARK: - Models

    private static func keyModel(_ app: SignedInApp) -> SchedulingAPIKeyCreateModel {
        SchedulingAPIKeyCreateModel(repository: app.container.schedulingAdmin, workspaceId: app.workspaceId) {}
    }

    private static func revealed(_ app: SignedInApp, copied: Bool) async throws -> AnyView {
        let model = keyModel(app)
        model.name = "Zapier"
        await model.create()
        if copied {
            model.markCopied()
        }
        let minted = try XCTUnwrap(model.minted)
        return AnyView(SchedulingAPIKeyRevealSheet(minted: minted, model: model))
    }

    private static func webhookModel(
        _ app: SignedInApp,
        mode: SchedulingWebhookEditorModel.ModeC
    ) -> SchedulingWebhookEditorModel {
        SchedulingWebhookEditorModel(
            repository: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            mode: mode
        ) {}
    }

    /// A row of the recorded `webhooks.list`, as the Developer tab hands it to the editor.
    private static func webhook(_ app: SignedInApp, at index: Int) async throws -> SchedulingWebhook {
        let rows = try await app.container.schedulingAdmin.webhooks(workspaceId: app.workspaceId)
        return try XCTUnwrap(rows.indices.contains(index) ? rows[index] : nil)
    }
}
