import DistrictLive
@testable import DistrictMac
import Foundation
import XCTest

/// ⛔ THE `URLSessionWebSocketTask` ADAPTER, AGAINST DISTRICTLIVE'S CONTRACT FOR IT.
///
/// `URLSessionWebSocketTask` answers the server's pings itself and never hands them to
/// `receive()`, so a quiet, healthy socket delivers nothing, and the core's 90 s silence
/// watchdog drops it. The adapter therefore pings on its own interval and reports each pong
/// as `.heartbeat`. These tests drive the socket through a fake task and a manual clock, so
/// the interval is proven without waiting thirty seconds.
@MainActor
final class MacTelemetrySocketTests: XCTestCase {
    private let interval = URLSessionTelemetryTransport.pingIntervalMilliseconds

    private func socket(
        _ task: FakeWebSocketTask,
        clock: ManualLiveClock,
        onClose: @escaping @Sendable () -> Void = {}
    ) -> URLSessionTelemetrySocket {
        URLSessionTelemetrySocket(
            task: task,
            selectedSubprotocol: TelemetryProtocol.subprotocol,
            clock: clock,
            onClose: onClose
        )
    }

    /// The ping loop has started its wait, so an advance lands on it.
    private func pingLoopIsWaiting(_ clock: ManualLiveClock) async {
        await waitUntil(state: "sleepers=\(clock.sleeperCount)") { clock.sleeperCount == 1 }
    }

    // MARK: - Heartbeats

    func test_MAC_SOCKET_01_aPongIsReportedAsAHeartbeat() async throws {
        let task = FakeWebSocketTask()
        let clock = ManualLiveClock()
        let socket = socket(task, clock: clock)
        await pingLoopIsWaiting(clock)

        clock.advance(by: interval)

        let frame = try await socket.receive()
        XCTAssertEqual(frame, .heartbeat)
        XCTAssertEqual(task.pingCount, 1)
        await socket.close()
    }

    func test_MAC_SOCKET_02_noPingIsSentBeforeTheInterval() async {
        let task = FakeWebSocketTask()
        let clock = ManualLiveClock()
        let socket = socket(task, clock: clock)
        await pingLoopIsWaiting(clock)

        clock.advance(by: interval - 1)

        XCTAssertEqual(task.pingCount, 0, "the first ping waits the whole interval")
        await socket.close()
    }

    func test_MAC_SOCKET_03_pingsRepeatAndEveryPongIsAHeartbeat() async throws {
        let task = FakeWebSocketTask()
        let clock = ManualLiveClock()
        let socket = socket(task, clock: clock)
        for round in 1 ... 3 {
            await pingLoopIsWaiting(clock)
            clock.advance(by: interval)
            let frame = try await socket.receive()
            XCTAssertEqual(frame, .heartbeat, "round \(round)")
        }
        XCTAssertEqual(task.pingCount, 3)
        // ⛔ THE WHOLE POINT: three intervals is 90 s, the core's silence limit, and every one
        // of them produced a frame the watchdog counts as hearing from the server.
        XCTAssertEqual(interval * 3, TelemetryProtocol.silenceLimitMilliseconds)
        await socket.close()
    }

    func test_MAC_SOCKET_04_aFailedPingReportsNothing() async throws {
        let task = FakeWebSocketTask()
        task.pongError = URLError(.timedOut)
        let clock = ManualLiveClock()
        let socket = socket(task, clock: clock)
        await pingLoopIsWaiting(clock)

        clock.advance(by: interval)
        await waitUntil { task.pingCount == 1 }
        task.push(.success(.string("{}")))

        let frame = try await socket.receive()
        XCTAssertEqual(frame, .text("{}"), "a ping with no pong is not proof of life; the watchdog decides")
        await socket.close()
    }

    // MARK: - Messages and closes

    func test_MAC_SOCKET_05_textAndBinaryPassThroughInOrder() async throws {
        let task = FakeWebSocketTask()
        let socket = socket(task, clock: ManualLiveClock())
        task.push(.success(.string("one")))
        task.push(.success(.data(Data([0x7B, 0x7D]))))

        let first = try await socket.receive()
        let second = try await socket.receive()
        XCTAssertEqual(first, .text("one"))
        XCTAssertEqual(second, .binary(Data([0x7B, 0x7D])))
        await socket.close()
    }

