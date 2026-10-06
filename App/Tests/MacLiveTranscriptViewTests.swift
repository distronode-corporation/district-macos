import AppKit
import DistrictLive
@testable import DistrictMac
import DistrictModel
import Foundation
import SwiftUI
import Testing

/// ⛔ THE LIVE TRANSCRIPT SECTION, DRAWN IN EVERY STATE ITS MODEL REACHES.
///
/// Each state is reached the way the app reaches it: the real model and the core's reducer,
/// fed the frames the contract defines (§4.11, §4.12) through the model's ``TranscriptFeed``,
/// as ``DesktopLive`` feeds it, with a manual clock, so the full transcript's backoff takes no
/// time. Each is drawn in a window, which runs the section's body, and what it drew is read
/// from ``LiveTranscriptContent``, the one value the body lays out.
///
/// ⚠️ NOT READ BACK THROUGH ACCESSIBILITY, AS district-ios's `LiveTranscriptViewTests` IS: on
/// the Mac, SwiftUI builds no accessibility element for a hosting view in a unit test, on or
/// off screen, key or not, with the AX "enhanced UI", "manual accessibility" or automation
/// switches set (measured on macOS 15 with Xcode 26.3: the hosting view answers with no
/// child at all). The identifiers are asserted on the phone, from the same view code.
@MainActor
@Suite(.serialized)
struct MacLiveTranscriptViewTests {
    private typealias Line = LiveTranscriptContent.Line

    private let clock = ManualLiveClock()
    /// ⚠️ HELD HERE: the model keeps its channel weakly, as it does ``DesktopLive``.
    private let channel = FakeChannel()

    private func makeModel(_ answers: [Result<String, ApiError>] = [.success("")]) -> (LiveTranscriptModel, Answers) {
        let answers = Answers(answers)
        let model = LiveTranscriptModel(callId: "call_1", channel: channel, clock: clock) { answers.next() }
        return (model, answers)
    }

    /// Watched, with the socket open and the subscribe sent.
    private func open(_ model: LiveTranscriptModel) {
        model.activate()
        model.handle(.connected)
    }

