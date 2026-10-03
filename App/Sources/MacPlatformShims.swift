import DistrictAuthCore
import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation

// ⛔ EVERY REQUEST BODY THAT NAMES THE CLIENT PLATFORM, BUILT HERE AS `"macos"`, AND
// NOWHERE ELSE IN THE APP.
//
// The shared core (district-core-swift 1.0) hard-codes `"ios"` at the sites that send a
// platform: `CodeExchangeRequest.platform`, `AppleNativeSignInRequest.platform` and
// `DistrictEndpoints.registerPushToken`'s body. Sending `"ios"` from a Mac would list it
// as an iPhone in Devices and route its pushes as an iOS device. Wave 2 of the macOS plan
// adds a `ClientPlatform` parameter to the core (core 1.1.0); when the Mac bumps to it,
// this file is DELETED and its callers use the core's own clients with `.macos`.
//
// ⚠️ THE STATUS MAPS BELOW ARE COPIES OF THE CORE'S, READ OFF `NativeAuthClient` AND
// `PushTokenRepository` AT district-core-swift main 7f99ac1. They are the price of the
// shim, and the reason it is one file: when the core's maps change before Wave 2 lands,
// this is the only place to follow them. `MacPlatformShimsTests` pins the bytes and the
// maps so a drift here shows up as a red test rather than as a Mac listed as an iPhone.

/// The platform string for this client. The service's three routes accept it as of
/// monorepo ce3d3b6f1 (`devices/register` since 4161273c4); that their deployed
/// versions do is a fact to check at the first signed sign-in, not one this file knows.
enum MacClientPlatform {
    static let wire = "macos"
}

/// The two sign-in exchanges, with `platform: "macos"`.
///
/// ⛔ NO BEARER, for the reason the core's `NativeAuthClient` gives: acquiring a token is
/// what these calls are FOR. Refresh and revoke carry no platform and still go through
/// the core's client (``AppNativeAuthClient``).
struct MacNativeAuthExchange: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport

    init(baseURL: URL, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// The PKCE code exchange: `POST /api/auth/native/token`.
    ///
    /// ⚠️ camelCase body keys (`codeVerifier`, `redirectUri`), unlike the authorize leg's
    /// snake_case query. `deviceName` is omitted rather than sent empty when nil.
    func exchangeCode(_ request: CodeExchangeRequest) async -> CodeExchangeResult<NativeTokens> {
        let body = CodeExchangeBody(
            code: request.code,
            codeVerifier: request.codeVerifier,
            redirectUri: request.redirectUri,
            deviceId: request.deviceId,
            platform: MacClientPlatform.wire,
            deviceName: request.deviceName
        )
        guard let response = await post(["api", "auth", "native", "token"], body) else {
            return .transportFailure
        }
        switch response.statusCode {
        case 200:
            guard let tokens = Self.tokens(from: response) else { return .transportFailure }
            return .success(tokens)
        case 400:
            return .rejected
        case 429:
            return .rateLimited
        default:
            return .transportFailure
        }
    }

    /// The Apple identity-token exchange: `POST /api/auth/native/apple`.
    ///
    /// ⛔ FIVE KEYS AND NO `authorizationCode`; the RAW nonce, never the hashed one. 403 is
    /// `noAccount` (sign-in never creates an account), keyed on the status alone.
    func exchangeAppleIdentityToken(
        identityToken: String,
        nonce: String,
        deviceId: String,
        deviceName: String?
    ) async -> CodeExchangeResult<NativeTokens> {
        let body = AppleBody(
            platform: MacClientPlatform.wire,
            identityToken: identityToken,
            nonce: nonce,
            deviceId: deviceId,
            deviceName: deviceName
        )
        guard let response = await post(["api", "auth", "native", "apple"], body) else {
            return .transportFailure
        }
        switch response.statusCode {
        case 200:
            guard let tokens = Self.tokens(from: response) else { return .transportFailure }
            return .success(tokens)
        case 400:
            return .rejected
        case 403:
            return .noAccount
        case 429:
            return .rateLimited
        default:
            return .transportFailure
        }
    }

    // MARK: - Wire

    struct CodeExchangeBody: Encodable, Equatable {
        let code: String
        let codeVerifier: String
        let redirectUri: String
        let deviceId: String
        let platform: String
        /// ⚠️ Synthesised `Encodable` writes an Optional with `encodeIfPresent`, so a nil
        /// name is an absent key, not `null`.
        let deviceName: String?
    }

    struct AppleBody: Encodable, Equatable {
        let platform: String
        let identityToken: String
        let nonce: String
        let deviceId: String
        let deviceName: String?
    }

    private func post(_ segments: [String], _ body: some Encodable) async -> HTTPResponse? {
        // ⚠️ Segment by segment, as the core does: it absorbs a trailing `/` on the base.
        let url = segments.reduce(baseURL) { $0.appendingPathComponent($1) }
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Accept": "application/json",
            ],
            body: data
        )
        return try? await transport.send(request, followRedirects: true)
    }

    /// ⚠️ Lenient on purpose: an unknown key added server-side is ignored rather than
    /// breaking sign-in on every installed build.
    private static func tokens(from response: HTTPResponse) -> NativeTokens? {
        guard let body = response.body else { return nil }
        return try? JSONDecoder().decode(NativeTokenResponse.self, from: body).tokens
    }
}

