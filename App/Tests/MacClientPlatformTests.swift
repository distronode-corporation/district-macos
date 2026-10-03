import DistrictAuthCore
import DistrictData
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import XCTest

/// ⛔ THE BYTES OF EVERY REQUEST THAT NAMES THE PLATFORM, AS THIS APP SENDS THEM.
///
/// The core's clients take a `ClientPlatform` that defaults to `.ios`, so a Mac request
/// built without `.macos` would list this Mac as an iPhone in Devices and route its
/// pushes as an iOS device. Each request is built where the app builds it and sent
/// through the core's own client over a recording transport, so a regression to the
/// default shows up here as `"ios"` in a body rather than as a wrong row in Devices.
final class MacClientPlatformTests: XCTestCase {
    private let base = URL(string: "https://www.distronode.com")!

    private static let tokenBody = """
    {"tokenType":"Bearer","accessToken":"a.b.c","accessTokenExpiresAt":1,\
    "refreshToken":"r","refreshTokenExpiresAt":2}
    """

    // MARK: - Code exchange

    func testCodeExchangeSendsMacosToTheTokenRoute() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let request = WebAuthLoginController.codeExchangeRequest(
            code: "code-1",
            verifier: "verifier-1",
            deviceId: "device-0001",
            deviceName: "Studio Mac"
        )

        let result = await AppNativeAuthClient(baseURL: base, transport: transport).exchangeCode(request)

        XCTAssertEqual(result, .success(NativeTokens(
            accessToken: "a.b.c",
            accessTokenExpiresAt: 1,
            refreshToken: "r",
            refreshTokenExpiresAt: 2
        )))
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.url.absoluteString, "https://www.distronode.com/api/auth/native/token")
        XCTAssertNil(sent.headers["Authorization"], "a sign-in exchange carries no bearer")
        let body = try transport.body()
        XCTAssertEqual(
            Set(body.keys),
            ["code", "codeVerifier", "redirectUri", "deviceId", "platform", "deviceName"]
        )
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["codeVerifier"] as? String, "verifier-1")
        XCTAssertEqual(body["redirectUri"] as? String, "districtai://auth")
    }

    func testCodeExchangeOmitsANilDeviceName() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let request = WebAuthLoginController.codeExchangeRequest(
            code: "code-1",
            verifier: "verifier-1",
            deviceId: "device-0001",
            deviceName: nil
        )

        _ = await AppNativeAuthClient(baseURL: base, transport: transport).exchangeCode(request)

        let body = try transport.body()
        XCTAssertFalse(body.keys.contains("deviceName"))
        XCTAssertEqual(body["platform"] as? String, "macos")
    }

    // MARK: - Apple

    func testAppleSignInRequestSendsFiveKeysWithMacos() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let request = AppleSignInController.signInRequest(
            identityToken: "id-token",
            nonce: "raw-nonce",
            deviceId: "device-0001",
            deviceName: "Studio Mac"
        )

        _ = await AppNativeAuthClient(baseURL: base, transport: transport).exchangeAppleIdentityToken(request)

        XCTAssertEqual(transport.requests.first?.url.path, "/api/auth/native/apple")
        let body = try transport.body()
        XCTAssertEqual(Set(body.keys), ["platform", "identityToken", "nonce", "deviceId", "deviceName"])
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["nonce"] as? String, "raw-nonce")
    }

    /// The controller's own path, not only its builder: what reaches the wire from a
    /// real `AppleSignInController` is `"macos"` and the RAW nonce.
    @MainActor
    func testAppleSignInControllerSendsMacosAndTheRawNonce() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let auth = AppNativeAuthClient(baseURL: base, transport: transport)
        let controller = AppleSignInController(
            exchange: auth,
            coordinator: TokenRefreshCoordinator(store: InMemoryTokenStore(), refreshClient: auth),
            deviceId: "device-0001",
            deviceName: nil
        )
        let nonce = AppleNonce.new()

        let outcome = await controller.exchange(identityToken: Data("id-token".utf8), nonce: nonce)

        XCTAssertEqual(outcome, .success)
        let body = try transport.body()
        XCTAssertEqual(Set(body.keys), ["platform", "identityToken", "nonce", "deviceId"])
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["nonce"] as? String, nonce.raw)
        XCTAssertNotEqual(body["nonce"] as? String, nonce.hashed, "the service hashes the raw nonce itself")
    }

    // MARK: - Push registration

    private func pushTokens(
        _ transport: RecordingTransport,
        memory: FakeMemory = FakeMemory()
    ) -> PushTokenRepository {
        let api = ApiClient(baseURL: base, transport: transport, accessToken: { "access-1" })
        return AppContainer.pushTokenRepository(client: api, memory: memory)
    }

    func testPushRegisterSendsTokenAndMacosAndNoKind() async throws {
        let transport = RecordingTransport(status: 200, body: #"{"success":true}"#)
        let memory = FakeMemory()

        let result = await pushTokens(transport, memory: memory).register(token: "abc123")

        XCTAssertEqual(result, .success(.registered))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url.absoluteString, "https://www.distronode.com/api/district/devices/register")
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-1")
        let body = try transport.body()
        XCTAssertEqual(Set(body.keys), ["token", "platform"], "no `kind`: this is the alert token")
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(memory.lastRegisteredToken(), "abc123")
    }

    func testPushRegisterSkipsATokenTheServerAlreadyAffirmed() async {
        let transport = RecordingTransport()
        let memory = FakeMemory()
        memory.rememberRegisteredToken("abc123")

        let result = await pushTokens(transport, memory: memory).register(token: "abc123")

        XCTAssertEqual(result, .success(.alreadyRegistered))
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

/// An in-memory ``PushTokenMemory``.
final class FakeMemory: PushTokenMemory, @unchecked Sendable {
    private var alert: String?
    private var voip: String?

    func lastRegisteredToken() -> String? {
        alert
    }

    func rememberRegisteredToken(_ token: String) {
        alert = token
    }

    func forgetRegisteredToken() {
        alert = nil
    }

    func lastRegisteredVoipToken() -> String? {
        voip
    }

    func rememberRegisteredVoipToken(_ token: String) {
        voip = token
    }

    func forgetRegisteredVoipToken() {
        voip = nil
    }
}
