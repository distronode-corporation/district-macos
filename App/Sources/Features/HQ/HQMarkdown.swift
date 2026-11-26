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
/// (CodeRabbit on #145), so the lines from a fence to its closing fence are never parsed.
///
/// ⚠️ TEXT THAT IS NOT VALID MARKDOWN IS SHOWN AS SENT, so an answer is never lost to a
/// parse failure.
enum HQMarkdown {
    static func inline(_ text: String) -> AttributedString {
        var rendered = AttributedString()
        var prose = ""
        var fenced = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let piece = String(line) + (index < lines.count - 1 ? "\n" : "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // An opening fence's info string cannot hold a backtick (CommonMark 4.5), so
            // "```value```" is an inline code span, not a fence (CodeRabbit on #145);
            // a closing fence is backticks only.
            let isFence = trimmed.hasPrefix("```") && (fenced
                ? trimmed.allSatisfy { $0 == "`" }
                : !trimmed.drop { $0 == "`" }.contains("`"))
            if isFence || fenced {
                rendered += parsed(prose)
                prose = ""
                rendered += AttributedString(piece)
                if isFence {
                    fenced.toggle()
                }
            } else {
                prose += piece
            }
        }
        rendered += parsed(prose)
        return rendered
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
