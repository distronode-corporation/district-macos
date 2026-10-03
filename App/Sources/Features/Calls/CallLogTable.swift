import DistrictModel
import SwiftUI

/// One call-log row as the Mac's table sorts it.
///
/// ⚠️ MAC ONLY. The iPad draws ``CallRow``; a Mac window has the width for columns, so the
/// call log is a `Table` whose every column sorts. Every value a cell shows still comes from
/// ``CallDisplay``, so the table and the iPad's row cannot disagree about a call; the extra
/// fields here are only the KEYS each column sorts by.
struct CallLogRow: Identifiable {
    let call: CallSummary
    let display: CallDisplay

    /// The instant the call was created, for the When column's order. ⚠️ An unparseable
    /// stamp sorts as the distant past rather than being dropped, so the row stays visible
    /// (its cell shows the raw string, as ``WireDate`` does).
    let instant: Date

    /// Seconds, for the Duration column's order. A call with no duration sorts as zero,
    /// beside the unanswered ones it reads like.
    let seconds: Int

    init(_ call: CallSummary) {
        self.call = call
        display = CallDisplay(call)
        instant = WireInstant.parse(call.createdAt) ?? .distantPast
        seconds = max(0, call.durationRaw ?? 0)
    }

    var id: String {
        call.id
    }

    var caller: String {
        display.callerLabel
    }

    var direction: String {
        display.directionLabel
    }

    /// The Status column's key: the words the cell shows, the transfer label before the
    /// status, so the transferred and failed-transfer calls group together.
    var status: String {
        [display.transferLabel, display.statusLabel].compactMap(\.self).joined(separator: " ")
    }

    /// The table's rows in `order`.
    ///
    /// ⛔ AN EMPTY ORDER IS THE SERVER'S ORDER (newest first), UNTOUCHED. That is the order
    /// the pager appends in, and the one the iPad shows; a column the person clicked is the
    /// only thing that may reorder it. ⚠️ A sort reorders the calls loaded so far; reaching
    /// the end of the table still loads the next page, which then sorts in.
    static func rows(_ calls: [CallSummary], sortedBy order: [KeyPathComparator<CallLogRow>]) -> [CallLogRow] {
        let rows = calls.map(CallLogRow.init)
        return order.isEmpty ? rows : rows.sorted(using: order)
    }
}

/// The call log as a sortable table.
///
/// ⛔ SELECTION IS THE SHELL'S ROUTE, NOT A ROW ID OF ITS OWN: choosing a row writes
/// `Route.callDetail` through `selection`, exactly as the iPad's `NavigationLink(value:)`
/// does, so the detail column, the Go menu and a workspace switch all see one state.
struct CallLogTable: View {
    let workspaceId: String
    let calls: [CallSummary]
    let selection: Binding<Route?>?
    let onReachEnd: () -> Void

    @State private var sortOrder: [KeyPathComparator<CallLogRow>] = []

    var body: some View {
        let rows = CallLogRow.rows(calls, sortedBy: sortOrder)
        Table(rows, selection: selectedId, sortOrder: $sortOrder) {
            TableColumn("Caller", value: \.caller) { row in
                Text(row.caller)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11yID.Calls.row(row.id))
                    .onAppear { reached(row, in: rows) }
            }
            .width(min: 120, ideal: 120)
            TableColumn("Direction", value: \.direction) { row in
                Text(row.direction)
            }
            .width(min: 66, ideal: 66)
            TableColumn("When", value: \.instant) { row in
                Text(row.display.time)
                    .monospacedDigit()
            }
            // ⚠️ WIDE ENOUGH FOR THE WHOLE STAMP ("Sep 30, 2026 at 12:59 PM"), which a narrower
            // column truncated to the hour at the default window width. The other columns
            // give up the room, so the five fit the list column's minimum width
            // (``ShellView``), with no horizontal scroll.
            .width(min: 172, ideal: 172)
            TableColumn("Duration", value: \.seconds) { row in
                Text(row.display.durationLabel ?? "")
                    .monospacedDigit()
            }
            .width(min: 56, ideal: 56)
            // ⚠️ MAC: A TRANSFER OUTCOME STACKS OVER THE STATUS rather than beside it, so the
            // column is one badge wide and a two-badge row grows a line instead of scrolling.
            TableColumn("Status", value: \.status) { row in
                VStack(alignment: .leading, spacing: 2) {
                    if let transfer = row.display.transferLabel {
                        DistrictBadge(text: transfer, tone: row.display.transferTone)
                    }
                    DistrictBadge(text: row.display.statusLabel, tone: row.display.statusTone)
                }
            }
            .width(min: 92, ideal: 92)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        }
        .accessibilityIdentifier(A11yID.Calls.root)
    }

    /// ⚠️ THE ROW'S COPY ACTIONS, THE iPad'S (``RowContextActions/call(direction:from:)``),
    /// for a single row; a multi-row selection is not offered one, because the table selects
    /// one call at a time.
    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first, let call = calls.first(where: { $0.id == id }) {
            ForEach(RowContextActions.call(direction: call.direction, from: call.from)) { action in
                Button(action.title, systemImage: "doc.on.doc") {
                    Clipboard.copy(action.value)
                }
            }
        }
    }

    private var selectedId: Binding<String?> {
        Binding(
            get: {
                guard case let .callDetail(_, callId) = selection?.wrappedValue else { return nil }
                return callId
            },
            set: { id in
                selection?.wrappedValue = id.map { Route.callDetail(workspaceId: workspaceId, callId: $0) }
            }
        )
    }

    /// ⚠️ THE LAST ROW ON SCREEN IS THE PAGINATION TRIGGER, as on the iPad; the model
    /// guards it, so firing repeatedly while a window is in flight costs nothing.
    private func reached(_ row: CallLogRow, in rows: [CallLogRow]) {
        guard row.id == rows.last?.id else { return }
        onReachEnd()
    }
}