    private func deliver(_ model: LiveTranscriptModel, _ json: String) throws {
        let envelope = try JSONDecoder().decode(TelemetryEnvelope.self, from: Data(json.utf8))
        try model.handle(.event(#require(envelope.transcriptEvent)))
    }

    /// Draw the section for `model` as it stands, in a window that is never ordered in, and
    /// return what it drew. ⚠️ `layoutSubtreeIfNeeded` RUNS THE BODY THERE AND THEN; a drawing
    /// with no height would mean it drew nothing.
    private func drawn(
        _ model: LiveTranscriptModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> LiveTranscriptContent {
        let host = NSHostingView(rootView: LiveTranscriptSection(model: model).frame(width: 480))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0, sourceLocation: sourceLocation)
        window.contentView = nil
        window.close()
        return LiveTranscriptContent(model)
    }

    /// Move the manual clock in steps until `condition` holds, letting the waits each step
    /// wakes run. ⚠️ Steps, not one jump: a wait that starts after a jump is timed from after it.
    private func advance(until condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0 ..< 400 where !condition() {
            clock.advance(by: 1000)
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }

    // MARK: - Before the first line

    /// Watched, the snapshot not in yet (the server holds it until the first line, up to
    /// 30 s): "Connecting…" and nothing else, while the socket opens and once it is open.
    @Test func `connecting shows connecting and nothing else`() {
        let (model, _) = makeModel()
        model.activate()
        #expect(model.connection == .connecting)

        let opening = drawn(model)
        #expect(opening.status == "Connecting…")
        #expect(!opening.waiting, "not live yet, so not 'nothing said'")
        #expect(!opening.incomplete)
        #expect(opening.lines.isEmpty)
        #expect(opening.final == .none)

        model.handle(.connected)
        #expect(model.connection == .open)
        #expect(drawn(model).status == "Connecting…")
        model.deactivate()
    }

    // MARK: - Live

    /// The lines as they are spoken: the persona's name on an assistant line, "Caller", a
    /// fallback for an unnamed assistant and an unknown speaker, "Interrupted" under a line
    /// that was cut off, and an interim line drawn as provisional.
    @Test func `live lines name their speakers and mark an interruption`() throws {
        let (model, _) = makeModel()
        open(model)

        try deliver(model, Frame.snapshot(
            [Frame.greeting, Frame.segment("item_b2", index: 1, seq: 2, text: "A cleaning, please.")],
            lastSeq: 2
        ))
        try deliver(model, Frame.live(Frame.segment(
            "item_c3", index: 2, seq: 3, speaker: "agent", text: "Of course", interrupted: true
        )))
        try deliver(model, Frame.live(Frame.segment(
            "item_d4", index: 3, seq: 4, speaker: "agent", speakerName: "", text: "One moment."
        )))
        try deliver(model, Frame.live(Frame.segment(
            "item_e5", index: 4, seq: 5, speaker: "supervisor", text: "Joining now."
        )))
        try deliver(model, Frame.live(Frame.segment(
            "item_f6", index: 5, seq: 6, text: "Tuesday if you", final: false
        )))
        let shown = drawn(model)

        #expect(shown.status == "Live")
        #expect(shown.lines == [
            Line(id: "item_a1", speaker: "Ava", text: "Good afternoon.", provisional: false, interrupted: false),
            Line(id: "item_b2", speaker: "Caller", text: "A cleaning, please.", provisional: false, interrupted: false),
            Line(id: "item_c3", speaker: "Ava", text: "Of course", provisional: false, interrupted: true),
            Line(id: "item_d4", speaker: "Assistant", text: "One moment.", provisional: false, interrupted: false),
            Line(id: "item_e5", speaker: "Other speaker", text: "Joining now.", provisional: false, interrupted: false),
            Line(id: "item_f6", speaker: "Caller", text: "Tuesday if you", provisional: true, interrupted: false),
        ])
        #expect(!shown.waiting)
        #expect(!shown.incomplete)
        #expect(shown.final == .none)
        model.deactivate()
    }

    /// ⛔ D3: A SNAPSHOT THAT DOES NOT REACH BACK TO THE CALL'S FIRST LINE SAYS SO, above the
    /// lines it does have.
    @Test func `an incomplete snapshot says earlier lines come after the call`() throws {
        let (model, _) = makeModel()
        open(model)

        try deliver(model, Frame.snapshot(
            [Frame.segment("item_k9", index: 9, seq: 14, text: "And the address?")],
            lastSeq: 14,
            complete: false
        ))
        let shown = drawn(model)

        #expect(shown.incomplete)
        #expect(LiveTranscriptCopy.incomplete == "Earlier lines will appear in the full transcript after the call.")
        #expect(shown.lines.map(\.text) == ["And the address?"])
        #expect(shown.status == "Live")
        model.deactivate()
    }

    // MARK: - Reconnecting and the end

    /// ⛔ `agent_error` IS NOT THE END: "Reconnecting…", the lines stay, nothing is fetched.
    @Test func `an agent error shows reconnecting and keeps the lines`() throws {
        let (model, answers) = makeModel([.success("never asked")])
        open(model)
        try deliver(model, Frame.snapshot([Frame.greeting], lastSeq: 1))
        #expect(drawn(model).status == "Live")

        try deliver(model, Frame.ended(seq: 2, reason: "agent_error"))
        let shown = drawn(model)

        #expect(shown.status == "Reconnecting…")
        #expect(shown.lines.map(\.text) == ["Good afternoon."])
        #expect(shown.final == .none)
        #expect(answers.count == 0)
        model.deactivate()
    }

    /// The call ended: "Call ended" and a spinner with "Loading the full transcript…" while it
    /// is fetched (it is written only after the call's session closes), then the full
    /// transcript in place of the spinner, with the live lines kept above it.
    @Test func `the end loads the full transcript then shows it`() async throws {
        let (model, _) = makeModel([.success(""), .success("Ava: Good afternoon.\nCaller: Hi.")])
        open(model)
        try deliver(model, Frame.snapshot([Frame.greeting], lastSeq: 1))

        model.handle(.callEnded)
        let loading = drawn(model)
        #expect(loading.status == "Call ended")
        #expect(loading.final == .loading)
        #expect(loading.lines.map(\.text) == ["Good afternoon."], "the live lines stay while it loads")

        await advance { model.finalTranscript == .loaded("Ava: Good afternoon.\nCaller: Hi.") }
        let loaded = drawn(model)
        #expect(loaded.final == .loaded("Ava: Good afternoon.\nCaller: Hi."))
        #expect(loaded.status == "Call ended")
    }

    /// Still empty after every attempt: "No transcript for this call."
    @Test func `an empty full transcript says there is none`() async throws {
        let (model, answers) = makeModel([.success("  ")])
        open(model)
        try deliver(model, Frame.snapshot([Frame.greeting], lastSeq: 1))
        try deliver(model, Frame.ended(seq: 2, reason: "handed_off"))
        #expect(drawn(model).final == .loading)

        await advance { model.finalTranscript == .empty }
        let shown = drawn(model)

        #expect(shown.final == .empty)
        #expect(shown.status == "Call ended")
        #expect(answers.count == TranscriptReducer.finalFetchAttempts)
    }

    /// A fetch refused for good: the failure's words, in place of the transcript.
    @Test func `a failed full transcript says why`() async throws {
        let refusal = ApiError.http(status: 404, message: "Call not found")
        let (model, _) = makeModel([.failure(refusal)])
        open(model)
        try deliver(model, Frame.snapshot([Frame.greeting], lastSeq: 1))
        try deliver(model, Frame.ended(seq: 2))

        await advance { model.finalTranscript == .failed(refusal) }
        let shown = drawn(model)

        #expect(shown.final == .failed("Call not found"))
        #expect(shown.status == "Call ended")
    }

    // MARK: - No live transcript

    /// ⛔ `not_live`, OR A SOCKET THAT ENDED FOR GOOD: the model falls back, which is what makes
    /// the call's screen swap this section for the transcript after the call
    /// (`CallDetailView.transcriptSection`). Drawn anyway, it draws no line and no fetch.
    @Test(arguments: [true, false])
    func `no live transcript falls back to the transcript after the call`(notLive: Bool) throws {
        let (model, _) = makeModel()
        open(model)

        if notLive {
            try deliver(model, Frame.error("not_live"))
            #expect(model.phase == .unavailable(.notLive))
        } else {
            model.handle(.failed)
            #expect(model.connection == .failed)
        }
        let shown = drawn(model)

        #expect(model.fallsBack)
        #expect(!shown.waiting)
        #expect(shown.lines.isEmpty)
        #expect(shown.final == .none)
        model.deactivate()
    }

    // MARK: - Retracted and purged

    /// ⛔ A RETRACTED LINE COMES OFF THE SCREEN, and once every line is retracted the live
    /// pane says nothing has been said rather than keeping a stale line.
    @Test func `retracted lines come off the screen`() throws {
        let (model, _) = makeModel()
        open(model)
        try deliver(model, Frame.snapshot(
            [Frame.greeting, Frame.segment("item_b2", index: 1, seq: 2, text: "My card is 4111.")],
            lastSeq: 2
        ))
        #expect(drawn(model).lines.map(\.id) == ["item_a1", "item_b2"])

        try deliver(model, Frame.retracted(["item_b2"], seq: 3))
        let one = drawn(model)
        #expect(one.lines.map(\.id) == ["item_a1"])
        #expect(!one.waiting)

        try deliver(model, Frame.retracted([], all: true))
        let none = drawn(model)
        #expect(none.lines.isEmpty)
        #expect(none.waiting)
        #expect(none.status == "Live")
        model.deactivate()
    }

    /// ⛔ §4.12 Q12: THE SNAPSHOT AFTER A PURGE HAS NO EPOCH AND NO LINE. The pane is live and
    /// empty, and the next line sets the baseline and is drawn.
    @Test func `a purged snapshot is live and empty until the next line`() throws {
        let (model, _) = makeModel()
        open(model)

        try deliver(model, Frame.purgedSnapshot)
        let empty = drawn(model)
        #expect(empty.waiting)
        #expect(empty.status == "Live")

        try deliver(model, Frame.live(Frame.segment("item_z1", index: 7, seq: 12, text: "Still there?")))
        let line = drawn(model)
        #expect(line.lines.map(\.text) == ["Still there?"])
        #expect(!line.waiting)
        model.deactivate()
    }
}

/// Answers for the full-transcript fetch, in order; the last one repeats.
private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<String, ApiError>]
    private var calls = 0

    init(_ answers: [Result<String, ApiError>]) {
        self.answers = answers
    }

    var count: Int {
        lock.withLock { calls }
    }

    func next() -> Result<String, ApiError> {
        lock.withLock {
            calls += 1
            return answers.count > 1 ? answers.removeFirst() : answers[0]
        }
    }
}

