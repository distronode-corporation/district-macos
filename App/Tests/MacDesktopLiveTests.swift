import AppKit
import DistrictLive
@testable import DistrictMac
import XCTest

/// ⛔ WHEN THIS MAC RINGS: a live session runs while someone is signed in, a workspace is
/// selected, "Ring on this computer" is on and the Mac is awake, and stops on sleep, quit,
/// sign-out and the setting going off.
///
/// The session itself is a recording fake, so these tests are about the lifecycle and
/// nothing else: no socket, no presence, no server.
@MainActor
final class MacDesktopLiveTests: XCTestCase {
    /// ⚠️ NOT PRIVATE: `MacLiveTranscriptTests` drives the same fake.
    final class FakeSession: LiveSessionRunning {
        let workspaceId: String
        let rings: Bool
        let startedWith: Set<String>
        let onTranscript: @MainActor (TelemetryUpdate) -> Void
        private(set) var stops = 0
        private(set) var signOuts = 0
        private(set) var clears = 0
        /// Every transcript op, in order: `+id`, `-id`, `~id`.
        private(set) var ops: [String] = []

        init(request: LiveSessionRequest) {
            workspaceId = request.workspaceId
            rings = request.rings
            startedWith = request.transcriptCallIds
            onTranscript = request.onTranscript
        }

        func subscribeTranscript(callId: String) {
            ops.append("+\(callId)")
        }

        func unsubscribeTranscript(callId: String) {
            ops.append("-\(callId)")
        }

        func resubscribeTranscript(callId: String) {
            ops.append("~\(callId)")
        }

        func stop() async {
            stops += 1
        }

        func signOut() async {
            signOuts += 1
        }

        func clearRing() {
            clears += 1
        }
    }

    private final class Activities {
        private(set) var begun = 0
        private(set) var ended = 0
        var held: Int {
            begun - ended
        }

        func begin() {
            begun += 1
        }

        func end() {
            ended += 1
        }
    }

    /// ⚠️ IN MEMORY: the test host shares the installed app's container, so nothing here
    /// may write a defaults suite. See ``RingSetting``.
    private final class SettingBox {
        var stored: Bool?
    }

    private var box = SettingBox()
    private var setting: RingSetting {
        let box = box
        return RingSetting(load: { box.stored }, save: { box.stored = $0 })
    }

    private var center: NotificationCenter!
    private var sessions: [FakeSession] = []
    private var activities = Activities()
    private var factoryRefuses = false

    override func setUp() async throws {
        box = SettingBox()
        center = NotificationCenter()
        sessions = []
        activities = Activities()
        factoryRefuses = false
    }

    private func makeLive() -> DesktopLive {
        let activities = activities
        return DesktopLive(
            calls: CallStack(microphone: FakeMicrophoneAccess(status: .granted)),
            setting: setting,
            workspaceCenter: center,
            beginActivity: {
                activities.begin()
                return NSObject()
            },
            endActivity: { _ in activities.end() },
            factory: { [weak self] request in
                guard let self, !factoryRefuses else { return nil }
                let session = FakeSession(request: request)
                sessions.append(session)
                request.onStatus(.live)
                return session
            }
        )
    }

    private var running: [FakeSession] {
        sessions.filter { $0.stops == 0 && $0.signOuts == 0 }
    }

    // MARK: - The setting

    func test_MAC_LIVE_01_ringingIsOnByDefaultAndRemembered() async {
        let live = makeLive()
        XCTAssertTrue(live.ringHere, "a new installation rings")

        live.setRingHere(false)
        await live.settled()

        XCTAssertEqual(box.stored, false)
        XCTAssertFalse(makeLive().ringHere, "the choice survives a relaunch")
    }

    func test_MAC_LIVE_02_aSessionRunsOnlyWithAWorkspaceSignedInAndTheSettingOn() async {
        let live = makeLive()
        live.signedIn(workspaceId: nil, workspaceName: nil)
        await live.settled()
        XCTAssertTrue(sessions.isEmpty, "no workspace, nothing to ring for")

        live.signedIn(workspaceId: "ws_1", workspaceName: "Acme")
        await live.settled()
        XCTAssertEqual(running.map(\.workspaceId), ["ws_1"])
        XCTAssertEqual(live.runningWorkspaceId, "ws_1")
        XCTAssertEqual(live.status, .live)

        live.setRingHere(false)
        await live.settled()
        XCTAssertTrue(running.isEmpty, "the setting off stops the session")
        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertEqual(sessions.first?.signOuts, 0, "switching it off withdraws nothing")
        XCTAssertEqual(live.status, .off)

        live.setRingHere(true)
        await live.settled()
        XCTAssertEqual(running.map(\.workspaceId), ["ws_1"], "and on starts a fresh one")
        XCTAssertEqual(sessions.count, 2)
    }

    // MARK: - Sleep and wake

