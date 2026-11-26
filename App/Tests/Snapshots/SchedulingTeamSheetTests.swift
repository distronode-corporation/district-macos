import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The team screen's three write sheets: a team's editor (create, rename and delete), its
/// members, and closing one person's scheduler account, each opened over the recorded
/// `teams.list` and `users.list` rows, as the team screen opens them.
final class SchedulingTeamSheetTests: SchedulingSheetSnapshotCase {
    // MARK: - Team editor

    func testCreate() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingTeamEditorSheet(model: Self.editor(app, team: nil), teamName: "") {})
        }
        try await sheet("no-name") { app in
            let model = Self.editor(app, team: nil)
            await model.submit()
            return AnyView(SchedulingTeamEditorSheet(model: model, teamName: "") {})
        }
        try await sheet("failed", rules: [Self.failing("teams.create")]) { app in
            let model = Self.editor(app, team: nil)
            model.editName("Support")
            await model.submit()
            return AnyView(SchedulingTeamEditorSheet(model: model, teamName: "") {})
        }
    }

    func testRename() async throws {
        try await sheetInBothLanguages("edit") { app in
            let team = try await Self.team(app, at: 0)
            return AnyView(SchedulingTeamEditorSheet(model: Self.editor(app, team: team), teamName: team.name) {})
        }
        let renamed: [FixtureTransport.Rule] = [
            .scheduling("teams.patch", .fixture("mobile/district-scheduling-team.json")),
        ]
        try await sheet("renamed", rules: renamed) { app in
            let team = try await Self.team(app, at: 1)
            let model = Self.editor(app, team: team)
            model.editName("Support desk")
            await model.submit()
            return AnyView(SchedulingTeamEditorSheet(model: model, teamName: team.name) {})
        }
        try await sheet("delete-failed", rules: [Self.failing("teams.delete")]) { app in
            let team = try await Self.team(app, at: 0)
            let model = Self.editor(app, team: team)
            await model.delete()
            return AnyView(SchedulingTeamEditorSheet(model: model, teamName: team.name) {})
        }
    }

    // MARK: - Members

    /// The recorded Sales team, whose two members leave nobody in the user list to add.
    func testMembers() async throws {
        try await sheetInBothLanguages("roster") { app in
            try await AnyView(SchedulingTeamMembersSheet(model: Self.members(app, team: 0)) {})
        }
        try await sheet("bad-priority") { app in
            let model = try await Self.members(app, team: 0)
            model.editPriority("-1", for: "sched-user-rotation")
            await model.savePriority(for: "sched-user-rotation")
            return AnyView(SchedulingTeamMembersSheet(model: model) {})
        }
        // ⚠️ THE FAILURE LINE SITS UNDER THE ROSTER, below the sheet's fold; the image shows the
        // priority as it was typed when the write failed.
        try await sheet("priority-failed", rules: [Self.failing("teams.members.patch")]) { app in
            let model = try await Self.members(app, team: 0)
            model.editPriority("1", for: "sched-user-rotation")
            await model.savePriority(for: "sched-user-rotation")
            return AnyView(SchedulingTeamMembersSheet(model: model) {})
        }
    }

    /// The recorded Support team, with no members, and the one live user offered to it.
    func testMembersOfAnEmptyTeam() async throws {
        try await sheet("empty") { app in
            try await AnyView(SchedulingTeamMembersSheet(model: Self.members(app, team: 1)) {})
        }
        try await sheet("picked") { app in
            let model = try await Self.members(app, team: 1)
            model.pick("sched-user-contract")
            return AnyView(SchedulingTeamMembersSheet(model: model) {})
        }
        // On the empty team, so the user list's failure is not pushed below the fold by a roster.
        try await sheet("users-failed", rules: [Self.failing("users.list")]) { app in
            try await AnyView(SchedulingTeamMembersSheet(model: Self.members(app, team: 1)) {})
        }
        try await sheet("add-failed", rules: [Self.failing("teams.members.add")]) { app in
            let model = try await Self.members(app, team: 1)
            model.pick("sched-user-contract")
            await model.addMember()
            return AnyView(SchedulingTeamMembersSheet(model: model) {})
        }
    }

    // MARK: - Archive

    /// The recorded user with one upcoming booking, which keeps the account open.
    func testArchive() async throws {
        try await sheetInBothLanguages("blocked") { app in
            AnyView(SchedulingUserArchiveSheet(model: Self.archive(app), userName: Self.userName) {})
        }
        let none: [FixtureTransport.Rule] = [
            .scheduling("users.upcomingBookings", .emptied("mobile/district-scheduling-user-upcoming.json")),
        ]
        try await sheet("clear", rules: none) { app in
            AnyView(SchedulingUserArchiveSheet(model: Self.archive(app), userName: Self.userName) {})
        }
        try await sheet("failed", rules: none + [Self.failing("users.archive")]) { app in
            let model = Self.archive(app)
            await model.loadUpcoming()
            await model.archive()
            return AnyView(SchedulingUserArchiveSheet(model: model, userName: Self.userName) {})
        }
        let archived: [FixtureTransport.Rule] = [
            .scheduling("users.archive", .fixture("mobile/district-scheduling-user-archive.json")),
        ]
        try await sheet("archived", rules: none + archived) { app in
            let model = Self.archive(app)
            await model.loadUpcoming()
            await model.archive()
            return AnyView(SchedulingUserArchiveSheet(model: model, userName: Self.userName) {})
        }
        try await sheet("upcoming-failed", rules: [Self.failing("users.upcomingBookings")]) { app in
            AnyView(SchedulingUserArchiveSheet(model: Self.archive(app), userName: Self.userName) {})
        }
    }

    // MARK: - Models

    private static let userName = "Contract Member"

    /// A row of the recorded `teams.list`.
    private static func team(_ app: SignedInApp, at index: Int) async throws -> SchedulingTeam {
        let rows = try await app.container.schedulingAdmin.teams(workspaceId: app.workspaceId)
        return try XCTUnwrap(rows.indices.contains(index) ? rows[index] : nil)
    }

    private static func editor(_ app: SignedInApp, team: SchedulingTeam?) -> SchedulingTeamEditorModel {
        SchedulingTeamEditorModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            team: team,
            onSaved: { _ in },
            onDeleted: { _ in }
        )
    }

    private static func members(_ app: SignedInApp, team index: Int) async throws -> SchedulingTeamMembersModel {
        try await SchedulingTeamMembersModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            team: team(app, at: index)
        ) { _ in }
    }

    private static func archive(_ app: SignedInApp) -> SchedulingUserArchiveModel {
        SchedulingUserArchiveModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            userId: "sched-user-contract",
            userName: userName,
            timezone: "America/Toronto"
        ) { _ in }
    }
}
