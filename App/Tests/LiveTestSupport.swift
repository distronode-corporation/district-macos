import DistrictLive
@testable import DistrictMac
import DistrictModel
import Foundation
import XCTest

/// A `LiveClock` that never waits for real: a sleep returns when the test advances the clock
/// past its deadline, or throws when its task is cancelled.
final class ManualLiveClock: LiveClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Int64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var now: Int64
    private var sleepers: [Sleeper] = []

    init(startingAt now: Int64 = 1_790_000_000_000) {
        self.now = now
    }

    func nowMilliseconds() -> Int64 {
        lock.withLock { now }
    }

    /// How many sleeps are waiting. ⚠️ Polled by a test before it advances, so the advance
    /// lands on a sleep that exists rather than racing the task that is about to start one.
    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(milliseconds: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let due: Bool = lock.withLock {
                    if milliseconds <= 0 {
                        return true
                    }
                    sleepers.append(Sleeper(id: id, deadline: now + milliseconds, continuation: continuation))
                    return false
                }
                if due {
                    continuation.resume()
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Move time forward, waking every sleep whose deadline has passed.
    func advance(by milliseconds: Int64) {
        let woken: [Sleeper] = lock.withLock {
            now += milliseconds
            let due = sleepers.filter { $0.deadline <= now }
            sleepers.removeAll { $0.deadline <= now }
            return due
        }
        woken.forEach { $0.continuation.resume() }
    }
}

extension XCTestCase {
    /// Wait until at least `count` sleeps are waiting on `clock`, before moving it.
    @MainActor
    func waitUntilAsleep(
        _ clock: ManualLiveClock,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil(state: "sleepers=\(clock.sleeperCount)", file: file, line: line) {
            clock.sleeperCount >= count
        }
    }
}

/// A `URLSessionWebSocketTask` stand-in: messages and failures are pushed by the test, pings
/// are counted and answered at once with ``pongError``.
final class FakeWebSocketTask: WebSocketTasking, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [Result<URLSessionWebSocketTask.Message, any Error>] = []
    private var waiting: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
    private var pings = 0
    private var cancels: [URLSessionWebSocketTask.CloseCode] = []
    private var texts: [String] = []
    private var code: URLSessionWebSocketTask.CloseCode = .invalid
    private var reason: Data?

    /// What each pong reports: nil is a pong, anything else a failed ping.
    var pongError: (any Error)?

    var pingCount: Int {
        lock.withLock { pings }
    }

    /// Every text this app sent, in order.
    var sent: [String] {
        lock.withLock { texts }
    }

    var cancelCodes: [URLSessionWebSocketTask.CloseCode] {
        lock.withLock { cancels }
    }

    var closeCode: URLSessionWebSocketTask.CloseCode {
        lock.withLock { code }
    }

    var closeReason: Data? {
        lock.withLock { reason }
    }

    /// The server's close: the code `closeCode` reports from now on, and a failed read.
    func serverClosed(code: Int, reason: String = "") {
        lock.withLock {
            self.code = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .invalid
            self.reason = Data(reason.utf8)
        }
        push(.failure(URLError(.networkConnectionLost)))
    }

    func push(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
        let reader: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>? = lock.withLock {
            guard let reader = waiting else {
                queued.append(result)
                return nil
            }
            waiting = nil
            return reader
        }
        reader?.resume(with: result)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            let next: Result<URLSessionWebSocketTask.Message, any Error>? = lock.withLock {
                guard !queued.isEmpty else {
                    waiting = continuation
                    return nil
                }
                return queued.removeFirst()
            }
            if let next {
                continuation.resume(with: next)
            }
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard case let .string(text) = message else { return }
        lock.withLock { texts.append(text) }
    }

    func sendPing(pongReceiveHandler: @escaping @Sendable ((any Error)?) -> Void) {
        let error: (any Error)? = lock.withLock {
            pings += 1
            return pongError
        }
        pongReceiveHandler(error)
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.withLock { cancels.append(closeCode) }
    }
}

/// A fixture decoded from the shapes in district-core-swift's `contracts/desktop`.
enum LiveFixtures {
    static let workspaceId = "ws_desktop_contract"
    static let callId = "call_desktop_contract"
    static let userId = "user_desktop_contract"

    static func envelope(_ json: String) throws -> TelemetryEnvelope {
        try JSONDecoder().decode(TelemetryEnvelope.self, from: Data(json.utf8))
    }

    static func ringing(callId: String = callId, userIds: [String] = [userId]) -> String {
        let ids = userIds.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"workspaceId":"\(workspaceId)","callId":"\(callId)","eventType":"call_ringing",\
        "data":{"callId":"\(callId)","userIds":[\(ids)]},"timestamp":"2026-09-26T14:30:00.000Z"}
        """
    }

    static func ended(callId: String = callId) -> String {
        """
        {"workspaceId":"\(workspaceId)","callId":"\(callId)","eventType":"call_ended",\
        "data":{"id":"\(callId)","status":"completed"},"timestamp":"2026-09-26T14:30:00.000Z"}
        """
    }
}