    func test_MAC_LIVE_03_sleepStopsTheSessionAndWakeStartsAFreshOne() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await live.settled()
        XCTAssertTrue(running.isEmpty, "a sleeping Mac must not hold callers on a ring nobody hears")
        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertFalse(live.awake)

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await live.settled()
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(sessions.count, 2, "the session before the sleep is never reused")
    }

    func test_MAC_LIVE_04_sleepEndsALiveCall() async {
        let calls = CallStack(microphone: FakeMicrophoneAccess(status: .granted))
        let owner = RecordingCallOwner()
        XCTAssertTrue(calls.claimCall(owner))
        let live = DesktopLive(calls: calls, setting: setting, workspaceCenter: center) { _ in nil }

        live.willSleep()
        await live.settled()

        XCTAssertEqual(owner.systemEnds, 1, "the call cannot survive the network going with the sleep")
    }

    // MARK: - Sign-out, the server ending the session, and quitting

    func test_MAC_LIVE_05_signOutWithdrawsThePresenceAndStops() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        await live.signOut()

        XCTAssertEqual(sessions.first?.signOuts, 1, "PresenceController.signOut, before the revoke")
        XCTAssertEqual(sessions.first?.stops, 0)
        XCTAssertNil(live.runningWorkspaceId)
        XCTAssertEqual(live.status, .off)
        XCTAssertEqual(activities.held, 0)

        live.setRingHere(true)
        await live.settled()
        XCTAssertEqual(sessions.count, 1, "nothing restarts until someone signs in again")
    }

    func test_MAC_LIVE_06_aSessionTheServerEndedStopsWithoutWithdrawing() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        live.sessionEnded()
        await live.settled()

        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertEqual(sessions.first?.signOuts, 0, "there is no bearer left to unregister with")
    }

    func test_MAC_LIVE_07_quittingStops() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        await live.terminate()

        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertEqual(activities.held, 0)
    }

    func test_MAC_LIVE_08_aNewWorkspaceReplacesTheSession() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()
        live.signedIn(workspaceId: "ws_2", workspaceName: nil)
        await live.settled()

        XCTAssertEqual(sessions.map(\.workspaceId), ["ws_1", "ws_2"])
        XCTAssertEqual(sessions.first?.stops, 1)
        XCTAssertEqual(running.map(\.workspaceId), ["ws_2"])
    }

    // MARK: - App Nap

    func test_MAC_LIVE_09_appNapIsHeldOffExactlyWhileASessionRuns() async {
        let live = makeLive()
        XCTAssertEqual(activities.held, 0)

        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()
        XCTAssertEqual(activities.held, 1)

        live.signedIn(workspaceId: "ws_2", workspaceName: nil)
        await live.settled()
        XCTAssertEqual(activities.held, 1, "one activity across a workspace switch, never two")

        live.willSleep()
        await live.settled()
        XCTAssertEqual(activities.held, 0)
    }

    func test_MAC_LIVE_10_aStartThatFailsHoldsNothingAndSaysWhy() async {
        factoryRefuses = true
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        XCTAssertEqual(activities.held, 0)
        XCTAssertNil(live.runningWorkspaceId)
    }

    func test_MAC_LIVE_11_aSettledRingIsHandedToTheSession() async {
        let live = makeLive()
        live.signedIn(workspaceId: "ws_1", workspaceName: nil)
        await live.settled()

        live.ringSettled()

        XCTAssertEqual(sessions.first?.clears, 1)
    }

    // MARK: - The line under the setting

    func test_MAC_LIVE_12_onlyAnUnavailableStatusSaysAnything() {
        XCTAssertNil(DesktopLiveCopy.message(.off))
        XCTAssertNil(DesktopLiveCopy.message(.connecting))
        XCTAssertNil(DesktopLiveCopy.message(.live))
        XCTAssertEqual(DesktopLiveCopy.message(.unavailable("")), "Calls cannot ring here right now.")
        XCTAssertEqual(
            DesktopLiveCopy.message(.unavailable(DesktopLiveCopy.forbidden)),
            "Calls cannot ring here right now. Live updates are not available to you in this workspace."
        )
    }

    func test_MAC_LIVE_13_liveNeedsBothTheSocketAndThePresence() {
        XCTAssertEqual(DesktopLiveCopy.status(socketOpen: true, socketEnded: .none, presence: .registered), .live)
        XCTAssertEqual(
            DesktopLiveCopy.status(socketOpen: true, socketEnded: .none, presence: .registering),
            .connecting
        )
        XCTAssertEqual(
            DesktopLiveCopy.status(socketOpen: false, socketEnded: .none, presence: .registered),
            .connecting
        )
        XCTAssertEqual(
            DesktopLiveCopy.status(
                socketOpen: false,
                socketEnded: .some(DesktopLiveCopy.unusable),
                presence: .registered
            ),
            .unavailable(DesktopLiveCopy.unusable)
        )
        if case .unavailable = DesktopLiveCopy.status(
            socketOpen: true,
            socketEnded: .none,
            presence: .failed(.http(status: 503, message: nil))
        ) {} else {
            XCTFail("a failed presence means calls cannot ring here")
        }
    }
}

/// A call owner that counts how often the system ended it.
@MainActor
final class RecordingCallOwner: LiveCallOwner {
    private(set) var systemEnds = 0

    func endForSystem() async {
        systemEnds += 1
    }
}
