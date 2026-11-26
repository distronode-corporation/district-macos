import Foundation

/// The console's Markdown, with only its inline spans rendered.
///
/// ⛔ INLINE ONLY, AND EVERY CHARACTER OF EVERY LINE KEPT. `inlineOnlyPreservingWhitespace`
/// styles `**bold**`, `*italics*` and `` `code` `` and leaves block syntax alone, so a list
/// marker, a heading's `#` or a table's pipes stay on screen as sent and no row can be lost
/// to a half-implemented block renderer.
///
/// ⛔ NO LINKS. A link in an answer becomes plain styled text, never something to click: the
/// console's text is generated, and a click must not take the operator somewhere it chose.
///
/// ⛔ A FENCED BLOCK IS KEPT AS SENT, fences and all. Inline parsing alone read a ```` ``` ````
/// fence as a code-span delimiter and swallowed both fences and the line breaks around them
/// (CodeRabbit on #145), so the lines from a fence to its closing fence are never parsed. A
/// fence is three or more backticks or tildes, closed by at least as many of the same.
///
/// ⚠️ ANY INDENTATION, ON PURPOSE. CommonMark allows at most three spaces before a top-level
/// fence, but list items are not tracked here, and a fence in a nested list item sits four
/// spaces in or more. Read inline, such a fence would swallow its line breaks again. The cost
/// is that a fence-like line indented four spaces inside a block closes it.
///
/// ⚠️ TEXT THAT IS NOT VALID MARKDOWN IS SHOWN AS SENT, so an answer is never lost to a
/// parse failure.
enum HQMarkdown {
    static func inline(_ text: String) -> AttributedString {
        var rendered = AttributedString()
        var prose = ""
        var fence: Fence?
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let piece = String(line) + (index < lines.count - 1 ? "\n" : "")
            let candidate = Fence(line)
            let isFence: Bool = if let open = fence {
                candidate?.closes(open) ?? false
            } else {
                candidate?.canOpen ?? false
            }
            if isFence || fence != nil {
                rendered += parsed(prose)
                prose = ""
                rendered += AttributedString(piece)
                if isFence {
                    fence = fence == nil ? candidate : nil
                }
            } else {
                prose += piece
            }
        }
        rendered += parsed(prose)
        return rendered
    }

    /// A line that starts with three or more backticks or tildes: a code fence by CommonMark's
    /// rules (4.5), if it opens or closes one.
    private struct Fence {
        let marker: Character
        let length: Int
        /// What follows the run: an opening fence's info string, nothing on a closing fence.
        let rest: Substring

        init?(_ line: Substring) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
            let length = trimmed.prefix { $0 == marker }.count
            guard length >= 3 else { return nil }
            self.marker = marker
            self.length = length
            rest = trimmed.dropFirst(length)
        }

        /// A backtick fence's info string cannot hold a backtick, so "```value```" is an inline
        /// code span, not a fence (CodeRabbit on #145).
        var canOpen: Bool {
            !(marker == "`" && rest.contains("`"))
        }

        /// The opening fence's character only, at least as many of it (CodeRabbit on #145).
        func closes(_ open: Fence) -> Bool {
            marker == open.marker && length >= open.length && rest.isEmpty
        }
    }

    private static func parsed(_ text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var rendered = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in rendered.runs where run.link != nil {
            rendered[run.range].link = nil
        }
        return rendered
    }
}
