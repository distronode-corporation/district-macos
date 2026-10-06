import AppKit
import DistrictLive
@testable import DistrictMac
import DistrictModel
import XCTest

/// ⛔ THE LIVE TRANSCRIPT AGAINST THE REVISED CONTRACT'S §4.12: `not_live` is final for its
/// subscribe and only a call-status signal subscribes again, and `agent_error` reconnects
/// rather than ends. The rules are district-core-swift's `TranscriptReducer`; this is the
/// Mac's wiring of them (``DesktopLive`` and the call screen's model).
@MainActor
final class MacLiveTranscriptContractTests: XCTestCase {
    private typealias FakeSession = MacDesktopLiveTests.FakeSession

    private var sessions: [FakeSession] = []
    private var center = NotificationCenter()
    private var ringSetting: Bool?

    private var running: [FakeSession] {
        sessions.filter { $0.stops == 0 && $0.signOuts == 0 }
    }

    private func makeLive(ringHere: Bool) -> DesktopLive {
        ringSetting = ringHere
        return DesktopLive(
            calls: CallStack(microphone: FakeMicrophoneAccess(status: .granted)),
            setting: RingSetting(
                load: { [weak self] in self?.ringSetting },
                save: { [weak self] in self?.ringSetting = $0 }
            ),
            workspaceCenter: center,
            beginActivity: { NSObject() },
            endActivity: { _ in },
            factory: { [weak self] request in
                let session = FakeSession(request: request)
                self?.sessions.append(session)
                return session
            }
        )
    }

    private func envelope(_ eventType: String, callId: String = "call_1", data: String) -> TelemetryEnvelope? {
        try? JSONDecoder().decode(TelemetryEnvelope.self, from: Data("""
        {"workspaceId":"ws_1","callId":"\(callId)","eventType":"\(eventType)","data":\(data),"timestamp":"t"}
        """.utf8))
    }

    private func event(_ eventType: String, _ data: String) throws -> TranscriptEvent {
        try XCTUnwrap(envelope(eventType, data: data)?.transcriptEvent)
    }

    private var snapshot: TelemetryEnvelope? {
        envelope("transcript_snapshot", data: """
        {"v":1,"callId":"call_1","live":true,"complete":true,"epoch":1,"lastSeq":1,"segments":[\
        {"segmentId":"item_a1","index":0,"epoch":1,"seq":1,"rev":0,"speaker":"agent","speakerName":"Ava",\
        "text":"Good afternoon","final":true,"interrupted":false,"language":"en","startedAt":"t","endedAt":"t"}],\
        "part":0,"more":false}
        """)
    }

    private var notLive: String {
        #"{"v":1,"callId":"call_1","op":"transcript.subscribe","code":"not_live","retryAfterMs":null}"#
    }

    // MARK: - The revised contract (§4.12)

