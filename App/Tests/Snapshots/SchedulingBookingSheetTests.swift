import DistrictData
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// A booking's three write sheets: cancel, reschedule and reassign, each opened over the
/// recorded `bookings.list` row `bk-contract-1`, as the bookings list opens them.
final class SchedulingBookingSheetTests: SchedulingSheetSnapshotCase {
    private static let bookingId = "bk-contract-1"

    // MARK: - Cancel

    func testCancel() async throws {
        try await sheetInBothLanguages("new") { app in
            AnyView(SchedulingBookingCancelSheet(model: Self.cancel(app)) {})
        }
        try await sheet("reason-too-long") { app in
            let model = Self.cancel(app)
            model.editReason(String(repeating: "a", count: SchedulingBookingCancelModel.reasonLimit + 1))
            await model.submit()
            return AnyView(SchedulingBookingCancelSheet(model: model) {})
        }
        try await sheet("failed", rules: [Self.failing("bookings.cancel")]) { app in
            let model = Self.cancel(app)
            model.editReason("Customer asked to postpone")
            await model.submit()
            return AnyView(SchedulingBookingCancelSheet(model: model) {})
        }
        let done: [FixtureTransport.Rule] = [
            .scheduling("bookings.cancel", .fixture("mobile/district-scheduling-booking.json")),
        ]
        try await sheet("done", rules: done) { app in
            let model = Self.cancel(app)
            model.editReason("Customer asked to postpone")
            await model.submit()
            return AnyView(SchedulingBookingCancelSheet(model: model) {})
        }
    }

    // MARK: - Reschedule

    func testReschedule() async throws {
        try await sheetInBothLanguages("slots") { app in
            AnyView(SchedulingBookingRescheduleSheet(model: Self.reschedule(app)) {})
        }
        try await sheet("picked") { app in
            let model = Self.reschedule(app)
            afterLoad(!Self.slots(model).isEmpty) {
                model.select(Self.slots(model)[0])
            }
            return AnyView(SchedulingBookingRescheduleSheet(model: model) {})
        }
        let none: [FixtureTransport.Rule] = [
            .scheduling("eventTypes.slots", .emptied("mobile/district-scheduling-slots.json")),
        ]
        try await sheet("no-slots", rules: none) { app in
            AnyView(SchedulingBookingRescheduleSheet(model: Self.reschedule(app)) {})
        }
        try await sheet("slots-failed", rules: [Self.failing("eventTypes.slots")]) { app in
            AnyView(SchedulingBookingRescheduleSheet(model: Self.reschedule(app)) {})
        }
        try await sheet("failed", rules: [Self.failing("bookings.reschedule")]) { app in
            let model = Self.reschedule(app)
            afterLoad(!Self.slots(model).isEmpty) {
                model.select(Self.slots(model)[0])
                await model.submit()
            }
            return AnyView(SchedulingBookingRescheduleSheet(model: model) {})
        }
    }

    // MARK: - Reassign

    /// ⚠️ THE RECORDED USER LIST HOLDS ONE LIVE HOST, `bk-contract-1`'s OWN, so that booking
    /// has nobody to move to. The picker is drawn for a booking whose host the scheduler did
    /// not name (`bk-contract-2`'s `host_id` is null), which leaves that host in it.
    func testReassign() async throws {
        try await sheet("no-other-host") { app in
            AnyView(SchedulingBookingReassignSheet(model: Self.reassign(app, from: "sched-user-contract")) {})
        }
        try await sheetInBothLanguages("hosts") { app in
            AnyView(SchedulingBookingReassignSheet(model: Self.reassign(app, from: nil)) {})
        }
        try await sheet("picked") { app in
            let model = Self.reassign(app, from: nil)
            model.select("sched-user-contract")
            return AnyView(SchedulingBookingReassignSheet(model: model) {})
        }
        try await sheet("failed", rules: [Self.failing("bookings.reassign")]) { app in
            let model = Self.reassign(app, from: nil)
            model.select("sched-user-contract")
            await model.submit()
            return AnyView(SchedulingBookingReassignSheet(model: model) {})
        }
        try await sheet("hosts-failed", rules: [Self.failing("users.list")]) { app in
            AnyView(SchedulingBookingReassignSheet(model: Self.reassign(app, from: nil)) {})
        }
    }

    // MARK: - Models

    private static func cancel(_ app: SignedInApp) -> SchedulingBookingCancelModel {
        SchedulingBookingCancelModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            bookingId: bookingId
        ) { _ in }
    }

    /// ⚠️ THE DAY IS THE RECORDED SLOTS' DAY, 14 September 2026 in the scheduler's zone, so the
    /// calendar shows the month the slots are in on every run.
    private static func reschedule(_ app: SignedInApp) -> SchedulingBookingRescheduleModel {
        SchedulingBookingRescheduleModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            bookingId: bookingId,
            eventTypeSlug: "phone-consultation",
            timezone: "America/Toronto",
            startingFrom: Date(timeIntervalSince1970: 1_789_390_800) // 2026-09-14T13:00:00Z
        ) { _ in }
    }

    private static func slots(_ model: SchedulingBookingRescheduleModel) -> [SchedulingSlot] {
        guard case let .ready(rows) = model.slots else { return [] }
        return rows
    }

    private static func reassign(_ app: SignedInApp, from host: String?) -> SchedulingBookingReassignModel {
        SchedulingBookingReassignModel(
            admin: app.container.schedulingAdmin,
            workspaceId: app.workspaceId,
            bookingId: bookingId,
            currentHostId: host
        ) { _ in }
    }
}
