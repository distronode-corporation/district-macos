import DistrictAuthCore
import DistrictData
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import XCTest

/// ⛔ THE BYTES AND THE STATUS MAPS OF EVERY REQUEST THAT NAMES THE PLATFORM.
///
/// The shim exists so a Mac is never listed as an iPhone; these tests are what make that
/// a red test rather than a wrong row in Devices. They are deleted with the shim when the
/// core takes a platform parameter (Wave 2).
final class MacPlatformShimsTests: XCTestCase {
    private let base = URL(string: "https://www.distronode.com")!

    private static let tokenBody = """
    {"tokenType":"Bearer","accessToken":"a.b.c","accessTokenExpiresAt":1,\
    "refreshToken":"r","refreshTokenExpiresAt":2}
    """

    private func codeRequest(deviceName: String? = "Studio Mac") -> CodeExchangeRequest {
        CodeExchangeRequest(
            code: "code-1",
            codeVerifier: "verifier-1",
            redirectUri: "districtai://auth",
            deviceId: "device-0001",
            deviceName: deviceName
        )
    }

    // MARK: - Code exchange

    func testCodeExchangeSendsMacosToTheTokenRoute() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let exchange = MacNativeAuthExchange(baseURL: base, transport: transport)

        let result = await exchange.exchangeCode(codeRequest())

        XCTAssertEqual(result, .success(NativeTokens(
            accessToken: "a.b.c",
            accessTokenExpiresAt: 1,
            refreshToken: "r",
            refreshTokenExpiresAt: 2
        )))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url.absoluteString, "https://www.distronode.com/api/auth/native/token")
        XCTAssertNil(request.headers["Authorization"], "a sign-in exchange carries no bearer")
        let body = try transport.body()
        XCTAssertEqual(
            Set(body.keys),
            ["code", "codeVerifier", "redirectUri", "deviceId", "platform", "deviceName"]
        )
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["redirectUri"] as? String, "districtai://auth")
    }

    func testCodeExchangeOmitsANilDeviceName() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        _ = await MacNativeAuthExchange(baseURL: base, transport: transport).exchangeCode(codeRequest(deviceName: nil))
        XCTAssertFalse(try transport.body().keys.contains("deviceName"))
    }

    func testCodeExchangeStatusMapMatchesTheCore() async {
        let cases: [(Int, CodeExchangeResult<NativeTokens>)] = [
            (400, .rejected),
            (429, .rateLimited),
            (403, .transportFailure),
            (500, .transportFailure),
            (200, .transportFailure), // an empty 200 is unreadable, not a refusal
        ]
        for (status, expected) in cases {
            let transport = RecordingTransport(status: status)
            let result = await MacNativeAuthExchange(baseURL: base, transport: transport).exchangeCode(codeRequest())
            XCTAssertEqual(result, expected, "status \(status)")
        }
    }

    func testCodeExchangeTransportErrorIsTransportFailure() async {
        let transport = RecordingTransport([.failure(URLError(.notConnectedToInternet))])
        let result = await MacNativeAuthExchange(baseURL: base, transport: transport).exchangeCode(codeRequest())
        XCTAssertEqual(result, .transportFailure)
    }

    // MARK: - Apple

    func testAppleExchangeSendsFiveKeysWithMacos() async throws {
        let transport = RecordingTransport(status: 200, body: Self.tokenBody)
        let exchange = MacNativeAuthExchange(baseURL: base, transport: transport)

        _ = await exchange.exchangeAppleIdentityToken(
            identityToken: "id-token",
            nonce: "raw-nonce",
            deviceId: "device-0001",
            deviceName: "Studio Mac"
        )

        XCTAssertEqual(transport.requests.first?.url.path, "/api/auth/native/apple")
        let body = try transport.body()
        XCTAssertEqual(Set(body.keys), ["platform", "identityToken", "nonce", "deviceId", "deviceName"])
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["nonce"] as? String, "raw-nonce")
    }

    func testAppleExchangeMaps403ToNoAccount() async {
        let transport = RecordingTransport(status: 403, body: #"{"error":"no_account"}"#)
        let result = await MacNativeAuthExchange(baseURL: base, transport: transport).exchangeAppleIdentityToken(
            identityToken: "t",
            nonce: "n",
            deviceId: "device-0001",
            deviceName: nil
        )
        XCTAssertEqual(result, .noAccount)
    }

    // MARK: - Push registration

    private func registration(
        _ transport: RecordingTransport,
        bearer: String? = "access-1",
        memory: FakeMemory = FakeMemory()
    ) -> MacPushRegistration {
        MacPushRegistration(baseURL: base, transport: transport, accessToken: { bearer }, memory: memory)
    }

    func testPushRegisterSendsTokenAndMacosAndNoKind() async throws {
        let transport = RecordingTransport(status: 200, body: #"{"success":true}"#)
        let memory = FakeMemory()

        let result = await registration(transport, memory: memory).register(token: "abc123")

        XCTAssertEqual(result, .success(.registered))
        let request = try XCTUnwrap(transport.requests.first)
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

        let result = await registration(transport, memory: memory).register(token: "abc123")

        XCTAssertEqual(result, .success(.alreadyRegistered))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPushRegisterSendsNothingWithoutABearerOrAToken() async {
        let transport = RecordingTransport()
        let unauthenticated = await registration(transport, bearer: nil).register(token: "abc123")
        let empty = await registration(transport).register(token: "")
        XCTAssertEqual(unauthenticated, .failure(.http(status: 401, message: nil)))
        XCTAssertEqual(empty, .success(.noTokenToRegister))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPushRegisterRefusalIsNotRemembered() async {
        let transport = RecordingTransport(status: 400, body: #"{"error":"Invalid request"}"#)
        let memory = FakeMemory()

        let result = await registration(transport, memory: memory).register(token: "abc123")

        guard case .failure(.http(status: 400, _)) = result else {
            return XCTFail("expected an HTTP 400 failure, got \(result)")
        }
        XCTAssertNil(memory.lastRegisteredToken())
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
