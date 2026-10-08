import DistrictAuthCore
@testable import DistrictMac
import DistrictNetwork
import Foundation
import XCTest

/// The authenticator-code step after Sign in with Apple, on the Mac: the Apple route's
/// `401 mfa_required`, ``AppleSignInController/submitCode(_:for:now:)`` with `macos`, and
/// what the session gate does with each answer.
///
/// ⚠️ THE BODIES ARE THE SERVICE'S RECORDED FIXTURES, INLINED
/// (`district-native-apple-mfa-required.json`, `district-native-mfa.json`); the strict
/// copies live in district-core-swift.
@MainActor
final class MacAppleMfaStepTests: XCTestCase {
    private struct Row {
        let status: Int
        let body: String
        let expected: MfaCodeOutcome

        init(_ status: Int, _ body: String, _ expected: MfaCodeOutcome) {
            self.status = status
            self.body = body
            self.expected = expected
        }
    }

    private let base = URL(string: "https://www.distronode.com")!

    private static let mfaRequiredBody = """
    {"error":"mfa_required","code":"MFA_REQUIRED","message":"Enter the code from your authenticator app.",\
    "mfaTicket":"q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s","mfaTicketExpiresAt":"2026-08-15T14:35:00.000Z"}
    """

    private static let grantBody = """
    {"tokenType":"Bearer","accessToken":"access-contract-token","accessTokenExpiresAt":1786804800000,\
    "refreshToken":"refresh-contract-token","refreshTokenExpiresAt":1791988200000}
    """

    private static let ticket = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"
    private static let expiresAt = Date(timeIntervalSince1970: 1_786_804_500)
    private static let challenge = NativeMfaChallenge(ticket: ticket, expiresAt: expiresAt)
    private static let beforeExpiry = expiresAt.addingTimeInterval(-60)

    private func makeController(
        _ transport: RecordingTransport,
        store: InMemoryTokenStore = InMemoryTokenStore()
    ) -> AppleSignInController {
        let auth = AppNativeAuthClient(baseURL: base, transport: transport)
        return AppleSignInController(
            exchange: auth,
            coordinator: TokenRefreshCoordinator(store: store, refreshClient: auth),
            deviceId: "device-0001",
            deviceName: "Studio Mac"
        )
    }

    /// ⛔ THE RECORDED 401 OPENS THE CODE STEP AND ADOPTS NOTHING. Before the step existed
    /// this read as "could not reach District AI".
    func testTheMfaRequiredAnswerOpensTheCodeStepWithoutSigningIn() async throws {
        let store = InMemoryTokenStore()
        let controller = makeController(RecordingTransport(status: 401, body: Self.mfaRequiredBody), store: store)

        let outcome = await controller.exchange(identityToken: Data("id-token".utf8), nonce: AppleNonce.new())

        XCTAssertEqual(outcome, .mfaRequired(Self.challenge))
        let persisted = try await store.read()
        XCTAssertNil(persisted)
    }

    /// ⛔ `macos`, THE APPLE LEG'S PLATFORM: the ticket was minted for it, and any other
    /// value is refused. Built where the app builds it, sent through the core's client.
    func testTheCodeStepSendsMacosAndTheAppleLegsDevice() async throws {
        let transport = RecordingTransport(status: 200, body: Self.grantBody)
        let store = InMemoryTokenStore()
        let controller = makeController(transport, store: store)

        let outcome = await controller.submitCode("123456", for: Self.challenge, now: Self.beforeExpiry)

        XCTAssertEqual(outcome, .success)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url.absoluteString, "https://www.distronode.com/api/auth/native/mfa")
        XCTAssertNil(sent.headers["Authorization"])
        let body = try transport.body()
        XCTAssertEqual(Set(body.keys), ["mfaTicket", "code", "deviceId", "deviceName", "platform"])
        XCTAssertEqual(body["platform"] as? String, "macos")
        XCTAssertEqual(body["deviceId"] as? String, "device-0001")
        XCTAssertEqual(body["mfaTicket"] as? String, Self.ticket)
        let persisted = try await store.read()
        XCTAssertEqual(persisted?.refreshToken, "refresh-contract-token")
    }

    func testTheRequestBuilderIsMacos() {
        let request = AppleSignInController.mfaRequest(
            challenge: Self.challenge,
            code: "ABCDE-FGHJK",
            deviceId: "device-0001",
            deviceName: nil
        )

        XCTAssertEqual(request.platform, "macos")
        XCTAssertNil(request.deviceName)
    }

    /// ⛔ A WRONG CODE AND A DEAD TICKET MUST NOT CROSS.
    func testTheCodeStatusMap() async throws {
        let rows = [
            Row(401, #"{"error":"invalid_credentials","code":"invalid_credentials"}"#, .wrongCode),
            Row(400, #"{"error":"invalid_grant","code":"invalid_credentials"}"#, .expired),
            Row(429, #"{"error":"Too many requests. Please try again shortly."}"#, .rateLimited),
            Row(503, "", .unreachable),
        ]

        for row in rows {
            let store = InMemoryTokenStore()
            let controller = makeController(RecordingTransport(status: row.status, body: row.body), store: store)
            let outcome = await controller.submitCode("123456", for: Self.challenge, now: Self.beforeExpiry)
            XCTAssertEqual(outcome, row.expected, "HTTP \(row.status)")
            let persisted = try await store.read()
            XCTAssertNil(persisted, "HTTP \(row.status) adopts nothing")
        }
    }

    /// ⚠️ A TICKET THAT HAS CERTAINLY EXPIRED IS NOT SENT (an empty transport throws on any
    /// request, so a send would read as `unreachable`).
    func testAnExpiredTicketIsNotSent() async {
        let transport = RecordingTransport()
        let controller = makeController(transport)

        let outcome = await controller.submitCode("123456", for: Self.challenge, now: Self.expiresAt)

        XCTAssertEqual(outcome, .expired)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    /// ⛔ ONLY `expired` CLOSES THE SHEET WITHOUT SIGNING IN.
    func testEachOutcomesReaction() {
        XCTAssertEqual(MfaCodeOutcome.success.reaction, .signedIn)
        XCTAssertEqual(MfaCodeOutcome.wrongCode.reaction, .stayOpen(MfaCopy.wrongCode))
        XCTAssertEqual(MfaCodeOutcome.expired.reaction, .startOver(MfaCopy.expired))
        XCTAssertEqual(MfaCodeOutcome.rateLimited.reaction, .stayOpen(SessionCopy.tooManyAttempts))
        XCTAssertEqual(MfaCodeOutcome.unreachable.reaction, .stayOpen(SessionCopy.unreachable))
    }

    /// ⚠️ THE MAC SAYS WHAT THE iPHONE SAYS.
    func testTheCopyMatchesTheIosApp() {
        XCTAssertEqual(MfaCopy.expired, "That sign-in timed out. Sign in with Apple again.")
        XCTAssertEqual(MfaCopy.wrongCode, "That code did not work. Check the code and try again.")
    }
}