    func test_MAC_SOCKET_06_theServersCloseCodeIsReported() async throws {
        for code in [TelemetryProtocol.closeUnauthorized, TelemetryProtocol.closeForbidden, 1001] {
            let task = FakeWebSocketTask()
            let socket = socket(task, clock: ManualLiveClock())
            task.serverClosed(code: code, reason: "bye")

            let frame = try await socket.receive()
            XCTAssertEqual(frame, .closed(code: code, reason: "bye"), "code \(code)")
            await socket.close()
        }
    }

    func test_MAC_SOCKET_07_aDelegateCloseWithNoStatusIs1005() async throws {
        let socket = socket(FakeWebSocketTask(), clock: ManualLiveClock())
        socket.peerClosed(code: 0, reason: nil)

        let frame = try await socket.receive()
        XCTAssertEqual(frame, .closed(code: 1005, reason: ""))
        await socket.close()
    }

    func test_MAC_SOCKET_08_theFirstEndWinsAndNothingFollowsIt() async throws {
        let task = FakeWebSocketTask()
        let socket = socket(task, clock: ManualLiveClock())
        socket.peerClosed(code: TelemetryProtocol.closeForbidden, reason: Data("not a member".utf8))
        task.serverClosed(code: 1000)

        let frame = try await socket.receive()
        XCTAssertEqual(frame, .closed(code: TelemetryProtocol.closeForbidden, reason: "not a member"))
        do {
            _ = try await socket.receive()
            XCTFail("nothing may follow a close")
        } catch {
            XCTAssertTrue(error is TelemetrySocketEnded)
        }
        await socket.close()
    }

    func test_MAC_SOCKET_09_aBrokenConnectionThrowsRatherThanClosing() async {
        let task = FakeWebSocketTask()
        let socket = socket(task, clock: ManualLiveClock())
        task.push(.failure(URLError(.networkConnectionLost)))

        do {
            _ = try await socket.receive()
            XCTFail("a read that broke with no close frame is a broken socket")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
        await socket.close()
    }

    func test_MAC_SOCKET_10_closeIsIdempotentAndStopsThePings() async {
        let task = FakeWebSocketTask()
        let clock = ManualLiveClock()
        let closes = Counter()
        let socket = socket(task, clock: clock) { closes.increment() }
        await pingLoopIsWaiting(clock)

        await socket.close()
        await socket.close()
        clock.advance(by: interval * 2)

        XCTAssertEqual(task.cancelCodes, [.normalClosure], "one normal closure, however often close is called")
        XCTAssertEqual(closes.value, 1, "the per-socket session is released once")
        XCTAssertEqual(task.pingCount, 0, "a closed socket pings nobody")
    }

    // MARK: - The handshake

    func test_MAC_SOCKET_11_connectOffersTheSubprotocolsExactlyAsTheCoreOrdersThem() async throws {
        let offered = Recorder<[String]>()
        let task = FakeWebSocketTask()
        let transport = URLSessionTelemetryTransport(clock: ManualLiveClock()) { _, protocols in
            offered.record(protocols)
            return OpenedWebSocket(
                task: task,
                selectedSubprotocol: TelemetryProtocol.subprotocol,
                delegate: nil,
                onClose: {}
            )
        }
        let protocols = TelemetryProtocol.offeredSubprotocols(token: "a.b.c")
        let url = try XCTUnwrap(URL(string: "wss://telemetry.example.test/ws/telemetry?workspaceId=ws_1"))

        let socket = try await transport.connect(to: url, subprotocols: protocols)

        // ⛔ THE VERSION FIRST, THE CREDENTIAL SECOND, AND NOTHING ADDED OR SORTED.
        XCTAssertEqual(offered.values, [["distronode.telemetry.v1", "distronode.token.a.b.c"]])
        XCTAssertEqual(socket.selectedSubprotocol, "distronode.telemetry.v1")
        await socket.close()
    }

    func test_MAC_SOCKET_12_aRefusedHandshakeThrowsOutOfConnect() async {
        let transport = URLSessionTelemetryTransport(clock: ManualLiveClock()) { _, _ in
            throw URLError(.badServerResponse)
        }
        do {
            _ = try await transport.connect(to: URL(fileURLWithPath: "/"), subprotocols: [])
            XCTFail("a refused handshake must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }
}

/// A thread-safe counter for callbacks a test cannot await.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

/// A thread-safe list of what a callback was handed.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Value] = []

    var values: [Value] {
        lock.withLock { recorded }
    }

    func record(_ value: Value) {
        lock.withLock { recorded.append(value) }
    }
}
