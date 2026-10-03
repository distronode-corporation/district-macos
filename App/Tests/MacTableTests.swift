@testable import DistrictMac
import DistrictModel
import Foundation
import XCTest

/// The Mac's sortable call-log and contacts tables: what each column sorts by, and that the
/// server's order survives until a column is clicked.
final class MacTableTests: XCTestCase {
    // MARK: - The call log

    /// ⛔ NO SORT IS THE SERVER'S ORDER, UNTOUCHED: the pager appends in it.
    func test_MAC_TABLE_01_noSortKeepsTheServersOrder() throws {
        let calls = try [
            call(id: "c3", number: "Zed", created: "2026-08-15T14:30:00.000Z", seconds: 5, status: "completed"),
            call(id: "c1", number: "Ada", created: "2026-08-16T09:00:00.000Z", seconds: 600, status: "no-answer"),
            call(id: "c2", number: "Bea", created: "2026-08-14T08:00:00.000Z", seconds: 0, status: "busy"),
        ]
        XCTAssertEqual(CallLogRow.rows(calls, sortedBy: []).map(\.id), ["c3", "c1", "c2"])
    }

    func test_MAC_TABLE_02_eachCallColumnSortsByItsOwnKey() throws {
        let calls = try [
            call(id: "c3", number: "zed", created: "2026-08-15T14:30:00.000Z", seconds: 5, status: "completed"),
            call(id: "c1", number: "Ada", created: "2026-08-16T09:00:00.000Z", seconds: 600, status: "no-answer"),
            call(id: "c2", number: "Bea", created: "2026-08-14T08:00:00.000Z", seconds: 0, status: "busy"),
        ]
        let byCaller = CallLogRow.rows(calls, sortedBy: [KeyPathComparator(\CallLogRow.caller)])
        XCTAssertEqual(byCaller.map(\.id), ["c1", "c2", "c3"], "case-insensitive, as Finder sorts")
        let byWhen = CallLogRow.rows(calls, sortedBy: [KeyPathComparator(\CallLogRow.instant, order: .reverse)])
        XCTAssertEqual(byWhen.map(\.id), ["c1", "c3", "c2"], "by the instant, not the display string")
        let byDuration = CallLogRow.rows(calls, sortedBy: [KeyPathComparator(\CallLogRow.seconds)])
        XCTAssertEqual(byDuration.map(\.id), ["c2", "c3", "c1"], "by seconds, not by \"10m 0s\" as text")
        let byStatus = CallLogRow.rows(calls, sortedBy: [KeyPathComparator(\CallLogRow.status)])
        XCTAssertEqual(byStatus.map(\.id), ["c2", "c3", "c1"])
    }

    /// ⛔ THE CELLS SAY WHAT THE iPad's ROW SAYS: every value comes from ``CallDisplay``.
    func test_MAC_TABLE_03_aCallRowReadsAsTheIPadsRow() throws {
        let transferred = try call(
            id: "c9", number: "Unknown", created: "not a date", seconds: nil, status: "completed",
            transferStatus: "failed"
        )
        let row = CallLogRow(transferred)
        XCTAssertEqual(row.caller, CallDisplay(transferred).callerLabel)
        XCTAssertEqual(row.caller, "No caller ID", "a withheld caller is not a name")
        XCTAssertEqual(row.direction, "Inbound")
        XCTAssertEqual(row.status, "Transfer failed completed", "the transfer label sorts with the status")
        XCTAssertEqual(row.seconds, 0)
        XCTAssertEqual(row.instant, .distantPast, "an unparseable stamp sorts last, it is not dropped")
        XCTAssertNil(row.display.durationLabel)
    }

    // MARK: - Contacts

