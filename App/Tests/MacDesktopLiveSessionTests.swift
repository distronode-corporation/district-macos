import DistrictLive
@testable import DistrictMac
import DistrictModel
import XCTest

/// ⛔ THE WIRING BETWEEN THE CORE'S SOCKET, PRESENCE AND RING GATE, ON THE REAL CORE.
///
/// `TelemetryConnectionRunner`, `PresenceController` and `DesktopRingGate` are
/// district-core-swift's and tested there; what is the app's is that a `call_ringing` read
/// off THIS app's socket adapter reaches the ring as the gate decides, and that stopping
/// and signing out reach the presence the right way. The socket is the real adapter over a
/// fake task; the clock is manual, so nothing waits.
@MainActor
final class MacDesktopLiveSessionTests: XCTestCase {
    private final class FakeMinter: TelemetryTokenMinter {
        func mintTelemetryToken(workspaceId: String) async -> Result<TelemetryTokenResponse, ApiError> {
            .success(TelemetryTokenResponse(
                success: true,
                token: "a.b.c",
                expiresAt: 1_790_000_000_000 + 15 * 60 * 1000,
                wsUrl: "wss://telemetry.example.test/ws/telemetry"
            ))
        }
    }

    private final class FakePresence: PresenceAPI, @unchecked Sendable {
        private let lock = NSLock()
        private var registered: [String] = []
        private var unregistered = 0

        var registers: [String] {
            lock.withLock { registered }
        }

        var unregisters: Int {
            lock.withLock { unregistered }
        }

        func registerPresence(token: String) async -> Result<Void, ApiError> {
            lock.withLock { registered.append(token) }
            return .success(())
        }

        func unregisterPresence() async -> Result<Void, ApiError> {
            lock.withLock { unregistered += 1 }
            return .success(())
        }
    }

    private final class FakeRing: DesktopRingSink {
        private(set) var started: [(callId: String, name: String?)] = []
        private(set) var stopped: [(callId: String, reason: DesktopRingEnd)] = []
        private(set) var withdrawn: [String] = []

        func ringStarted(workspaceId: String, callId: String, workspaceName: String?) {
            started.append((callId, workspaceName))
        }

        func ringStopped(workspaceId: String, callId: String, reason: DesktopRingEnd) {
            stopped.append((callId, reason))
        }

        func ringWithdrawn(callId: String) {
            withdrawn.append(callId)
        }
    }

    private let task = FakeWebSocketTask()
    private let clock = ManualLiveClock()
    private let presence = FakePresence()
    private let ring = FakeRing()
    private let offered = Recorder<[String]>()
    private var statuses: [DesktopLiveStatus] = []

    private func start() async -> DesktopLiveSession {
        let task = task
        let offered = offered
        let transport = URLSessionTelemetryTransport(clock: clock) { _, protocols in
            offered.record(protocols)
            return OpenedWebSocket(
                task: task,
                selectedSubprotocol: TelemetryProtocol.subprotocol,
                delegate: nil,
                onClose: {}
            )
        }
        let session = DesktopLiveSession(
            workspaceId: LiveFixtures.workspaceId,
            workspaceName: "Acme",
            userId: LiveFixtures.userId,
            minter: FakeMinter(),
            presenceAPI: presence,
            installToken: "install-nonce-1",
            transport: transport,
            clock: clock,
            ring: ring
        ) { [weak self] status in
            self?.statuses.append(status)
        }
        session.start()
        await waitUntil(state: "registers=\(presence.registers) offered=\(offered.values.count)") {
            presence.registers.count == 1 && offered.values.count == 1
        }
        return session
    }

    func test_MAC_LIVE_SESSION_01_aRingForThisMemberRingsAndItsEndStopsIt() async {
        let session = await start()
        XCTAssertEqual(presence.registers, ["install-nonce-1"], "presence is registered under the install nonce")
        XCTAssertEqual(offered.values.first?.first, "distronode.telemetry.v1")
        XCTAssertEqual(offered.values.first?.last, "distronode.token.a.b.c")

        task.push(.success(.string(LiveFixtures.ringing())))
        await waitUntil { self.ring.started.count == 1 }
        XCTAssertEqual(ring.started.first?.callId, LiveFixtures.callId)
        XCTAssertEqual(ring.started.first?.name, "Acme")

        task.push(.success(.string(LiveFixtures.ended())))
        await waitUntil { self.ring.stopped.count == 1 }
        XCTAssertEqual(ring.stopped.first?.callId, LiveFixtures.callId)
        XCTAssertEqual(ring.stopped.first?.reason, .callEnded)

        await session.stop()
    }

    func test_MAC_LIVE_SESSION_02_aRingForAColleagueRingsNothing() async {
        let session = await start()

        task.push(.success(.string(LiveFixtures.ringing(userIds: ["user_somebody_else"]))))
        task.push(.success(.string(LiveFixtures.ringing(callId: "call_mine"))))
        await waitUntil { self.ring.started.count == 1 }

        XCTAssertEqual(ring.started.map(\.callId), ["call_mine"], "only the ring that names this member")
        await session.stop()
    }

    func test_MAC_LIVE_SESSION_03_stoppingWithdrawsTheRingAndSendsNothing() async {
        let session = await start()
        task.push(.success(.string(LiveFixtures.ringing())))
        await waitUntil { self.ring.started.count == 1 }

        await session.stop()

        XCTAssertEqual(ring.withdrawn, [LiveFixtures.callId])
        XCTAssertEqual(presence.unregisters, 0, "a stop sends nothing; the presence lapses on the server")
        XCTAssertEqual(task.cancelCodes, [.normalClosure], "the socket is closed")
    }

    func test_MAC_LIVE_SESSION_04_signingOutWithdrawsThePresence() async {
        let session = await start()

        await session.signOut()

        XCTAssertEqual(presence.unregisters, 1)
        XCTAssertEqual(task.cancelCodes, [.normalClosure])
    }

    func test_MAC_LIVE_SESSION_05_aClearedRingLetsTheNextCallRing() async {
        let session = await start()
        task.push(.success(.string(LiveFixtures.ringing(callId: "call_a"))))
        await waitUntil { self.ring.started.count == 1 }

        session.clearRing()
        task.push(.success(.string(LiveFixtures.ringing(callId: "call_b"))))
        await waitUntil { self.ring.started.count == 2 }

        XCTAssertEqual(ring.started.map(\.callId), ["call_a", "call_b"])
        XCTAssertEqual(ring.stopped.map(\.reason), [.cleared])
        await session.stop()
    }

    func test_MAC_LIVE_SESSION_06_statusIsLiveOnceTheSocketIsOpenAndThePresenceRegistered() async {
        let session = await start()
        await waitUntil(state: "\(statuses)") { self.statuses.contains(.connecting) || self.statuses.contains(.live) }
        // ⚠️ THE PRESENCE'S STATUS IS POLLED; advancing past one poll reads "registered".
        clock.advance(by: DesktopLiveSession.statusPollMilliseconds)
        await waitUntil(state: "\(statuses)") { self.statuses.last == .live }
        await session.stop()
    }
}
