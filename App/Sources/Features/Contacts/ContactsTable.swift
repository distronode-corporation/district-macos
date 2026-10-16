import DistrictModel
import SwiftUI

/// One contact as the Mac's table sorts it.
///
/// ⚠️ MAC ONLY. The iPad draws a list row (a name over its phone or email); a Mac window
/// has the width to give each its own column, and every column sorts. The words are the
/// iPad's: "Unnamed contact" for a contact with no usable name, and the same badges.
struct ContactsTableRow: Identifiable {
    let contact: Contact

    /// When the contact was created, for the Added column's order. ⚠️ An unparseable
    /// stamp sorts as the distant past rather than being dropped.
    let instant: Date

    init(_ contact: Contact) {
        self.contact = contact
        instant = WireInstant.parse(contact.createdAt) ?? .distantPast
    }

    var id: String {
        contact.id
    }

    /// ⛔ ``Contact/displayName``, WHICH TREATS THE SERVER'S "Unknown" AS NO NAME, and the
    /// iPad's fallback word for it.
    var name: String {
        contact.displayName ?? Self.unnamed
    }

    /// Sorted as text; a contact with none sorts first ascending, with the other blanks.
    var phone: String {
        Self.usable(contact.phoneNumber)
    }

    var email: String {
        Self.usable(contact.email)
    }

    /// The table's rows in `order`.
    ///
    /// ⛔ AN EMPTY ORDER IS THE SERVER'S ORDER, UNTOUCHED: the order the pager appends in
    /// and the iPad shows. A sort reorders the contacts loaded so far; reaching the end of
    /// the table still loads the next page, which then sorts in.
    static func rows(
        _ contacts: [Contact],
        sortedBy order: [KeyPathComparator<ContactsTableRow>]
    ) -> [ContactsTableRow] {
        let rows = contacts.map(ContactsTableRow.init)
        return order.isEmpty ? rows : rows.sorted(using: order)
    }

    /// ⚠️ THE iPad's PLACEHOLDER FOR A CONTACT WITH NEITHER (contacts are email-first, so a
    /// phone-less one is common and legal), drawn in the Phone column.
    var hasNoIdentifier: Bool {
        phone.isEmpty && email.isEmpty
    }

    static var unnamed: String {
        ContactsCopy.unnamedContact
    }

    static var noIdentifiers: String {
        ContactsCopy.noPhoneEmail
    }