/// This installation's ALERT push registration, with `platform: "macos"` and no `kind`.
///
/// ⛔ NO `kind`. The route's default is the alert token, which is the only push this Mac
/// registers in this wave. Presence ringing (`kind: "desktop"`) arrives with the
/// telemetry socket in Wave 6, through the core.
///
/// ⚠️ THE SAME "REMEMBERED TOKEN" RULE AS THE CORE'S `PushTokenRepository`: an unchanged
/// token the server already affirmed is not re-sent (the route allows 20 a minute per
/// account), and the memory is cleared on every sign-out by
/// `PushTokenRepository.forgetRegistration()`, which the Mac still uses, together with
/// its `unregister()`, because neither names a platform.
struct MacPushRegistration: Sendable {
    typealias AccessToken = @Sendable () async -> String?

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let accessToken: AccessToken
    private let memory: any PushTokenMemory

    init(baseURL: URL, transport: any HTTPTransport, accessToken: @escaping AccessToken, memory: any PushTokenMemory) {
        self.baseURL = baseURL
        self.transport = transport
        self.accessToken = accessToken
        self.memory = memory
    }

    struct Body: Encodable, Equatable {
        let token: String
        let platform: String
    }

    func register(token: String) async -> Result<PushRegistrationOutcome, ApiError> {
        guard !token.isEmpty else { return .success(.noTokenToRegister) }
        if memory.lastRegisteredToken() == token {
            return .success(.alreadyRegistered)
        }
        // ⛔ NO BEARER, NO REQUEST: an unauthenticated register would only spend the rate
        // limit to be told 401. The same local 401 the core's `ApiClient` answers.
        guard let bearer = await accessToken() else {
            return .failure(.http(status: 401, message: nil))
        }
        let url = ["api", "district", "devices", "register"].reduce(baseURL) { $0.appendingPathComponent($1) }
        guard let data = try? JSONEncoder().encode(Body(token: token, platform: MacClientPlatform.wire)) else {
            return .failure(.decoding("The push registration could not be encoded."))
        }
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Accept": "application/json",
                "Authorization": "Bearer \(bearer)",
            ],
            body: data
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request, followRedirects: true)
        } catch {
            return .failure(.transport(String(describing: error)))
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            // The core's own normaliser, so the error text matches every other refusal.
            return .failure(ApiErrorNormalizer.apiError(statusCode: response.statusCode, body: response.body))
        }
        memory.rememberRegisteredToken(token)
        return .success(.registered)
    }
}
