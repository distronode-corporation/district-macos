@testable import DistrictMac
import Foundation
import XCTest

/// Issue #129: HQ showed the console's Markdown as literal asterisks ("You had **19 calls**").
final class HQMarkdownTests: XCTestCase {
    func testBoldIsRenderedAndItsAsterisksAreGone() throws {
        let rendered = HQMarkdown.inline("You had **19 calls** this week")
        XCTAssertEqual(String(rendered.characters), "You had 19 calls this week")
        let bold = try XCTUnwrap(rendered.range(of: "19 calls"))
        XCTAssertEqual(rendered[bold].inlinePresentationIntent, .stronglyEmphasized)
    }

    /// Block syntax is kept as sent, so no list item or table row can be lost.
    func testListsTablesAndLineBreaksStayAsSent() {
        let text = "- one\n- two\n\n| Day | Calls |\n|---|---|\n| Mon | 4 |"
        XCTAssertEqual(String(HQMarkdown.inline(text).characters), text)
    }

    func testALinkIsTextAndNothingToClick() {
        let rendered = HQMarkdown.inline("See [the report](https://example.com/r)")
        XCTAssertEqual(String(rendered.characters), "See the report")
        XCTAssertTrue(rendered.runs.allSatisfy { $0.link == nil })
    }

    /// A fenced block keeps its fences, its line breaks and its literal asterisks.
    func testAFencedBlockStaysAsSent() {
        let text = "Before **bold**\n```text\nTotal **19**\n```\nAfter"
        XCTAssertEqual(String(HQMarkdown.inline(text).characters), "Before bold\n```text\nTotal **19**\n```\nAfter")
    }

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(String(HQMarkdown.inline("No calls yet.").characters), "No calls yet.")
    }
}
