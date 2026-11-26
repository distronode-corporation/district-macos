import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The scheduling settings' four write sheets: the booking page's branding, the booking
/// assistant, the caller's own profile and their email notifications, each filled from the
/// recorded read its tab hands it.
///
/// ⚠️ BRANDING, PROFILE AND NOTIFICATIONS ARE TALLER THAN THE SHEET, and their refusal and outcome
/// lines sit below its fold, so those images show the form as it stood when the save answered:
/// the edited field, and the values the service echoed back.
final class SchedulingSettingsSheetTests: SchedulingSheetSnapshotCase {
    // MARK: - Branding

    func testBranding() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingBrandingSheet(model: Self.branding(app)) {})
        }
        try await sheet("refused") { app in
            let model = try await Self.branding(app)
            model.editPrivacyUrl("privacy page")
            await model.save()
            return AnyView(SchedulingBrandingSheet(model: model) {})
        }
        try await sheet("failed", rules: [Self.failing("settings.branding.patch")]) { app in
            let model = try await Self.branding(app)
            model.editBusinessName("Contract Agency Inc.")
            await model.save()
            return AnyView(SchedulingBrandingSheet(model: model) {})
        }
        let saved: [FixtureTransport.Rule] = [
            .scheduling("settings.branding.patch", .fixture("mobile/district-scheduling-branding.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let model = try await Self.branding(app)
            await model.save()
            return AnyView(SchedulingBrandingSheet(model: model) {})
        }
    }

    // MARK: - Booking assistant

    func testAutomation() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingAutomationSheet(model: Self.automation(app)) {})
        }
        try await sheet("edited") { app in
            let model = try await Self.automation(app)
            model.editAssistant(false)
            return AnyView(SchedulingAutomationSheet(model: model) {})
        }
        try await sheet("too-long") { app in
            let model = try await Self.automation(app)
            model.editInstructions(String(
                repeating: "a",
                count: SchedulingSettingsWriteCopy.assistantInstructionsLimit + 1
            ))
            await model.save()
            return AnyView(SchedulingAutomationSheet(model: model) {})
        }
        try await sheet("failed", rules: [Self.failing("settings.llm.patch")]) { app in
            let model = try await Self.automation(app)
            model.editAssistant(false)
            await model.save()
            return AnyView(SchedulingAutomationSheet(model: model) {})
        }
        let saved: [FixtureTransport.Rule] = [
            .scheduling("settings.llm.patch", .fixture("mobile/district-scheduling-llm.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let model = try await Self.automation(app)
            model.editInstructions("List the agreed next steps first.")
            await model.save()
            return AnyView(SchedulingAutomationSheet(model: model) {})
        }
    }

    // MARK: - Profile

    func testProfile() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingProfileSheet(model: Self.profile(app)) {})
        }
        try await sheet("no-name") { app in
            let model = try await Self.profile(app)
            model.editName(" ")
            await model.save()
            return AnyView(SchedulingProfileSheet(model: model) {})
        }
        try await sheet("failed", rules: [Self.failing("me.patch")]) { app in
            let model = try await Self.profile(app)
            model.editTimeFormat("12h")
            await model.save()
            return AnyView(SchedulingProfileSheet(model: model) {})
        }
        let saved: [FixtureTransport.Rule] = [
            .scheduling("me.patch", .fixture("mobile/district-scheduling-me.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let model = try await Self.profile(app)
            await model.save()
            return AnyView(SchedulingProfileSheet(model: model) {})
        }
    }

    // MARK: - Notifications

    func testNotifications() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingNotificationsSheet(model: Self.notifications(app)) {})
        }
        try await sheet("failed", rules: [Self.failing("me.patch")]) { app in
            let model = try await Self.notifications(app)
            model.editReschedule(true)
            await model.save()
            return AnyView(SchedulingNotificationsSheet(model: model) {})
        }
        let saved: [FixtureTransport.Rule] = [
            .scheduling("me.patch", .fixture("mobile/district-scheduling-me.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let model = try await Self.notifications(app)
            await model.save()
            return AnyView(SchedulingNotificationsSheet(model: model) {})
        }
    }

    // MARK: - Models

    private static func branding(_ app: SignedInApp) async throws -> SchedulingBrandingModel {
        let admin = app.container.schedulingAdmin
        return try await SchedulingBrandingModel(
            admin: admin,
            media: app.container.schedulingAdminMedia,
            workspaceId: app.workspaceId,
            branding: admin.branding(workspaceId: app.workspaceId)
        ) { _ in }
    }

    private static func automation(_ app: SignedInApp) async throws -> SchedulingAutomationModel {
        let admin = app.container.schedulingAdmin
        return try await SchedulingAutomationModel(
            admin: admin,
            workspaceId: app.workspaceId,
            llm: admin.llmSettings(workspaceId: app.workspaceId)
        ) {}
    }

    private static func me(_ app: SignedInApp) async throws -> SchedulingMe {
        try await app.container.schedulingAdmin.me(workspaceId: app.workspaceId)
    }

    private static func profile(_ app: SignedInApp) async throws -> SchedulingProfileModel {
        try await SchedulingProfileModel(
            admin: app.container.schedulingAdmin,
            media: app.container.schedulingAdminMedia,
            workspaceId: app.workspaceId,
            me: me(app)
        ) { _ in }
    }

    private static func notifications(_ app: SignedInApp) async throws -> SchedulingNotificationsModel {
        try await SchedulingNotificationsModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            me: me(app)
        ) { _ in }
    }
}
