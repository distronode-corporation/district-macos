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
/// ⚠️ TEXT THAT IS NOT VALID MARKDOWN IS SHOWN AS SENT, so an answer is never lost to a
/// parse failure.
enum HQMarkdown {
    static func inline(_ text: String) -> AttributedString {
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
