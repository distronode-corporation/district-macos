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

    static let unnamed = "Unnamed contact"
    static let noIdentifiers = "No phone or email"

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
        Table(rows, selection: selectedId, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                nameCell(row)
                    .onAppear { reached(row, in: rows) }
            }
            .width(min: 140, ideal: 180)
            TableColumn("Phone", value: \.phone) { row in
                if row.hasNoIdentifier {
                    Text(ContactsTableRow.noIdentifiers)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(row.phone)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .width(min: 100, ideal: 120)
            TableColumn("Email", value: \.email) { row in
                Text(row.email)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 170)
            TableColumn("Added", value: \.instant) { row in
                Text(WireDate.display(row.contact.createdAt))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        }
    }

    /// The name, and the iPad row's two badges beside it.
    private func nameCell(_ row: ContactsTableRow) -> some View {
        HStack(spacing: DistrictSpacing.hairline) {
            Text(row.name)
                .lineLimit(1)
                .accessibilityIdentifier(A11yID.Contacts.row(row.id))
            if blocked.isBlocked(row.id, in: workspaceId) {
                BlockedBadge(identifier: A11yID.Contacts.blockedRow(row.id))
            }
            if DgiStatus.isInProgress(row.contact.dgiStatus) {
                DistrictBadge(text: "Building dossier…", tone: .district)
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
