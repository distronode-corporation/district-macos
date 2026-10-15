import SwiftUI

/// A centred title that never breaks inside a word: the largest of ``fonts`` at which its
/// longest word fits the width it is given, wrapping only between words.
///
/// ⛔ A `Text` WHOSE WORD IS WIDER THAN ITS LINE BREAKS THE WORD, AND `minimumScaleFactor`
/// DOES NOT STOP IT: the text still fits once hyphenated, so it never shrinks. Beside the
/// call log at the smallest window the detail column is about 160pt, and the system's empty
/// state drew « Choisis-sez un appel ». Here each font is a candidate whose ideal width is
/// its longest word (``WholeWordLayout``), and `ViewThatFits` takes the first that fits.
/// ⚠️ The last candidate is the floor: below it a word can still break, which no real
/// column reaches.
struct WholeWordTitle: View {
    let text: String

    /// Largest first. The first is the size the system's empty state draws its title at.
    static let fonts: [Font] = [
        .title.weight(.bold),
        .title2.weight(.bold),
        .title3.weight(.bold),
        .headline,
        .subheadline.weight(.semibold),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            candidate(Self.fonts[0])
            candidate(Self.fonts[1])
            candidate(Self.fonts[2])
            candidate(Self.fonts[3])
            candidate(Self.fonts[4])
        }
    }

    /// The words a line may break between: split on spaces only, as the text is written.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func candidate(_ font: Font) -> some View {
        WholeWordLayout {
            Text(text)
                .font(font)
                .multilineTextAlignment(.center)
            ForEach(Array(Self.words(text).enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(font)
                    .hidden()
            }
        }
    }
}

/// The first subview is the title; the rest are its words, measured and never drawn. The
/// ideal width is the widest word, so `ViewThatFits` rejects a font at which any word would
/// have to break.
struct WholeWordLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        guard let title = subviews.first else { return .zero }
        let widest = subviews.dropFirst().map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = offered ?? widest
        let height = title.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        guard let title = subviews.first else { return }
        title.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        for word in subviews.dropFirst() {
            word.place(at: bounds.origin, proposal: .zero)
        }
    }
}
