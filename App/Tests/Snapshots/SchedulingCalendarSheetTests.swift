import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The calendar screen's two write sheets: connecting a CalDAV calendar, and choosing which of a
/// connection's calendars are checked for conflicts and which one takes new bookings.
final class SchedulingCalendarSheetTests: SchedulingSheetSnapshotCase {
    // MARK: - CalDAV

    func testCaldav() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingCaldavConnectSheet(model: Self.caldav(app)))
        }
        try await sheet("custom-server") { app in
            let model = Self.caldav(app)
            model.preset = .custom
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
        try await sheet("server-not-https") { app in
            let model = Self.caldav(app)
            model.preset = .custom
            model.serverURL = "http://dav.contract.test"
            await model.connect()
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
        try await sheet("no-username") { app in
            let model = Self.caldav(app)
            await model.connect()
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
        try await sheet("failed", rules: [Self.failing("calendar.caldav.connect")]) { app in
            let model = Self.filledCaldav(app)
            await model.connect()
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
        // The recorded scheduler refusal (`ok: false`), which the sheet tells as the provider
        // refusing the credentials rather than as an outage.
        let refused: [FixtureTransport.Rule] = [
            .scheduling("calendar.caldav.connect", .fixture("mobile/district-scheduling-admin-failure.json")),
        ]
        try await sheet("refused", rules: refused) { app in
            let model = Self.filledCaldav(app)
            await model.connect()
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
        let connected: [FixtureTransport.Rule] = [
            .scheduling("calendar.caldav.connect", .fixture("mobile/district-scheduling-caldav-connect.json")),
        ]
        try await sheet("connected", rules: connected) { app in
            let model = Self.filledCaldav(app)
            await model.connect()
            return AnyView(SchedulingCaldavConnectSheet(model: model))
        }
    }

    // MARK: - Calendar picker

    func testPicker() async throws {
        try await sheetInBothLanguages("loaded") { app in
            try await AnyView(SchedulingCalendarPickerSheet(model: Self.picker(app)))
        }
        try await sheet("load-failed", rules: [Self.failing("calendar.connections.calendars.get")]) { app in
            try await AnyView(SchedulingCalendarPickerSheet(model: Self.picker(app)))
        }
        try await sheet("failed", rules: [Self.failing("calendar.connections.calendars.put")]) { app in
            let model = try await Self.picker(app)
            afterLoad(model.rows != nil) {
                model.setCheckConflicts("holidays@group.v.calendar.google.test", on: true)
                await model.save()
            }
            return AnyView(SchedulingCalendarPickerSheet(model: model))
        }
        // ⚠️ BOTH WRITES ANSWER THE RECORDED EMPTY SUCCESS (`{"ok": true}`): the corpus records no
        // answer of their own, and the sheet reads nothing from either.
        let saved: [FixtureTransport.Rule] = [
            .scheduling("calendar.connections.calendars.put", .fixture("mobile/district-scheduling-ok.json")),
            .scheduling("calendar.connections.destination", .fixture("mobile/district-scheduling-ok.json")),
        ]
        try await sheet("saved", rules: saved) { app in
            let model = try await Self.picker(app)
            afterLoad(model.rows != nil) {
                await model.save()
            }
            return AnyView(SchedulingCalendarPickerSheet(model: model))
        }
    }

    // MARK: - Models

    private static func caldav(_ app: SignedInApp) -> SchedulingCaldavConnectModel {
        SchedulingCaldavConnectModel(repository: app.container.schedulingAdmin, workspaceId: app.workspaceId) {}
    }

    /// The iCloud preset with the recorded account's address and a made-up app password.
    private static func filledCaldav(_ app: SignedInApp) -> SchedulingCaldavConnectModel {
        let model = caldav(app)
        model.username = "contract@fastmail.test"
        model.appPassword = "abcd-efgh-ijkl-mnop"
        return model
    }

    /// The recorded `calendar.status`'s first connection, as the calendar screen hands it.
    private static func picker(_ app: SignedInApp) async throws -> SchedulingCalendarPickerModel {
        let admin = app.container.schedulingAdmin
        let status = try await admin.calendarStatus(workspaceId: app.workspaceId)
        let connection = try XCTUnwrap(status.connections.first)
        return SchedulingCalendarPickerModel(
            repository: admin,
            workspaceId: app.workspaceId,
            connection: connection
        ) {}
    }
}
