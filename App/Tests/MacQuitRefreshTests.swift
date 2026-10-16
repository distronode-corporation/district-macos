import DistrictAuthCore
@testable import DistrictMac
import DistrictNetwork
import Foundation
import XCTest

/// A quit lets a token refresh already on the wire reach the store (3.0.1).
///
/// ⛔ THE 3.0.0 DEFECT: the server rotated the session, the app quit before the successor
/// was written, and the next launch could only say "Your session ended unexpectedly".
@MainActor
final class MacQuitRefreshTests: XCTestCase {
    /// ⛔ THE QUIT WAITS FOR THE ROTATED TOKEN TO BE STORED.
    func test_MAC_QUIT_01_aQuitWaitsForTheRotatedTokenToBeStored() async {
        let harness = await QuitHarness()
        let refresh = Task { await harness.container.coordinator.accessToken() }
        await waitUntil { harness.transport.refreshes == 1 }

        let quit = Task { await harness.session.finishForQuit(within: 30) }
        try? await Task.sleep(for: .milliseconds(200))
        let stillSpent = await harness.store.storedRefreshToken()
        XCTAssertEqual(stillSpent, "refresh-1", "nothing is stored while the server has not answered")

        harness.transport.release()
        await quit.value

        let stored = await harness.store.storedRefreshToken()
        XCTAssertEqual(stored, "refresh-2", "the quit may go only once the successor is stored")
        let marker = try? await harness.store.pendingRefreshToken()
        XCTAssertNil(marker)
        _ = await refresh.value
    }

    /// ⚠️ BOUNDED: a server that never answers does not hold the quit.
    func test_MAC_QUIT_02_aQuitDoesNotWaitPastItsDeadline() async {
        let harness = await QuitHarness()
        let refresh = Task { await harness.container.coordinator.accessToken() }
        await waitUntil { harness.transport.refreshes == 1 }

        let started = Date()
        await harness.session.finishForQuit(within: 0.2)

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        harness.transport.release()
        _ = await refresh.value
    }

    /// ⚠️ A QUIT STARTS NO REFRESH OF ITS OWN.
    func test_MAC_QUIT_03_aQuitWithNothingInFlightSendsNothing() async {
        let harness = await QuitHarness()

        await harness.session.finishForQuit(within: 30)

        XCTAssertEqual(harness.transport.refreshes, 0)
    }
}

// MARK: - Harness

/// A session whose access token has run out, so the next request refreshes, against a
/// server whose refresh answer is held until the test releases it.
@MainActor
private struct QuitHarness {
    let transport = HeldRefreshTransport()
    let store = InMemoryTokenStore()
    let container: AppContainer
    let session: SessionModel

    init() async {
        container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: store,
            pushTokenMemory: InMemoryPushTokenMemory()
        )
        // ⚠️ ADOPTED RATHER THAN SEEDED, through the container's own store, with an access
        // token that has already run out: the next request refreshes `refresh-1`.
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        await container.coordinator.adopt(
            NativeTokens(
                accessToken: "access-1",
                accessTokenExpiresAt: now - 1,
                refreshToken: "refresh-1",
                refreshTokenExpiresAt: now + 86_400_000
            ),
            deviceId: container.deviceId
        )
        session = SessionModel(container: container, push: PushRegistrar(container: container, system: .silent))
    }
}

extension InMemoryTokenStore {
    /// The refresh token on disk, or nil.
    func storedRefreshToken() async -> String? {
        try? await read()?.refreshToken
    }
}

/// Holds `auth/native/refresh` until ``release()``, then answers with the successor.
private final class HeldRefreshTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var refreshes: Int {
        lock.withLock { count }
    }

    func release() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            released = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in waiting {
            waiter.resume()
        }
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        guard request.url.path.hasSuffix("/auth/native/refresh") else {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(#"{"error":"not_found"}"#.utf8))
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = lock.withLock {
                count += 1
                if released {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let body = #"{"tokenType":"Bearer","accessToken":"access-2","accessTokenExpiresAt":\#(now + 600_000),"#
            + #""refreshToken":"refresh-2","refreshTokenExpiresAt":\#(now + 86_400_000)}"#
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}