    /// ⛔ §4.12 Q4: AFTER `not_live` A SCREEN STAYS ON THE CALL WITHOUT A SUBSCRIPTION. It
    /// hears the call's status and end (and keeps the socket running, ringing off) but no
    /// transcript frame; subscribing it again sends the subscribe, and leaving sends no
    /// unsubscribe for a call it was not subscribed to.
    func test_MAC_TRANSCRIPT_09_aWatchWithoutASubscriptionHearsOnlyTheCall() async throws {
        let live = makeLive(ringHere: false)
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        var heard: [TranscriptFeed] = []
        let watch = live.watchTranscript(callId: "call_1", subscribed: false) { heard.append($0) }
        await live.settled()
        let session = try XCTUnwrap(running.first)
        XCTAssertEqual(session.startedWith, [], "nothing to subscribe")
        XCTAssertEqual(session.rings, false)

        session.onTranscript(.connected)
        try session.onTranscript(.event(XCTUnwrap(snapshot)))
        try session.onTranscript(.event(XCTUnwrap(envelope(
            "call_updated",
            data: #"{"id":"call_1","status":"in-progress"}"#
        ))))
        try session.onTranscript(.event(XCTUnwrap(envelope("call_started", data: #"{"id":"call_1"}"#))))
        try session.onTranscript(.event(XCTUnwrap(envelope(
            "call_updated",
            callId: "call_2",
            data: #"{"id":"call_2","status":"completed"}"#
        ))))
        XCTAssertEqual(heard, [.callStatus("in-progress")], "a status, and nothing of the transcript")

        live.setTranscriptSubscribed(watch, true)
        live.setTranscriptSubscribed(watch, true)
        session.onTranscript(.connected)
        live.setTranscriptSubscribed(watch, false)
        live.stopWatchingTranscript(watch)
        await live.settled()

        XCTAssertEqual(heard.last, .connected)
        XCTAssertEqual(session.ops, ["+call_1", "-call_1"], "one each way, and none on leaving")
        XCTAssertTrue(running.isEmpty)
    }

    /// ⛔ THE MODEL: `not_live` falls back and drops the subscription but keeps the watch; no
    /// timer subscribes again, the same status does not, and a changed status does.
    func test_MAC_TRANSCRIPT_10_afterNotLiveOnlyAChangedStatusSubscribesAgain() async throws {
        let channel = FakeChannel()
        let clock = ManualLiveClock()
        let model = LiveTranscriptModel(callId: "call_1", channel: channel, clock: clock) { .success("") }
        model.callStatusChanged(to: "in-progress")
        model.activate()
        model.handle(.connected)

        try model.handle(.event(event(
            "transcript_error", notLive
        )))
        XCTAssertTrue(model.fallsBack)
        XCTAssertEqual(channel.watching, ["call_1"], "the screen still hears the call")
        XCTAssertEqual(channel.subscribed, [])
        for _ in 0 ..< 12 {
            clock.advance(by: 10000)
            try? await Task.sleep(for: .milliseconds(5))
        }
        model.handle(.callStatus("in-progress"))
        XCTAssertEqual(channel.subscribed, [], "neither time nor the same status subscribes again")

        model.handle(.callStatus("on-hold"))
        XCTAssertEqual(channel.subscribed, ["call_1"])
        XCTAssertFalse(model.fallsBack)
        XCTAssertEqual(model.phase, .subscribing)

        model.deactivate()
        model.activate()
        XCTAssertEqual(channel.subscribed, ["call_1"], "a screen shown again subscribes while it may")
    }

    /// A screen shown again after `not_live` watches without subscribing; the call row ending
    /// the call leaves it on the transcript after the call.
    func test_MAC_TRANSCRIPT_11_aScreenShownAgainAfterNotLiveDoesNotSubscribe() throws {
        let channel = FakeChannel()
        let model = LiveTranscriptModel(callId: "call_1", channel: channel, clock: ManualLiveClock()) { .success("") }
        model.activate()
        try model.handle(.event(event(
            "transcript_error", notLive
        )))
        model.deactivate()
        XCTAssertEqual(channel.watching, [])

        model.activate()
        XCTAssertEqual(channel.watching, ["call_1"])
        XCTAssertEqual(channel.subscribed, [])
        model.callEnded()
        XCTAssertTrue(model.fallsBack)
    }

    /// ⛔ §4.12 Q7: `agent_error` IS NOT THE END. "Reconnecting…", no fetch, and a fresh
    /// assistant's epoch makes it live again; the call row ending the call ends it.
    func test_MAC_TRANSCRIPT_12_anAgentErrorReconnectsUntilANewEpoch() throws {
        let channel = FakeChannel()
        let model = LiveTranscriptModel(callId: "call_1", channel: channel, clock: ManualLiveClock()) { .success("x") }
        model.activate()
        model.handle(.connected)
        try model.handle(.event(XCTUnwrap(snapshot?.transcriptEvent)))

        try model.handle(.event(event(
            "transcript_ended",
            #"{"v":1,"callId":"call_1","epoch":1,"seq":2,"lastIndex":0,"reason":"agent_error"}"#
        )))
        XCTAssertEqual(model.phase, .reconnecting)
        XCTAssertEqual(LiveTranscriptCopy.status(phase: model.phase, connection: model.connection), "Reconnecting…")
        XCTAssertEqual(model.finalTranscript, .notRequested)

        try model.handle(.event(event("transcript_segment", """
        {"v":1,"callId":"call_1","segment":{"segmentId":"n1","index":0,"epoch":2,"seq":1,"rev":0,"speaker":"agent",\
        "speakerName":"Ava","text":"Hello again","final":true,"interrupted":false,"language":"en",\
        "startedAt":"t","endedAt":"t"}}
        """)))
        XCTAssertEqual(model.phase, .live)
        XCTAssertEqual(LiveTranscriptCopy.status(phase: model.phase, connection: model.connection), "Live")

        model.callEnded()
        XCTAssertEqual(model.phase, .ended(.callEnded))
        model.callStatusChanged(to: "in-progress")
        XCTAssertEqual(model.phase, .ended(.callEnded), "a status after the end changes nothing")
    }
}