    func test_MAC_TABLE_04_noContactSortKeepsTheServersOrderAndColumnsSort() throws {
        let contacts = try [
            contact(id: "k2", name: "bea", phone: nil, email: "bea@example.com", created: "2026-08-15T10:00:00.000Z"),
            contact(id: "k1", name: "Unknown", phone: "+15550100", email: nil, created: "2026-08-16T10:00:00.000Z"),
            contact(
                id: "k3",
                name: "Ada",
                phone: "+15550199",
                email: "ada@example.com",
                created: "2026-08-14T10:00:00.000Z"
            ),
        ]
        XCTAssertEqual(ContactsTableRow.rows(contacts, sortedBy: []).map(\.id), ["k2", "k1", "k3"])
        let byName = ContactsTableRow.rows(contacts, sortedBy: [KeyPathComparator(\ContactsTableRow.name)])
        XCTAssertEqual(byName.map(\.id), ["k3", "k2", "k1"], "\"Unnamed contact\" sorts as its words")
        let byAdded = ContactsTableRow.rows(contacts, sortedBy: [KeyPathComparator(\ContactsTableRow.instant)])
        XCTAssertEqual(byAdded.map(\.id), ["k3", "k2", "k1"])
        let byPhone = ContactsTableRow.rows(contacts, sortedBy: [KeyPathComparator(\ContactsTableRow.phone)])
        XCTAssertEqual(byPhone.map(\.id), ["k2", "k1", "k3"], "no phone sorts first ascending")
    }

    /// ⛔ THE iPad's WORDS: the server's "Unknown" is no name, and a contact with neither
    /// identifier gets the placeholder.
    func test_MAC_TABLE_05_aContactRowUsesTheIPadsWords() throws {
        let unknown = try ContactsTableRow(contact(id: "k1", name: "Unknown", phone: " ", email: nil, created: "x"))
        XCTAssertEqual(unknown.name, "Unnamed contact")
        XCTAssertEqual(unknown.phone, "")
        XCTAssertTrue(unknown.hasNoIdentifier)
        XCTAssertEqual(ContactsTableRow.noIdentifiers, "No phone or email")
        let named = try ContactsTableRow(contact(
            id: "k2",
            name: "Ada",
            phone: nil,
            email: "ada@example.com",
            created: "x"
        ))
        XCTAssertEqual(named.name, "Ada")
        XCTAssertFalse(named.hasNoIdentifier)
    }

    // MARK: - Fixtures

    private func call(
        id: String,
        number: String,
        created: String,
        seconds: Int?,
        status: String,
        transferStatus: String? = nil
    ) throws -> CallSummary {
        var json: [String: Any] = [
            "id": id, "type": "inbound", "number": number, "status": status, "duration": "", "time": "",
            "aiSummary": "", "transcript": "", "callerName": number, "direction": "inbound",
            "summary": "", "createdAt": created,
        ]
        json["durationRaw"] = seconds
        json["transferStatus"] = transferStatus
        return try JSONDecoder().decode(CallSummary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func contact(id: String, name: String, phone: String?, email: String?, created: String) throws -> Contact {
        var json: [String: Any] = ["id": id, "workspaceId": "ws_1", "name": name, "createdAt": created]
        json["phoneNumber"] = phone
        json["email"] = email
        return try JSONDecoder().decode(Contact.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// A file chosen in the open panel is labelled by the picker's own rule.
final class AttachmentFileTests: XCTestCase {
    private let allowed: Set = ["image/jpeg", "image/png", "image/gif"]

    func test_MAC_ATTACH_01_aFileIsTypedByItsExtension() {
        XCTAssertEqual(AttachmentFile.mimeType(of: URL(fileURLWithPath: "/tmp/a.png"), allowed: allowed), "image/png")
        XCTAssertEqual(AttachmentFile.mimeType(of: URL(fileURLWithPath: "/tmp/b.JPG"), allowed: allowed), "image/jpeg")
    }

    /// ⚠️ A TYPE THE ROUTE DOES NOT TAKE IS STILL NAMED, so the model refuses it with its
    /// own sentence; a file with no extension is the unknown type.
    func test_MAC_ATTACH_02_anUnacceptedOrUnknownTypeIsPassedThroughForTheModelToRefuse() {
        XCTAssertEqual(AttachmentFile.mimeType(of: URL(fileURLWithPath: "/tmp/c.heic"), allowed: allowed), "image/heic")
        XCTAssertEqual(
            AttachmentFile.mimeType(of: URL(fileURLWithPath: "/tmp/noextension"), allowed: allowed),
            "application/octet-stream"
        )
    }
}
