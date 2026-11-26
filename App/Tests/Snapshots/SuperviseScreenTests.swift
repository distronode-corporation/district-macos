import DistrictCall
import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// Supervising a live call: on arrival, listening, a whisper sent, taken over, and a call
/// that has already ended, each over the recorded call and the recorded answers to the
/// listen token, the whisper and the takeover.
///
/// ⛔ NO ROOM IS JOINED. The media is the unit tests' ``FakeSuperviseMedia``, which claims
/// nothing and reports the engine events a test hands it; every request still goes to the
/// recorded answers. The screen finds the model the way the app does, as the call stack's
/// supervisor for that call (``SuperviseView``).
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class SuperviseScreenTests: ScreenSnapshotCase {
    /// The call in `district-call-detail.json`.
    private static let callId = "call_contract_answered"

    /// ⚠️ THE RECORDED CALL HAS ENDED; supervising needs one in progress, so its status says so.
    private static let inProgress: [FixtureTransport.Rule] = [
        .get("/api/district/calls/[^/]+", .edited("mobile/district-call-detail.json") { body in
            var call = body["call"] as? [String: Any] ?? [:]
            call["status"] = "in-progress"
            body["call"] = call
        }),
    ]

    /// The listen token, the whisper and the takeover, as recorded.
    private static let liveWrites: [FixtureTransport.Rule] =
        writes("/api/district/calls/token", .fixture("mobile/district-call-monitor-token.json"))
            + writes("/api/district/calls/whisper", .fixture("mobile/district-call-whisper.json"))
            + writes("/api/district/calls/[^/]+/takeover", .fixture("mobile/district-call-takeover.json"))

    /// The models the screens draw, held here: the call stack keeps its supervisor weakly.
    private var held: [AnyObject] = []

    override func tearDown() async throws {
        held = []
        try await super.tearDown()
    }

    func testArrival() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await supervise(Self.named("arrival", locale), locale: locale) { _, _ in }
        }
    }

    func testListening() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await supervise(Self.named("listening", locale), locale: locale) { model, media in
                await Self.listen(model, media)
            }
        }
    }

    func testWhisperSent() async throws {
        try await supervise("whisper-en") { model, media in
            await Self.listen(model, media)
            model.draft = "Offer the Thursday 2pm slot."
            await model.sendWhisper()
        }
    }

    func testTakenOver() async throws {
        try await supervise("taken-over-en") { model, media in
            await Self.listen(model, media)
            await model.takeOver()
            await Self.until { media.engines.contains { $0.leg == .takeover } }
            media.engine(.takeover, .connected)
            media.engine(.takeover, .microphoneChanged(enabled: true))
        }
    }

    func testEnded() async throws {
        // The recorded call, which has ended: no Listen, and no note box.
        try await supervise("ended-en", rules: ScreenRules.loaded) { _, _ in }
    }

    /// The supervise route over a model made from the recorded call, taken through `steps`
    /// before the screen is drawn.
    private func supervise(
        _ name: String,
        rules: [FixtureTransport.Rule] = SuperviseScreenTests.inProgress + ScreenRules.loaded,
        locale: L10nLocale = .en,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        steps: @escaping @MainActor (SuperviseModel, FakeSuperviseMedia) async -> Void
    ) async throws {
        try await assertView(
            name,
            rules: Self.liveWrites + rules,
            locale: locale,
            size: Self.regular,
            file: file,
            testName: testName,
            line: line
        ) { app in
            let calls = app.container.calls
            let workspaceId = app.workspaceId
            guard case let .success(call) = await calls.detail(workspaceId: workspaceId, callId: Self.callId) else {
                throw Fixtures.Missing.fixture("mobile/district-call-detail.json")
            }
            let media = FakeSuperviseMedia()
            let model = SuperviseModel(
                call: call,
                workspaceId: workspaceId,
                role: .agency,
                server: calls,
                media: media,
                transcript: LiveTranscriptModel(callId: call.id, channel: app.live) {
                    await calls.transcript(workspaceId: workspaceId, callId: Self.callId)
                },
                events: LiveEventFeed(workspaceId: workspaceId, dependencies: SuperviseFixtures.feedDependencies())
            )
            held.append(model)
            held.append(media)
            app.container.callStack.supervisor = model
            await steps(model, media)
            var paths = ShellPaths()
            paths.select(.live)
            paths.open(.superviseCall(workspaceId: workspaceId, role: .agency, callId: Self.callId))
            return AnyView(
                ShellView(container: app.container, session: app.session, push: app.push, live: app.live, paths: paths)
            )
        }
    }

    /// Listen, and the listen leg's engine reports it is in the room.
    private static func listen(_ model: SuperviseModel, _ media: FakeSuperviseMedia) async {
        await model.listen()
        await until { media.engines.contains { $0.leg == .listen } }
        media.engine(.listen, .connected)
        await until { model.state.phase == .listening }
    }

    /// Wait, at most 5 seconds, for `condition`.
    private static func until(_ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
