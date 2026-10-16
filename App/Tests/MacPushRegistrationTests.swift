import DistrictAuthCore
import DistrictData
@testable import DistrictMac
import DistrictNetwork
import Foundation
import XCTest

/// The quit app's ring is the server's APNs alert, so every signed-in session must leave
/// this Mac with a live alert row (3.0.1).
///
/// ⛔ THE FIRST TWO ARE THE 3.0.0 DEFECT: a second account signed in on the same launch
/// never registered (`hasAskedThisLaunch`), after the sign-out had deleted the rows.
@MainActor
final class MacPushRegistrationTests: XCTestCase {
    private static let token = String(repeating: "ab", count: 32)

    /// ⛔ A SIGN-IN AFTER A SIGN-OUT, ON THE SAME LAUNCH, ASKS APNS AGAIN AND SENDS THE TOKEN
    /// AGAIN, even though it is the one the server affirmed for the account before.
    func test_MAC_PUSH_01_aSecondSignInOnOneLaunchRegistersAgain() async {
        let harness = await PushHarness()

        harness.registrar.enableAfterSignIn()
        await waitUntil(state: harness.transport.summary()) { harness.transport.registers.count == 1 }
        harness.registrar.forget()
        harness.registrar.enableAfterSignIn()
        await waitUntil(state: harness.transport.summary()) { harness.transport.registers.count == 2 }

        XCTAssertEqual(
            harness.apns.calls,
            ["requestAuthorization", "register", "unregister", "requestAuthorization", "register"]
        )
        XCTAssertEqual(harness.transport.registers, [Self.token, Self.token])
        XCTAssertEqual(harness.registrar.registration, .registered)
    }

    /// ⛔ EVERY LAUNCH SENDS ITS REGISTER: a token remembered from an earlier launch does not
    /// skip it, because the server may have retired or deleted that row since.
    func test_MAC_PUSH_02_aRememberedTokenIsSentAgainOnTheNextLaunch() async {
        let harness = await PushHarness()
        harness.memory.rememberRegisteredToken(Self.token)

        harness.registrar.enableAfterSignIn()
        await waitUntil(state: harness.transport.summary()) { harness.transport.registers.count == 1 }

        XCTAssertEqual(harness.transport.registers, [Self.token])
    }

    /// ⚠️ ONCE PER SIGNED-IN SESSION: the gate reaching signed-in again ("Try again") does not
    /// ask twice.
    func test_MAC_PUSH_03_oneSessionAsksOnce() async {
        let harness = await PushHarness()

        harness.registrar.enableAfterSignIn()
        harness.registrar.enableAfterSignIn()
        await waitUntil(state: harness.transport.summary()) { harness.transport.registers.count == 1 }

        XCTAssertEqual(harness.apns.calls, ["requestAuthorization", "register"])
    }

    /// ⛔ A SESSION THAT ENDS WITH NO CREDENTIAL LEFT STILL WITHDRAWS WHAT IT CAN: this Mac
    /// stops taking remote notifications, and nothing is sent to the server.
    func test_MAC_PUSH_04_aServerEndedSessionStopsRemoteNotifications() async {
        let harness = await PushHarness(signedIn: false)
        let session = SessionModel(container: harness.container, push: harness.registrar)

        await session.refreshPhase()

        XCTAssertEqual(session.phase, .signedOut(""))
        XCTAssertEqual(harness.apns.calls, ["unregister"])
        XCTAssertEqual(harness.transport.paths, [])
    }

    /// ⛔ THE SESSION TURNS PUSH ON, WITH NO WINDOW: a launch at login must register too.
    func test_MAC_PUSH_05_theSessionRegistersWithNoView() async {
        let harness = await PushHarness()
        let session = SessionModel(container: harness.container, push: harness.registrar)

        await session.refreshPhase()
        await waitUntil(state: harness.transport.summary()) { harness.transport.registers.count == 1 }

        XCTAssertEqual(session.phase, .signedIn)
        XCTAssertEqual(harness.transport.registers, [Self.token])
    }

