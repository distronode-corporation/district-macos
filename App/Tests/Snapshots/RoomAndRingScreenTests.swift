import DistrictData
import DistrictL10n
import DistrictLive
@testable import DistrictMac
import DistrictNetwork
import SwiftUI
import XCTest

/// A meeting room before it is joined and with its join refused, the ring panel in each way
/// a ring ends, and the Voice Studio's tuning controls for every leg of the chain.
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class RoomAndRingScreenTests: ScreenSnapshotCase {
    /// The live room in `district-meetings.json`.
    private static let roomName = "meet_ws-contract-test_standup"
    /// The call in `district-call-detail.json`, which the ring looks its caller up from.
    private static let callId = "call_contract_answered"
    /// The ring panel's content size (``RingPanelController``).
    private static let panelSize = CGSize(width: 380, height: 360)
    /// The tuning controls are drawn whole, so taller than a sheet.
    private static let tuningSize = CGSize(width: 560, height: 1000)

    /// The models the screens draw, held here: the call stack keeps its ring and room claims
    /// only while they are live.
    private var held: [AnyObject] = []

    override func tearDown() async throws {
        held = []
        try await super.tearDown()
    }

    // MARK: - Active room

    func testRoomBeforeJoining() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertScreen(
                Self.named("agency", locale),
                item: .rooms,
                route: .activeRoom(workspaceId: Self.workspaceId, role: .agency, roomName: Self.roomName),
                rules: ScreenRules.loaded,
                locale: locale
            )
        }
        try await assertScreen(
            "viewer-en",
            item: .rooms,
            route: .activeRoom(workspaceId: Self.workspaceId, role: .viewer, roomName: Self.roomName),
            rules: ScreenRules.loaded
        )
    }

    /// Join pressed, and the room's token refused: back before the join, saying why.
    ///
    /// ⚠️ THE MODEL IS THE SCREEN'S OWN: it is claimed as the call stack's room while the
    /// screen is built, so the screen adopts it (``ActiveRoomModel/attached(to:roomName:)``),
    /// then given back before the join, which claims it again itself.
    func testRoomJoinRefused() async throws {
        try await assertView(
            "refused-en",
            rules: Self.refusingWrites() + ScreenRules.loaded,
            size: Self.regular
        ) { app in
            guard let room = RoomName(joining: Self.roomName) else {
                throw Fixtures.Missing.fixture(Self.roomName)
            }
            let calls = app.container.callStack
            let model = ActiveRoomModel(
                container: app.container,
                roomName: room,
                role: .agency,
                askPermissions: { RoomPermissions(requested: true, microphoneGranted: true, cameraGranted: true) }
            )
            held.append(model)
            calls.claimRoom(model)
            Self.once({ true }, {
                // The screen is built on the first layout, before this runs.
                try? await Task.sleep(for: .milliseconds(500))
                calls.releaseRoom(model)
                await model.join()
            })
            var paths = ShellPaths()
            paths.select(.rooms)
            paths.open(.activeRoom(workspaceId: app.workspaceId, role: .agency, roomName: Self.roomName))
            return AnyView(
                ShellView(container: app.container, session: app.session, push: app.push, live: app.live, paths: paths)
            )
        }
    }

    // MARK: - The ring's ends

    func testRingEnds() async throws {
        let ends: [(String, DesktopRingEnd)] = [
            ("timed-out", .timedOut),
            ("caller-hung-up", .callEnded),
            ("answered-elsewhere", .cancelled(.answered)),
            ("declined-elsewhere", .cancelled(.declined)),
        ]
        for (name, end) in ends {
            try await ring("\(name)-en") { model in
                model.ringStopped(workspaceId: Self.workspaceId, callId: Self.callId, reason: end)
            }
        }
        try await ring("answered-elsewhere-fr", locale: .frCA) { model in
            model.ringStopped(workspaceId: Self.workspaceId, callId: Self.callId, reason: .cancelled(.answered))
        }
        // Answer pressed on a Mac whose microphone is denied (the harness's).
        try await ring("answer-no-microphone-en") { model in model.answerPressed() }
    }

    private func ring(
        _ name: String,
        locale: L10nLocale = .en,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        then action: @escaping @MainActor (IncomingCallModel) -> Void
    ) async throws {
        try await assertView(
            name,
            rules: ScreenRules.loaded,
            locale: locale,
            size: Self.panelSize,
            file: file,
            testName: testName,
            line: line
        ) { app in
            let model = IncomingCallModel(container: app.container, presenter: SilentRing())
            held.append(model)
            model.sessionChanged(.signedIn)
            model.ringStarted(workspaceId: app.workspaceId, callId: Self.callId, workspaceName: "Zulu Agency")
            Self.once({ model.isRinging }, { action(model) })
            return AnyView(IncomingCallView(model: model, devices: app.container.callStack.devices)
                .frame(minWidth: 340, minHeight: 320)
                .sheetPage()
                .districtTheme())
        }
    }

    /// The panel's ringer and notification, which a snapshot neither plays nor posts.
    private final class SilentRing: RingPresenting {
        func startRinging(workspaceId _: String, callId _: String) {}
        func stopRinging() {}
        func withdrawAlerts(callId _: String) {}
    }

    // MARK: - Voice Studio tuning

    func testTuningEar() async throws {
        try await tuning(.stt)
    }

    func testTuningTurns() async throws {
        try await tuning(.turn)
    }

    func testTuningBrain() async throws {
        try await tuning(.llm)
    }

    func testTuningMouth() async throws {
        try await tuning(.tts)
    }

    /// Every tuning control the recorded Studio offers for `leg`, main and advanced together,
    /// as the leg editor lists them (its advanced group opened).
    private func tuning(
        _ leg: VoiceStudioLeg,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named(leg.rawValue, locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.tuningSize,
                file: file,
                testName: testName,
                line: line
            ) { app in
                let model = VoiceStudioModel(container: app.container, workspaceId: app.workspaceId, role: .agency)
                await model.loadStudio()
                model.selectLeg(leg)
                let session = try XCTUnwrap(model.session, "the recorded Voice Studio did not load")
                let keys = VoiceStudioTuning.keys(for: leg, engine: session.held.engine, in: session.studio)
                return AnyView(ScrollView {
                    VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
                        VoiceStudioTuningList(model: model, session: session, keys: keys)
                    }
                    .padding(DistrictSpacing.gutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .sheetPage()
                .districtTheme())
            }
        }
    }
}