/// The contract's frames (§4.11), as the server sends them. Ported from district-ios
/// `TranscriptWire` (`App/Tests/LiveTestSupport.swift`).
private enum Frame {
    static let epoch: Int64 = 1_791_297_000_000

    static func envelope(_ eventType: String, _ data: String) -> String {
        #"{"workspaceId":"ws_1","callId":"call_1","eventType":"\#(eventType)","data":\#(data),"#
            + #""timestamp":"2026-10-06T14:30:02.010Z"}"#
    }

    static func segment(
        _ segmentId: String,
        index: Int,
        seq: Int,
        speaker: String = "caller",
        speakerName: String? = "Ava",
        text: String,
        final: Bool = true,
        interrupted: Bool = false
    ) -> String {
        // The persona's name rides an assistant line only.
        let name = speaker == "agent" ? speakerName.map { #""\#($0)""# } ?? "null" : "null"
        return #"{"segmentId":"\#(segmentId)","index":\#(index),"epoch":\#(epoch),"seq":\#(seq),"rev":0,"#
            + #""speaker":"\#(speaker)","speakerName":\#(name),"text":"\#(text)","final":\#(final),"#
            + #""interrupted":\#(interrupted),"language":"en","startedAt":"2026-10-06T14:30:03.100Z","#
            + #""endedAt":\#(final ? #""2026-10-06T14:30:06.300Z""# : "null")}"#
    }

    static let greeting = segment("item_a1", index: 0, seq: 1, speaker: "agent", text: "Good afternoon.")

    static func live(_ segment: String) -> String {
        envelope("transcript_segment", #"{"v":1,"callId":"call_1","segment":\#(segment)}"#)
    }

    static func snapshot(_ segments: [String], lastSeq: Int, complete: Bool = true) -> String {
        envelope(
            "transcript_snapshot",
            #"{"v":1,"callId":"call_1","live":true,"endedReason":null,"complete":\#(complete),"#
                + #""epoch":\#(epoch),"lastSeq":\#(lastSeq),"segments":[\#(segments.joined(separator: ","))],"#
                + #""part":0,"more":false}"#
        )
    }

    /// The snapshot after an `all: true` purge emptied the server's memory of the call: no
    /// epoch, no `lastSeq` and no line (contract §4.12 Q12).
    static let purgedSnapshot = envelope(
        "transcript_snapshot",
        #"{"v":1,"callId":"call_1","live":true,"endedReason":null,"complete":true,"epoch":null,"#
            + #""lastSeq":null,"segments":[],"part":0,"more":false}"#
    )

    static func ended(seq: Int, reason: String = "call_ended") -> String {
        envelope(
            "transcript_ended",
            #"{"v":1,"callId":"call_1","epoch":\#(epoch),"seq":\#(seq),"lastIndex":1,"reason":"\#(reason)"}"#
        )
    }

    /// `transcript_retracted`: the assistant's (with its epoch and seq) unless `seq` is nil,
    /// which is the website's (a contact erase), with neither.
    static func retracted(_ segmentIds: [String], all: Bool = false, seq: Int? = nil) -> String {
        let counter = seq.map { #""epoch":\#(epoch),"seq":\#($0)"# } ?? #""epoch":null,"seq":null"#
        let ids = segmentIds.map { #""\#($0)""# }.joined(separator: ",")
        return envelope(
            "transcript_retracted",
            #"{"v":1,"callId":"call_1",\#(counter),"all":\#(all),"segmentIds":[\#(ids)],"reason":"erased"}"#
        )
    }

    static func error(_ code: String) -> String {
        envelope(
            "transcript_error",
            #"{"v":1,"callId":"call_1","op":"transcript.subscribe","code":"\#(code)","retryAfterMs":null}"#
        )
    }
}
