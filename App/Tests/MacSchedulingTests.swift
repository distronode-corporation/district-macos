import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The Mac's scheduling additions with no iOS original: the two sortable tables, the
/// navigator a table row opens through, and the settings hub's Scheduling row.
@MainActor
final class MacSchedulingTests: XCTestCase {
    // MARK: - The bookings table

    /// ⛔ NO SORT IS THE SERVER'S ORDER, UNTOUCHED: the pager appends in it.
    func test_MAC_SCHED_01_noSortKeepsTheServersOrder() throws {
        let rows = try [
            booking("b3", start: "2026-10-05T14:00:00Z", who: "Zed"),
            booking("b1", start: "2026-10-04T09:00:00Z", who: "Ada"),
            booking("b2", start: "2026-10-06T08:00:00Z", who: "Bea"),
        ]
        XCTAssertEqual(SchedulingBookingsTableRow.rows(rows, sortedBy: []).map(\.id), ["b3", "b1", "b2"])
    }

    /// ⛔ WHEN SORTS BY THE INSTANT, NOT BY THE DISPLAY STRING, and an unparseable stamp
    /// sorts as the distant past rather than being dropped.
    func test_MAC_SCHED_02_whenSortsByTheInstant() throws {
        let rows = try [
            booking("b3", start: "2026-10-05T14:00:00Z", who: "zed"),
            booking("b1", start: "2026-10-04T09:00:00Z", who: "Ada"),
            booking("bad", start: "not a date", who: "Bea"),
        ]
        let byWhen = SchedulingBookingsTableRow.rows(rows, sortedBy: [KeyPathComparator(\.instant)])
        XCTAssertEqual(byWhen.map(\.id), ["bad", "b1", "b3"])
        let byWho = SchedulingBookingsTableRow.rows(rows, sortedBy: [KeyPathComparator(\.who)])
        XCTAssertEqual(byWho.map(\.id), ["b1", "bad", "b3"], "case-insensitive, as Finder sorts")
        XCTAssertEqual(SchedulingBookingsTableRow(rows[2]).instant, .distantPast)
    }

    /// ⛔ THE CELLS SAY WHAT THE iPad's ROW SAYS: every value is the model's row, unchanged.
    func test_MAC_SCHED_03_aBookingCellReadsAsTheIPadsRow() throws {
        let row = try booking("b1", start: "2026-10-04T09:00:00Z", who: "Ada")
        let cell = SchedulingBookingsTableRow(row)
        XCTAssertEqual(cell.who, row.who)
        XCTAssertEqual(cell.eventType, row.eventType)
        XCTAssertEqual(cell.host, row.host)
        XCTAssertEqual(cell.status, row.status.label)
    }

    // MARK: - The event types table

    /// ⛔ DURATION SORTS BY LENGTH, NOT BY "90 min" AGAINST "15 min" AS TEXT.
    func test_MAC_SCHED_04_durationSortsByMinutes() throws {
        let types = try [eventType("e1", minutes: 90), eventType("e2", minutes: 15), eventType("e3", minutes: 30)]
        let rows = types.map { eventTypeRow($0) }
        XCTAssertEqual(
            SchedulingEventTypesTableRow.rows(rows, eventTypes: types, sortedBy: []).map(\.id),
            ["e1", "e2", "e3"]
        )
        let byLength = SchedulingEventTypesTableRow.rows(
            rows,
            eventTypes: types,
            sortedBy: [KeyPathComparator(\.minutes)]
        )
        XCTAssertEqual(byLength.map(\.id), ["e2", "e3", "e1"])
    }

    /// ⚠️ A ROW WHOSE TYPE IS NOT AMONG THE LOADED ONES SORTS FIRST, AND IS NOT DROPPED.
    func test_MAC_SCHED_05_aRowWithoutItsTypeIsKept() throws {
        let types = try [eventType("e1", minutes: 30)]
        let rows = try [eventTypeRow(types[0]), eventTypeRow(eventType("ghost", minutes: 45))]
        let sorted = SchedulingEventTypesTableRow.rows(
            rows,
            eventTypes: types,
            sortedBy: [KeyPathComparator(\.minutes)]
        )
        XCTAssertEqual(sorted.map(\.id), ["ghost", "e1"])
    }

    // MARK: - Opening a row

    /// ⛔ A TABLE ROW OPENS BY APPENDING, as the iPad's link does, so back lands on the table.
    func test_MAC_SCHED_06_theNavigatorAppendsToTheStack() {
        var path: [Route] = [.scheduling(workspaceId: "ws_1", role: .client, section: .bookings)]
        let navigator = ShellNavigator { path.append($0) }
        navigator.push(.scheduling(workspaceId: "ws_1", role: .client, section: .booking(id: "b1")))
        XCTAssertEqual(path, [
            .scheduling(workspaceId: "ws_1", role: .client, section: .bookings),
            .scheduling(workspaceId: "ws_1", role: .client, section: .booking(id: "b1")),
        ])
    }

    // MARK: - The settings hub's row

    /// ⛔ THE SETTINGS HUB'S SCHEDULING ROW OPENS THE SCHEDULING HUB ITSELF (Wave 8 showed
    /// the hand-off screen there as a stand-in), with the role carried.
    func test_MAC_SCHED_07_theSettingsHubRowOpensTheSchedulingHub() {
        let hub = SettingsHubView(workspaceId: "ws_1", role: .viewer)
        XCTAssertEqual(hub.destination(.scheduling), .scheduling(workspaceId: "ws_1", role: .viewer, section: .hub))
        XCTAssertEqual(
            hub.destination(.persona),
            .workspaceSettings(workspaceId: "ws_1", role: .viewer, section: .persona)
        )
    }

    // MARK: - Fixtures

    private func booking(_ id: String, start: String, who: String) throws -> SchedulingBookingsModel.Row {
        let json = """
        {"id":"\(id)","start_at":"\(start)","end_at":"\(start)","status":"confirmed",
         "host_name":"Host","attendees":[{"name":"\(who)","email":"x@example.com"}]}
        """
        let item = try JSONDecoder().decode(SchedulingBooking.self, from: Data(json.utf8))
        return SchedulingBookingsModel.Row(
            id: id,
            when: start,
            who: who,
            email: "x@example.com",
            eventType: "Intro",
            host: "Host",
            status: SchedulingBookingFormat.statusLabel(item.status),
            booking: item
        )
    }

    private func eventType(_ id: String, minutes: Int) throws -> SchedulingEventType {
        let json = #"{"id":"\#(id)","slug":"\#(id)-slug","name":"\#(id)","duration_minutes":\#(minutes)}"#
        return try JSONDecoder().decode(SchedulingEventType.self, from: Data(json.utf8))
    }

    private func eventTypeRow(_ item: SchedulingEventType) -> SchedulingEventTypesModel.Row {
        SchedulingEventTypesModel.Row(
            id: item.id,
            slug: item.slug,
            name: item.name,
            duration: "\(item.durationMinutes) min",
            interval: "",
            location: "",
            state: SchedulingBookingFormat.statusLabel("confirmed"),
            bookingPage: ""
        )
    }
}