    private static func usable(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// The contacts as a sortable table.
///
/// ⛔ SELECTION IS THE SHELL'S ROUTE: choosing a row writes `Route.contactDetail` through
/// `selection`, as the iPad's `NavigationLink(value:)` does.
struct ContactsTable: View {
    let workspaceId: String
    let role: WorkspaceRole?
    let contacts: [Contact]
    let selection: Binding<Route?>?
    /// The shared blocked set (``AppContainer/blockedContacts``), for the badge.
    let blocked: BlockedContactsStore
    let onReachEnd: () -> Void

    @State private var sortOrder: [KeyPathComparator<ContactsTableRow>] = []

    var body: some View {
        let rows = ContactsTableRow.rows(contacts, sortedBy: sortOrder)
        let widths = ContactsColumns.current
        Table(rows, selection: selectedId, sortOrder: $sortOrder) {
            TableColumn(ContactsCopy.name, value: \.name) { row in
                nameCell(row)
                    .onAppear { reached(row, in: rows) }
            }
            .width(min: widths.name, ideal: widths.name)
            TableColumn(ContactsCopy.phone, value: \.phone) { row in
                if row.hasNoIdentifier {
                    Text(ContactsTableRow.noIdentifiers)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(ContactsTableRow.noIdentifiers)
                } else {
                    Text(row.phone)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .width(min: widths.phone, ideal: widths.phone)
            // ⚠️ CUT IN THE MIDDLE, as the composer cuts an address: the domain is the half
            // that says who it is. The whole address is on hover and in the open contact.
            TableColumn(ContactsCopy.email, value: \.email) { row in
                Text(row.email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.email)
            }
            .width(min: widths.email, ideal: widths.email)
            // ⚠️ THE DAY, NOT THE MINUTE: the whole stamp needs 170pt, which this column cannot
            // have beside the other three in a list column at the 1000pt window minimum
            // (Sean's first build, 20019, cut it to "Aug 15, 2026 at"). The contact's own
            // screen keeps the full stamp.
            TableColumn(ContactsCopy.added, value: \.instant) { row in
                Text(WireDate.displayDay(row.contact.createdAt))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: widths.added, ideal: widths.added)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        }
    }

    /// The name, and under it the iPad row's Blocked badge and a spinner while the dossier is
    /// built.
    ///
    /// ⚠️ MAC: UNDER THE NAME, NOT BESIDE IT. Beside it, "Building dossier…" took the column
    /// and left "+1647..." of the name (Sean's first build, 20019); a row with a badge grows
    /// a line instead.
    ///
    /// ⚠️ AND THE DOSSIER IS A SPINNER WITH ITS WORDS ON HOVER, NOT THE iPad's BADGE. The badge
    /// was wider than the column at the window minimum and lost its end (« Création de la
    /// fiche… », 3.0.1 visual QA); a small spinner is how a Mac list says "still working",
    /// and the words stay spoken.
    private func nameCell(_ row: ContactsTableRow) -> some View {
        let isBlocked = blocked.isBlocked(row.id, in: workspaceId)
        let building = DgiStatus.isInProgress(row.contact.dgiStatus)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DistrictSpacing.hairline) {
                Text(row.name)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11yID.Contacts.row(row.id))
                if building {
                    ProgressView()
                        .controlSize(.mini)
                        .help(ContactsCopy.buildingDossier)
                        .accessibilityLabel(ContactsCopy.buildingDossier)
                }
            }
            if isBlocked {
                BlockedBadge(identifier: A11yID.Contacts.blockedRow(row.id))
            }
        }
    }

    /// ⚠️ THE iPad ROW'S COPY ACTIONS (``RowContextActions/contact(phone:email:)``), for
    /// one row at a time.
    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first, let contact = contacts.first(where: { $0.id == id }) {
            ForEach(RowContextActions.contact(phone: contact.phoneNumber, email: contact.email)) { action in
                Button(action.title, systemImage: "doc.on.doc") {
                    Clipboard.copy(action.value)
                }
            }
        }
    }

    private var selectedId: Binding<String?> {
        Binding(
            get: {
                guard case let .contactDetail(_, _, contactId) = selection?.wrappedValue else { return nil }
                return contactId
            },
            set: { id in
                selection?.wrappedValue = id.map {
                    Route.contactDetail(workspaceId: workspaceId, role: role, contactId: $0)
                }
            }
        )
    }

    private func reached(_ row: ContactsTableRow, in rows: [ContactsTableRow]) {
        guard row.id == rows.last?.id else { return }
        onReachEnd()
    }
}

/// The Contacts table's column widths in the language showing (``ColumnFit``), as
/// ``CallLogColumns`` does for the call log.
///
/// ⚠️ THE NAME AND THE EMAIL TRUNCATE, as names and addresses may, so theirs are floors
/// rather than the longest value; the phone and the day are measured.
struct ContactsColumns: Equatable {
    let name: CGFloat
    let phone: CGFloat
    let email: CGFloat
    let added: CGFloat

    static let nameText: CGFloat = 120
    static let emailText: CGFloat = 100

    static var current: ContactsColumns {
        ContactsColumns(
            name: max(nameText, ColumnFit.badge([ContactBlockCopy.badge]), ColumnFit.header(ContactsCopy.name)),
            phone: max(ColumnFit.text(["+14165550199"], monospacedDigits: true), ColumnFit.header(ContactsCopy.phone)),
            email: max(emailText, ColumnFit.header(ContactsCopy.email)),
            added: max(
                ColumnFit.text(CallLogColumns.dayStamps, monospacedDigits: true),
                ColumnFit.header(ContactsCopy.added)
            )
        )
    }

    var all: [CGFloat] {
        [name, phone, email, added]
    }

    var table: CGFloat {
        ColumnFit.table(all)
    }
}
