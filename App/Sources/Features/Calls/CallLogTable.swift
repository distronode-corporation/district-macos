import DistrictL10n
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
        let widths = CallLogColumns.current
        Table(rows, selection: selectedId, sortOrder: $sortOrder) {
            // ⚠️ THE DIRECTION IS THE CALLER'S GLYPH, NOT A COLUMN OF ITS OWN, as in the Mac's
            // Phone app. A fifth column cost 83pt of a list column that has to leave the open
            // call readable at the 1000pt window minimum (``ListColumnWidth``), and the word is
            // still spoken and shown on hover.
            TableColumn(CallsCopy.columnCaller, value: \.caller) { row in
                HStack(spacing: CallLogColumns.glyphSpacing) {
                    Image(systemName: row.display.outbound ? "phone.arrow.up.right" : "phone.arrow.down.left")
                        .foregroundStyle(.secondary)
                        .frame(width: CallLogColumns.glyphWidth)
                        .help(row.direction)
                        .accessibilityLabel(row.direction)
                    Text(row.caller)
                        .lineLimit(1)
                        .accessibilityIdentifier(A11yID.Calls.row(row.id))
                        .onAppear { reached(row, in: rows) }
                }
            }
            .width(min: widths.caller, ideal: widths.caller)
            // ⚠️ THE WHOLE STAMP WHEN THE COLUMN HAS THE ROOM, THE DAY WHEN IT DOES NOT, as the
            // Finder's date columns do. At the window minimum the column is the day's width
            // (``CallLogColumns``); the open call and the hover keep the minute.
            TableColumn(CallsCopy.columnWhen, value: \.instant) { row in
                ViewThatFits(in: .horizontal) {
                    Text(row.display.time)
                    Text(WireDate.displayDay(row.call.createdAt))
                }
                .monospacedDigit()
                .lineLimit(1)
                .help(row.display.time)
            }
            .width(min: widths.when, ideal: widths.when)
            TableColumn(CallsCopy.columnDuration, value: \.seconds) { row in
                Text(row.display.durationLabel ?? "")
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: widths.duration, ideal: widths.duration)
            // ⚠️ MAC: A TRANSFER OUTCOME STACKS OVER THE STATUS rather than beside it, so the
            // column is one badge wide and a two-badge row grows a line instead of scrolling.
            // ⛔ AND IT IS AS WIDE AS THE LONGEST BADGE IN THE LANGUAGE SHOWING: a fixed 92pt
            // clipped « Sans réponse » and pushed the table into a sideways scroll.
            TableColumn(CallsCopy.columnStatus, value: \.status) { row in
                VStack(alignment: .leading, spacing: 2) {
                    if let transfer = row.display.transferLabel {
                        DistrictBadge(text: transfer, tone: row.display.transferTone)
                    }
                    DistrictBadge(text: row.display.statusLabel, tone: row.display.statusTone)
                }
            }
            .width(min: widths.status, ideal: widths.status)
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

/// The Calls table's column widths in the language showing, measured (``ColumnFit``).
///
/// ⛔ EACH IS THE WIDEST THING ITS COLUMN CAN SHOW, OR ITS HEADER, WHICHEVER IS WIDER, and
/// the list column's minimum is their sum (``ListColumnWidth``), so the table never scrolls
/// sideways and never clips a badge. `ColumnFitTests` pins it in both languages.
struct CallLogColumns: Equatable {
    let caller: CGFloat
    let when: CGFloat
    let duration: CGFloat
    let status: CGFloat

    /// The caller's name gets what is left of a narrow list; it truncates, as a name may.
    static let callerText: CGFloat = 96
    static let glyphWidth: CGFloat = 18
    static let glyphSpacing: CGFloat = 6

    static var current: CallLogColumns {
        CallLogColumns(
            caller: max(callerText + glyphWidth + glyphSpacing, ColumnFit.header(CallsCopy.columnCaller)),
            when: max(ColumnFit.text(dayStamps, monospacedDigits: true), ColumnFit.header(CallsCopy.columnWhen)),
            duration: max(
                ColumnFit.text(durations, monospacedDigits: true),
                ColumnFit.header(CallsCopy.columnDuration)
            ),
            status: max(ColumnFit.badge(statusLabels), ColumnFit.header(CallsCopy.columnStatus))
        )
    }

    var all: [CGFloat] {
        [caller, when, duration, status]
    }

    /// The table's own minimum: the columns, their spacing and the row inset.
    var table: CGFloat {
        ColumnFit.table(all)
    }

    /// Every word the Status column can draw: each call status the vocabulary lists, the
    /// generic word for one it does not (French reads an unlisted status as it), "Live", and
    /// the two transfer outcomes stacked over them. ⚠️ An English screen keeps an unlisted
    /// status as sent, which no width can promise to hold.
    static var statusLabels: [String] {
        let listed = [
            "completed",
            "in-progress",
            "ringing",
            "no-answer",
            "failed",
            "busy",
            "canceled",
            "abandoned",
            "unknown",
        ]
        return listed.map { AppWire.label(.callStatus, $0) } + [
            WireLabel.label(.callStatus, "\u{1}"),
            CallsCopy.live,
            CallsCopy.transferred,
            CallsCopy.transferFailed,
        ]
    }

    /// The day of a call in each month, two-digit, as the narrow When column draws it.
    static var dayStamps: [String] {
        (1 ... 12).map { WireDate.displayDay(String(format: "2026-%02d-28T12:00:00.000Z", $0)) }
    }

    /// The longest length a call log shows under an hour, in each language's own form.
    static var durations: [String] {
        [AppWire.duration(sent: "59m 59s", seconds: 3599)]
    }
}
