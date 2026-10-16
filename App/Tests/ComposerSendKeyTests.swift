import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The reply box's send key (``ComposerBar/sendShortcut``): a send is billed, so a stray
/// Return is a new line and only ⌘↩ sends (decided 2026-10-15 for 3.0.1).
@MainActor
final class ComposerSendKeyTests: XCTestCase {
    /// ⛔ ⌘↩, AND NEVER THE DEFAULT ACTION, which is a bare Return.
    func test_COMPOSER_SEND_1_commandReturnSendsAndReturnDoesNot() {
        XCTAssertEqual(ComposerBar.sendShortcut, KeyboardShortcut(.return, modifiers: .command))
        XCTAssertNotEqual(ComposerBar.sendShortcut, .defaultAction)
        XCTAssertEqual(ComposerBar.sendShortcut.modifiers, .command)
        XCTAssertEqual(ComposerBar.sendShortcut.key, .return)
    }

    /// ⚠️ THE HELP TAG NAMES THE KEY, in either language.
    func test_COMPOSER_SEND_2_theHelpTagNamesTheKey() {
        XCTAssertEqual(ComposerBar.sendHelp(InboxCopy.send), "Send (\u{2318}\u{21A9})")
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(ComposerBar.sendHelp(InboxCopy.send), "Envoyer (\u{2318}\u{21A9})")
        }
    }

    /// ⚠️ THE BOX IS SIZED BY ITS WORDS PLUS A SPACE, so an empty reply is one line and a
    /// new line just typed already has its height.
    func test_COMPOSER_SEND_3_theBoxIsSizedByItsWords() {
        XCTAssertEqual(ComposerBar.sizingText(""), " ")
        XCTAssertEqual(ComposerBar.sizingText("Thanks\n"), "Thanks\n ")
        XCTAssertEqual(ComposerBar.fieldMaxLines, 5)
    }
}
