import AppKit
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import XCTest

/// An Inbox thread with its reply box: on each channel the thread can answer on, with the
/// recorded draft restored into it (its text, its subject and its image, held where the
/// channel cannot carry one), a closed WhatsApp window, and a draft that could not be read.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class ThreadComposerScreenTests: ScreenSnapshotCase {
    /// The thread in `district-conversations.json` and the stored draft in `district-draft.json`.
    private static let threadKey = "contact:contact_contract_1"
    private static let sms = ReplyTarget(to: "14165551234", channel: MessageChannel.sms)
    private static let email = ReplyTarget(to: "ada@contract.test", channel: MessageChannel.email)
    private static let whatsApp = ReplyTarget(to: "+14165551234", channel: MessageChannel.whatsapp)

    /// The recorded draft for this thread.
    ///
    /// ⚠️ ONE THREAD'S DRAFT IS READ FROM `messages/drafts` WITH ITS THREAD KEY, the path the
    /// shared rules answer with the whole list (`district-drafts-list.json`), and the rules match
    /// paths only, so this answer goes first.
    private static let draft: [FixtureTransport.Rule] = [
        .get("/api/district/messages/drafts", .fixture("mobile/district-draft.json")),
    ]

    /// ⚠️ THE RECORDING'S WINDOW IS OPEN; the closed one is the same answer with `open` false.
    private static let closedWindow: [FixtureTransport.Rule] = [
        .get("/api/district/workspace/whatsapp/window", .edited("mobile/district-whatsapp-window.json") { body in
            body["window"] = ["open": false, "expiresAt": NSNull()]
        }),
    ]

    func testSmsAndEmail() async throws {
        // Two channels: the channel strip over an empty box.
        for locale in [L10nLocale.en, .frCA] {
            try await thread(Self.named("two-channels", locale), [Self.sms, Self.email], locale: locale)
        }
    }

    func testDraftRestored() async throws {
        // On SMS: the draft's text and its image, staged.
        for locale in [L10nLocale.en, .frCA] {
            try await thread(Self.named("sms", locale), [Self.sms, Self.email], rules: Self.draft, locale: locale)
        }
        // On email: the subject field, and the image held, since email carries none.
        try await thread("email-en", [Self.email, Self.sms], rules: Self.draft)
    }

    func testDraftUnreadable() async throws {
        let failed: [FixtureTransport.Rule] = [.get("/api/district/messages/drafts", .status(500))]
        try await thread("failed-en", [Self.sms, Self.email], rules: failed)
    }

    func testWhatsApp() async throws {
        // The recorded window, open: free text.
        try await thread("open-en", [Self.whatsApp])
        // Closed: only a template, and the draft's image held under it.
        for locale in [L10nLocale.en, .frCA] {
            try await thread(
                Self.named("closed", locale),
                [Self.whatsApp, Self.sms],
                rules: Self.closedWindow + Self.draft,
                locale: locale
            )
        }
    }

    /// A conversation opens at its newest message (#159): the thread's history, taller than
    /// the window, is scrolled to its end. With a lazy stack the bottom anchor saw estimated row
    /// heights, and on most runs the thread opened at the top of its history instead.
    func testAThreadOpensAtItsNewestMessage() async throws {
        let root = try await settledScreen(
            item: .inbox,
            route: Self.route([Self.sms, Self.email]),
            rules: Self.draft + ScreenRules.loaded
        )
        // The thread's history is the scroll view with the most to scroll; the list column, the
        // sidebar and the reply box hold less than their height here.
        let history = try XCTUnwrap(
            Self.scrollViews(in: root)
                .filter { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1 }
                .max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) },
            "the thread's history did not overflow the window, so this test proves nothing"
        )
        let document = try XCTUnwrap(history.documentView)
        let visible = history.contentView.documentVisibleRect
        let atEnd = document.isFlipped
            ? visible.maxY >= document.bounds.maxY - 1
            : visible.minY <= document.bounds.minY + 1
        XCTAssertTrue(
            atEnd,
            "the thread opened with \(visible) of its \(document.bounds) history visible, not its end"
        )
    }

    private static func route(_ targets: [ReplyTarget]) -> Route {
        .thread(
            workspaceId: workspaceId,
            role: .agency,
            threadKey: threadKey,
            replyTargets: targets,
            title: "Contract Test Caller"
        )
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func thread(
        _ name: String,
        _ targets: [ReplyTarget],
        rules: [FixtureTransport.Rule] = [],
        locale: L10nLocale = .en,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        try await assertScreen(
            name,
            item: .inbox,
            route: Self.route(targets),
            rules: rules + ScreenRules.loaded,
            locale: locale,
            file: file,
            testName: testName,
            line: line
        )
    }
}
