import DistrictData
@testable import DistrictMac
import SwiftUI
import XCTest

/// The working-hours screen's two write sheets: the week editor and the days-off list, each
/// reading its own copy of the recorded rules and overrides when it opens.
///
/// ⚠️ THE ADD-A-DAY-OFF FORM IS NOT DRAWN: it is a sheet the days-off sheet presents over
/// itself, private to it, which a window drawn in-process does not show.
final class SchedulingHoursSheetTests: SchedulingSheetSnapshotCase {
    /// ⚠️ THE OPERATOR'S DAY, PINNED before the two recorded overrides (24 and 25 September
    /// 2026), so both are upcoming on every run.
    private static let today = "2026-09-20"

    // MARK: - Week

    func testWeek() async throws {
        try await sheetInBothLanguages("loaded") { app in
            AnyView(SchedulingAvailabilityRulesSheet(model: Self.rules(app)))
        }
        // An end before its start on Monday, the recorded day with a range, drawn under it.
        try await sheet("end-before-start") { app in
            let model = Self.rules(app)
            afterLoad(!model.stored.isEmpty) {
                if let range = model.week[0].first {
                    model.setEnd("08:00", for: range.id, inRow: 0)
                }
            }
            return AnyView(SchedulingAvailabilityRulesSheet(model: model))
        }
        try await sheet("failed", rules: [Self.failing("availability.rules.patch")]) { app in
            let model = Self.rules(app)
            await model.load()
            if let range = model.week[0].first {
                model.setEnd("18:00", for: range.id, inRow: 0)
            }
            await model.save()
            return AnyView(SchedulingAvailabilityRulesSheet(model: model))
        }
        try await sheet("load-failed", rules: [Self.failing("availability.rules.list")]) { app in
            AnyView(SchedulingAvailabilityRulesSheet(model: Self.rules(app)))
        }
    }

    // MARK: - Days off

    func testDaysOff() async throws {
        try await sheetInBothLanguages("loaded") { app in
            AnyView(SchedulingAvailabilityOverridesSheet(model: Self.overrides(app, today: Self.today)))
        }
        // A day after both recorded overrides: nothing upcoming is left to list.
        try await sheet("none-upcoming") { app in
            AnyView(SchedulingAvailabilityOverridesSheet(model: Self.overrides(app, today: "2026-10-01")))
        }
        try await sheet("delete-failed", rules: [Self.failing("availability.overrides.delete")]) { app in
            let model = Self.overrides(app, today: Self.today)
            await model.load()
            let single = try XCTUnwrap(model.rows.first { $0.kind == .single })
            model.beginDelete(single)
            await model.delete()
            return AnyView(SchedulingAvailabilityOverridesSheet(model: model))
        }
        try await sheet("load-failed", rules: [Self.failing("availability.overrides.list")]) { app in
            AnyView(SchedulingAvailabilityOverridesSheet(model: Self.overrides(app, today: Self.today)))
        }
    }

    // MARK: - Models

    private static func rules(_ app: SignedInApp) -> SchedulingAvailabilityRulesModel {
        SchedulingAvailabilityRulesModel(admin: app.container.schedulingAdmin, workspaceId: app.workspaceId) { _ in }
    }

    private static func overrides(_ app: SignedInApp, today: String) -> SchedulingAvailabilityOverridesModel {
        SchedulingAvailabilityOverridesModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            today: today
        ) { _ in }
    }
}
