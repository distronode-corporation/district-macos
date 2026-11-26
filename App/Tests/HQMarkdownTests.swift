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

    /// Three backticks with a backtick later on the line open a code span, not a fence
    /// (CodeRabbit on #145), so the span and everything after it are still rendered.
    func testAnInlineTripleBacktickSpanIsNotAFence() throws {
        let rendered = HQMarkdown.inline("```value```\n**Next**")
        XCTAssertEqual(String(rendered.characters), "value\nNext")
        let code = try XCTUnwrap(rendered.range(of: "value"))
        XCTAssertEqual(rendered[code].inlinePresentationIntent, .code)
        let bold = try XCTUnwrap(rendered.range(of: "Next"))
        XCTAssertEqual(rendered[bold].inlinePresentationIntent, .stronglyEmphasized)
    }

    /// Inside a fence, only a line of backticks closes it; a code span line does not.
    func testOnlyALineOfBackticksClosesAFence() {
        let text = "```text\n```value```\n**kept**\n```\nAfter **bold**"
        XCTAssertEqual(
            String(HQMarkdown.inline(text).characters),
            "```text\n```value```\n**kept**\n```\nAfter bold"
        )
    }

    /// A closing fence has at least as many backticks as its opener (CodeRabbit on #145), so a
    /// shorter run inside a four-backtick fence is part of the block.
    func testAShorterRunInsideALongerFenceDoesNotCloseIt() {
        let text = "````text\n```\nTotal **19**\n````\nAfter **bold**"
        XCTAssertEqual(
            String(HQMarkdown.inline(text).characters),
            "````text\n```\nTotal **19**\n````\nAfter bold"
        )
    }

    /// A tilde fence is a fence too, and only tildes close it.
    func testATildeFenceStaysAsSent() {
        let text = "~~~\n```\nTotal **19**\n~~~\nAfter **bold**"
        XCTAssertEqual(
            String(HQMarkdown.inline(text).characters),
            "~~~\n```\nTotal **19**\n~~~\nAfter bold"
        )
    }

    /// A fence in a nested list item, four spaces in, is still a fence and kept as sent.
    func testAFenceInANestedListItemStaysAsSent() {
        let text = "- outer\n  - inner\n    ~~~\n    Total **19**\n    ~~~\nAfter **bold**"
        XCTAssertEqual(
            String(HQMarkdown.inline(text).characters),
            "- outer\n  - inner\n    ~~~\n    Total **19**\n    ~~~\nAfter bold"
        )
    }

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(String(HQMarkdown.inline("No calls yet.").characters), "No calls yet.")
    }
}