    /// A refused permission registers nothing, and says so.
    func test_MAC_PUSH_06_aRefusedPermissionRegistersNothing() async {
        let harness = await PushHarness()
        harness.apns.granted = false

        harness.registrar.enableAfterSignIn()
        await waitUntil { harness.registrar.authorization == .denied }

        XCTAssertEqual(harness.apns.calls, ["requestAuthorization"])
        XCTAssertEqual(harness.transport.registers, [])
    }
}

// MARK: - Harness

@MainActor
private struct PushHarness {
    let transport = DeviceRegisterTransport()
    let memory = InMemoryPushTokenMemory()
    let apns = RecordingPushSystem()
    let container: AppContainer
    let registrar: PushRegistrar

    init(signedIn: Bool = true) async {
        container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: InMemoryTokenStore(),
            pushTokenMemory: memory
        )
        if signedIn {
            let hour: Int64 = 3_600_000
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            await container.coordinator.adopt(
                NativeTokens(
                    accessToken: "access",
                    accessTokenExpiresAt: now + hour,
                    refreshToken: "refresh",
                    refreshTokenExpiresAt: now + 24 * hour
                ),
                deviceId: container.deviceId
            )
        }
        let registrar = PushRegistrar(container: container, system: apns.system)
        apns.token = String(repeating: "ab", count: 32)
        apns.registrar = registrar
        self.registrar = registrar
    }
}

/// The OS's push calls, recorded. Its `register` hands the token straight back, as APNs
/// does through the app delegate.
@MainActor
final class RecordingPushSystem {
    private(set) var calls: [String] = []
    var granted = true
    var token: String?
    weak var registrar: PushRegistrar?

    var system: PushSystem {
        PushSystem(
            requestAuthorization: { [self] in
                calls.append("requestAuthorization")
                return granted
            },
            register: { [self] in
                calls.append("register")
                if let token {
                    registrar?.deviceTokenReceived(token)
                }
            },
            unregister: { [self] in calls.append("unregister") }
        )
    }
}

/// ``PushTokenMemory`` kept in memory, so a test never writes the app's defaults.
final class InMemoryPushTokenMemory: PushTokenMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var alert: String?
    private var voip: String?

    func lastRegisteredToken() -> String? {
        lock.withLock { alert }
    }

    func rememberRegisteredToken(_ token: String) {
        lock.withLock { alert = token }
    }

    func forgetRegisteredToken() {
        lock.withLock { alert = nil }
    }

    func lastRegisteredVoipToken() -> String? {
        lock.withLock { voip }
    }

    func rememberRegisteredVoipToken(_ token: String) {
        lock.withLock { voip = token }
    }

    func forgetRegisteredVoipToken() {
        lock.withLock { voip = nil }
    }
}

/// Answers the devices routes with `{success:true}` and records the tokens registered.
private final class DeviceRegisterTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var recordedTokens: [String] = []

    var paths: [String] {
        lock.withLock { recordedPaths }
    }

    var registers: [String] {
        lock.withLock { recordedTokens }
    }

    func summary() -> String {
        "paths: \(paths)"
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        let path = request.url.path
        lock.withLock { recordedPaths.append(path) }
        if path.hasSuffix("/devices/register") {
            let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let token = body?["token"] as? String ?? ""
            lock.withLock { recordedTokens.append(token) }
            return Self.success
        }
        if path.hasSuffix("/devices/unregister") {
            return Self.success
        }
        return HTTPResponse(statusCode: 404, headers: [:], body: Data(#"{"error":"not_found"}"#.utf8))
    }

    private static let success = HTTPResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"success":true}"#.utf8)
    )
}

extension PushSystem {
    /// For a test that is not about push: asks nothing and registers nothing.
    static let silent = PushSystem(requestAuthorization: { false }, register: {}, unregister: {})
}
