import DistrictModel
import SwiftUI

// The bookings and the event types as sortable tables, and the column they sit in.
//
// ⚠️ MAC ONLY. The iPad draws both lists as rows of a card (a title over a subtitle that
// joins three values with dots); a Mac window has the width to give each value its own
// column, and every column sorts. The column headings are the web dashboard's own
// (`BookingsTable` and `EventTypesTable`), and every cell says what the iPad's row says,
// from the same ``SchedulingBookingsModel/Row`` or ``SchedulingEventTypesModel/Row``.
//
// ⛔ A ROW OPENS LIKE THE iPad's LINK: a double-click or Return pushes the same route onto
// the same stack (``ShellNavigator``), so a back press lands on the table.

/// One booking as the table sorts it.
struct SchedulingBookingsTableRow: Identifiable {
    let row: SchedulingBookingsModel.Row

    /// When the booking starts, for the When column's order. ⚠️ An unparseable stamp sorts
    /// as the distant past rather than being dropped; its cell still says "Unknown".
    let instant: Date

    init(_ row: SchedulingBookingsModel.Row) {
        self.row = row
        instant = WireInstant.parse(row.booking.startAt) ?? .distantPast
    }

    var id: String {
        row.id
    }

    var who: String {
        row.who
    }

    var eventType: String {
        row.eventType
    }

    var host: String {
        row.host
    }

    var status: String {
        row.status.label
    }

    /// ⛔ AN EMPTY ORDER IS THE SERVER'S ORDER, UNTOUCHED: the order the pager appends in
    /// and the iPad shows. A sort reorders the bookings loaded so far.
    static func rows(
        _ rows: [SchedulingBookingsModel.Row],
        sortedBy order: [KeyPathComparator<SchedulingBookingsTableRow>]
    ) -> [SchedulingBookingsTableRow] {
        let wrapped = rows.map(SchedulingBookingsTableRow.init)
        return order.isEmpty ? wrapped : wrapped.sorted(using: order)
    }
}

/// One event type as the table sorts it.
struct SchedulingEventTypesTableRow: Identifiable {
    let row: SchedulingEventTypesModel.Row

    /// The length in minutes, so Duration sorts by length and not by its words.
    let minutes: Int

    var id: String {
        row.id
    }

    var name: String {
        row.name
    }

    var location: String {
        row.location
    }

    var state: String {
        row.state.label
    }

    /// ⚠️ THE MINUTES COME FROM THE LOADED EVENT TYPES BY ID, because the iPad's row keeps
    /// only the rendered "30 min". A row whose type is missing sorts first ascending.
    static func rows(
        _ rows: [SchedulingEventTypesModel.Row],
        eventTypes: [SchedulingEventType],
        sortedBy order: [KeyPathComparator<SchedulingEventTypesTableRow>]
    ) -> [SchedulingEventTypesTableRow] {
        let minutes = Dictionary(eventTypes.map { ($0.id, $0.durationMinutes) }) { first, _ in first }
        let wrapped = rows.map { SchedulingEventTypesTableRow(row: $0, minutes: minutes[$0.id] ?? 0) }
        return order.isEmpty ? wrapped : wrapped.sorted(using: order)
    }
}

/// The bookings table.
struct SchedulingBookingsTable: View {
    let workspaceId: String
    let role: WorkspaceRole?
    let rows: [SchedulingBookingsModel.Row]

    @State private var sortOrder: [KeyPathComparator<SchedulingBookingsTableRow>] = []
    @State private var selection: String?
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?

    var body: some View {
        Table(
            SchedulingBookingsTableRow.rows(rows, sortedBy: sortOrder),
            selection: $selection,
            sortOrder: $sortOrder
        ) {
            TableColumn("When", value: \.instant) { item in
                Text(item.row.when)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityIdentifier(A11yID.Scheduling.bookingRow(item.id))
            }
            .width(min: 140, ideal: 170)
            TableColumn("Who", value: \.who) { item in
                Text(item.who).lineLimit(1)
            }
            .width(min: 140, ideal: 200)
            TableColumn("Event type", value: \.eventType) { item in
                Text(item.eventType).lineLimit(1)
            }
            .width(min: 100, ideal: 150)
            TableColumn("Host", value: \.host) { item in
                Text(item.host).lineLimit(1)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Status", value: \.status) { item in
                DistrictBadge(text: item.row.status.label, tone: item.row.status.kind.tone)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first else { return }
            navigator?.push(.scheduling(workspaceId: workspaceId, role: role, section: .booking(id: id)))
        }
    }
}

/// The event types table.
///
/// ⚠️ A ROW OPENS THE INSPECTOR, WHICH IS A READ, as the iPad's row does. The web's name
/// cell links to an EDITOR; this one leads to ``SchedulingEventTypeView``.
struct SchedulingEventTypesTable: View {
    let workspaceId: String
    let role: WorkspaceRole?
    let rows: [SchedulingEventTypesModel.Row]
    let eventTypes: [SchedulingEventType]

    @State private var sortOrder: [KeyPathComparator<SchedulingEventTypesTableRow>] = []
    @State private var selection: String?
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?

    var body: some View {
        let items = SchedulingEventTypesTableRow.rows(rows, eventTypes: eventTypes, sortedBy: sortOrder)
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                Text(item.name)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11yID.Scheduling.eventTypeRow(item.row.slug))
            }
            .width(min: 140, ideal: 200)
            TableColumn("Duration", value: \.minutes) { item in
                Text(item.row.duration).monospacedDigit().lineLimit(1)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Starts every") { item in
                Text(item.row.interval).monospacedDigit().lineLimit(1)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Location", value: \.location) { item in
                Text(item.location).lineLimit(1)
            }
            .width(min: 100, ideal: 150)
            TableColumn("State", value: \.state) { item in
                DistrictBadge(text: item.row.state.label, tone: item.row.state.kind.tone)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: String.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let item = items.first(where: { $0.id == id }) else { return }
            navigator?.push(.scheduling(workspaceId: workspaceId, role: role, section: .eventType(slug: item.row.slug)))
        }
    }
}

/// The column a table section sits in: its header above, its table filling the rest.
///
/// ⚠️ NOT ``SchedulingSectionScroll``. A `Table` scrolls itself and collapses to nothing
/// inside a `ScrollView`, so a table section is a plain column with the same title,
/// identifier and refresh (⌘R) as the scroll every other section uses.
struct SchedulingSectionColumn<Header: View, Content: View>: View {
    let title: String
    let identifier: String
    let onRefresh: () async -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.section) {
            header
            content
        }
        .padding(DistrictSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .districtRefreshable { await onRefresh() }
        .accessibilityIdentifier(identifier)
    }
}
