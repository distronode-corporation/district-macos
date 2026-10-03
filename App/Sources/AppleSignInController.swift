import AuthenticationServices
import DistrictAuthCore
import Foundation

/// The Sign in with Apple door (App Store Review Guideline 4.8). Ported from district-ios.
///
/// ⛔ THE NONCE IS HELD IN MEMORY FOR ONE ATTEMPT: the HASHED value goes on Apple's
/// request, the RAW value goes to the service, which hashes it and compares it with the
/// identity token's `nonce` claim.
///
/// ⚠️ A SIBLING OF ``WebAuthLoginController``: both end at the same coordinator and answer
/// the same ``LoginOutcome``.
@MainActor
final class AppleSignInController {
    private let authExchange: MacNativeAuthExchange
    private let coordinator: TokenRefreshCoordinator
    private let deviceId: String
    private let deviceName: String?

    private(set) var pending: AppleNonce?

    init(
        exchange: MacNativeAuthExchange,
        coordinator: TokenRefreshCoordinator,
        deviceId: String,
        deviceName: String?
    ) {
        authExchange = exchange
        self.coordinator = coordinator
        self.deviceId = deviceId
        self.deviceName = deviceName
    }

    /// Configure Apple's request: a fresh nonce for this attempt, and the two scopes.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.new()
        pending = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
    }

    func cancel() {
        pending = nil
    }

    /// Finish the attempt `prepare(_:)` started.
    func complete(_ result: Result<ASAuthorization, any Error>) async -> LoginOutcome {
        guard let nonce = pending else { return .noAttemptInProgress }
        pending = nil

        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return .denied("apple_unexpected_credential")
            }
            return await exchange(identityToken: credential.identityToken, nonce: nonce)
        case let .failure(error):
            return Self.outcome(for: error)
        }
    }

    func exchange(identityToken: Data?, nonce: AppleNonce) async -> LoginOutcome {
        guard let data = identityToken, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            return .denied("apple_no_identity_token")
        }

        // ⚠️ THROUGH THE MAC SHIM, which sends `platform: "macos"`. See MacPlatformShims.
        let result = await authExchange.exchangeAppleIdentityToken(
            identityToken: token,
            nonce: nonce.raw,
            deviceId: deviceId,
            deviceName: deviceName
        )
        switch result {
        case let .success(tokens):
            await coordinator.adopt(tokens, deviceId: deviceId)
            return .success
        case .rejected:
            return .rejected
        case .rateLimited:
            return .rateLimited
        case .noAccount:
            return .noAccount
        case .transportFailure:
            return .unreachable
        }
    }

    /// ⚠️ A user cancel is benign; any other authorization error carries its code so a
    /// report can name it (1000 is the missing-entitlement case on an unsigned build).
    static func outcome(for error: any Error) -> LoginOutcome {
        guard let authError = error as? ASAuthorizationError else {
            return .denied("apple_failed")
        }
        return authError.code == .canceled ? .cancelled : .denied("apple_\(authError.code.rawValue)")
    }
}
