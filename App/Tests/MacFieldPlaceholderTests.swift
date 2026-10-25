import DistrictL10n
@testable import DistrictMac
import XCTest

/// The Desk name field and the new message's To field say what goes in them when empty.
///
/// ⚠️ A PLACEHOLDER, NOT A SECOND LABEL: each field's label is drawn above it, so the
/// placeholder says what an empty Desk name means (the workspace's name) and what the To
/// field takes (a contact's name, or a number or email typed in).
final class MacFieldPlaceholderTests: XCTestCase {
    func testThePlaceholdersInBothLanguages() {
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(DeskCopy.brandNamePlaceholder, "Your workspace name")
            XCTAssertEqual(InboxCopy.toPlaceholder, "Name, number or email")
        }
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(DeskCopy.brandNamePlaceholder, "Nom de votre espace de travail")
            XCTAssertEqual(InboxCopy.toPlaceholder, "Nom, numéro ou courriel")
        }
    }

    /// ⛔ EACH FIELD PASSES ITS OWN PLACEHOLDER, and neither repeats its label.
    func testTheTwoFieldsPassThem() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features")
        let desk = try String(
            contentsOf: sources.appendingPathComponent("Desk/DeskSettingsView.swift"),
            encoding: .utf8
        )
        let compose = try String(
            contentsOf: sources.appendingPathComponent("Inbox/ComposeSheet.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(desk.contains("placeholder: DeskCopy.brandNamePlaceholder"))
        XCTAssertTrue(compose.contains("placeholder: InboxCopy.toPlaceholder"))
        XCTAssertNotEqual(DeskCopy.brandNamePlaceholder, DeskCopy.brandNameLabel)
        XCTAssertNotEqual(InboxCopy.toPlaceholder, InboxCopy.to)
    }
}
