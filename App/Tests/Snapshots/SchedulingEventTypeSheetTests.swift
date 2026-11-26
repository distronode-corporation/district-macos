import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The event type's write sheets: the editor (create and edit), the state actions, the hosts
/// and the booking questions, each opened over the recorded `eventTypes.get` row, as the detail
/// screen opens them.
///
/// ⚠️ THE QUESTION EDITOR IS NOT DRAWN: it is a sheet the questions sheet presents over itself,
/// private to it, which a window drawn in-process does not show.
final class SchedulingEventTypeSheetTests: SchedulingSheetSnapshotCase {
    // MARK: - Editor

    func testCreate() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingEventTypeEditorSheet(model: Self.editor(app, editing: nil)))
        }
        try await sheet("refused") { app in
            let model = Self.editor(app, editing: nil)
            await model.save()
            return AnyView(SchedulingEventTypeEditorSheet(model: model))
        }
        try await sheet("failed", rules: [Self.failing("eventTypes.create")]) { app in
            let model = Self.editor(app, editing: nil)
            model.form.name = "Site visit"
            await model.save()
            return AnyView(SchedulingEventTypeEditorSheet(model: model))
        }
    }

    func testEdit() async throws {
        try await sheetInBothLanguages("edit") { app in
            try await AnyView(SchedulingEventTypeEditorSheet(model: Self.editor(app, editing: Self.eventType(app))))
        }
        try await sheet("refused") { app in
            let model = try await Self.editor(app, editing: Self.eventType(app))
            model.form.duration = "0"
            await model.save()
            return AnyView(SchedulingEventTypeEditorSheet(model: model))
        }
    }

    // MARK: - Actions

    func testActions() async throws {
        try await sheetInBothLanguages("active") { app in
            try await AnyView(SchedulingEventTypeActionsSheet(model: Self.actions(app)))
        }
        // ⚠️ THE PATCH IS ANSWERED WITH THE RECORDED ROW TURNED OFF: the service echoes the row
        // it wrote, and the corpus records only the active one.
        let turnedOff: [FixtureTransport.Rule] = [
            .scheduling("eventTypes.patch", .edited("mobile/district-scheduling-event-type.json") { body in
                var data = body["data"] as? [String: Any] ?? [:]
                data["is_active"] = false
                body["data"] = data
            }),
        ]
        try await sheet("turned-off", rules: turnedOff) { app in
            let model = try await Self.actions(app)
            await model.toggleActive()
            return AnyView(SchedulingEventTypeActionsSheet(model: model))
        }
        let sent: [FixtureTransport.Rule] = [
            .scheduling("eventTypes.testEmail", .fixture("mobile/district-scheduling-test-email.json")),
        ]
        try await sheet("test-email-sent", rules: sent) { app in
            let model = try await Self.actions(app)
            await model.sendTestEmail(type: "confirmation")
            return AnyView(SchedulingEventTypeActionsSheet(model: model))
        }
        try await sheet("delete-failed", rules: [Self.failing("eventTypes.delete")]) { app in
            let model = try await Self.actions(app)
            await model.delete()
            return AnyView(SchedulingEventTypeActionsSheet(model: model))
        }
    }

    // MARK: - Hosts

    func testHosts() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingEventTypeHostsSheet(model: Self.hosts(app)))
        }
        // ⚠️ AFTER THE CANDIDATES HAVE ANSWERED TOO (`canAddHosts`), the second read the sheet
        // makes: hosts removed before it answers would come back as candidates to add.
        try await sheet("no-host") { app in
            let model = try await Self.hosts(app)
            afterLoad(model.canAddHosts) {
                for row in model.rows {
                    model.remove(row.userId)
                }
                await model.save()
            }
            return AnyView(SchedulingEventTypeHostsSheet(model: model))
        }
        try await sheet("bad-priority") { app in
            let model = try await Self.hosts(app)
            afterLoad(model.canAddHosts) {
                model.setPriority("first", for: model.rows[0].userId)
                await model.save()
            }
            return AnyView(SchedulingEventTypeHostsSheet(model: model))
        }
        try await sheet("failed", rules: [Self.failing("eventTypes.hosts.put")]) { app in
            let model = try await Self.hosts(app)
            await model.load()
            await model.save()
            return AnyView(SchedulingEventTypeHostsSheet(model: model))
        }
        try await sheet("load-failed", rules: [Self.failing("eventTypes.hosts.get")]) { app in
            try await AnyView(SchedulingEventTypeHostsSheet(model: Self.hosts(app)))
        }
    }

    // MARK: - Questions

    func testQuestions() async throws {
        try await sheetInBothLanguages("loaded") { app in
            AnyView(SchedulingEventTypeQuestionsSheet(model: Self.questions(app)))
        }
        let none: [FixtureTransport.Rule] = [
            .scheduling("eventTypes.questions.list", .emptied("mobile/district-scheduling-questions.json")),
        ]
        try await sheet("none", rules: none) { app in
            AnyView(SchedulingEventTypeQuestionsSheet(model: Self.questions(app)))
        }
        try await sheet("load-failed", rules: [Self.failing("eventTypes.questions.list")]) { app in
            AnyView(SchedulingEventTypeQuestionsSheet(model: Self.questions(app)))
        }
        try await sheet("delete-failed", rules: [Self.failing("eventTypes.questions.delete")]) { app in
            let model = Self.questions(app)
            await model.load()
            let first = try XCTUnwrap(model.questions.first)
            model.beginDelete(first)
            await model.delete()
            return AnyView(SchedulingEventTypeQuestionsSheet(model: model))
        }
    }

    // MARK: - Models

    /// The recorded `eventTypes.get` row, which the detail screen hands every one of these.
    private static func eventType(_ app: SignedInApp) async throws -> SchedulingEventType {
        try await app.container.schedulingAdmin.eventType(workspaceId: app.workspaceId, slug: "phone-consultation")
    }

    /// ⚠️ THE TAKEN SLUGS ARE THE RECORDED LIST'S, which the list screen hands a create.
    private static func editor(_ app: SignedInApp, editing: SchedulingEventType?) -> SchedulingEventTypeEditorModel {
        SchedulingEventTypeEditorModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            editing: editing,
            takenSlugs: ["phone-consultation"]
        ) { _ in }
    }

    private static func actions(_ app: SignedInApp) async throws -> SchedulingEventTypeActionsModel {
        try await SchedulingEventTypeActionsModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            eventType: eventType(app)
        ) { _ in }
    }

    private static func hosts(_ app: SignedInApp) async throws -> SchedulingEventTypeHostsModel {
        try await SchedulingEventTypeHostsModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            eventType: eventType(app)
        ) { _ in }
    }

    private static func questions(_ app: SignedInApp) -> SchedulingEventTypeQuestionsModel {
        SchedulingEventTypeQuestionsModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            slug: "phone-consultation"
        ) { _ in }
    }
}
