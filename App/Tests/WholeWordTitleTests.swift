import AppKit
@testable import DistrictMac
import SwiftUI
import Testing

/// The detail placeholder's title never breaks inside a word (``WholeWordTitle``).
@MainActor
struct WholeWordTitleTests {
    @Test func `a line breaks only between words as written`() {
        #expect(WholeWordTitle.words("Choisissez un appel") == ["Choisissez", "un", "appel"])
        #expect(WholeWordTitle.words("Vue d'ensemble") == ["Vue", "d'ensemble"])
        #expect(WholeWordTitle.words("  Select a call ") == ["Select", "a", "call"])
    }

    /// ⛔ THE IDEAL WIDTH IS THE WIDEST WORD, NOT THE WHOLE LINE, which is what lets
    /// `ViewThatFits` refuse a font at which « Choisissez » would have to break.
    @Test func `the ideal width is the widest word`() {
        let font = WholeWordTitle.fonts[0]
        let word = NSHostingView(rootView: Text("Choisissez").font(font)).fittingSize.width
        let line = NSHostingView(rootView: Text("Choisissez un appel").font(font)).fittingSize.width
        let laidOut = NSHostingView(rootView: WholeWordLayout {
            Text("Choisissez un appel").font(font)
            Text("Choisissez").font(font).hidden()
            Text("un").font(font).hidden()
            Text("appel").font(font).hidden()
        }).fittingSize.width
        #expect(abs(laidOut - word) < 1)
        #expect(laidOut < line)
    }

    /// ⚠️ THE FONTS GO FROM LARGEST TO SMALLEST, so the first that fits is the largest that
    /// keeps every word whole.
    @Test func `each smaller font needs less room for the same word`() {
        let widths = WholeWordTitle.fonts.map {
            NSHostingView(rootView: Text("Choisissez").font($0)).fittingSize.width
        }
        for (larger, smaller) in zip(widths, widths.dropFirst()) {
            #expect(smaller <= larger)
        }
    }
}
