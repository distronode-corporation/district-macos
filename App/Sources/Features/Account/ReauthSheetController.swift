import AppKit
import AuthenticationServices
import DistrictAuthCore
import DistrictData
import DistrictModel
import Foundation

/// The providers a fresh re-authentication can go through, by their wire names.
///
/// ⛔ THE SERVICE'S `LINKABLE_PROVIDERS`, NOT A GUESS ABOUT THIS ACCOUNT. The app does not know
/// which providers an account has linked, so it offers all three and the service decides: a
/// provider the account does not use is refused on the sheet itself.
enum ReauthProvider: String, CaseIterable, Sendable {
    case google
    case microsoft = "azure-ad"
    case apple

    /// ⛔ PROPER NOUNS, THE SAME IN BOTH LANGUAGES (the service's `PROVIDER_LABEL`).
    var displayName: String {
        switch self {
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .apple: "Apple"
        }
    }
}

/// How one fresh sign-in at a provider ended.
enum SSOReauthOutcome: Equatable, Sendable {
    /// The service holds a proof for this installation, for this many seconds.
    case proved(expiresInSeconds: Int)
    /// The person closed the sign-in window. ⚠️ Benign: nothing is shown for it.
    case cancelled
    /// ⛔ The callback's `state` was not the one this attempt made. Never exchanged.
    case stateMismatch
    /// The window came back without a code.
    case noCode
    /// The window could not be presented.
    case couldNotOpen
    /// The service refused the code, or could not be reached.
    case refused(ApiError)
}

/// The SSO leg of a fresh re-authentication before a sensitive action (account deletion).
/// Ported from district-ios.
///
/// ⛔ THE SAME TWO LEGS AS SIGN-IN, WITH THE SAME GUARDS. Leg one is
/// `ASWebAuthenticationSession` on `/auth/native/reauth`, which relays to the provider with a
/// forced fresh sign-in and hands back a one-time code; leg two spends that code with this
/// attempt's PKCE verifier (`POST /api/auth/native/reauth/sso`). `state` is checked before the
/// code is spent, and the verifier lives in memory only. See ``WebAuthLoginController``.
///
/// ⛔ NOT EPHEMERAL. The window's `reauth/authorize` reads the browser's own session cookie,
/// the one the fresh provider sign-in just stamped; an ephemeral session has none.
///
/// ⚠️ THE SERVICE BINDS THE CODE FOUR WAYS (this account, this installation by
/// `SHA-256(deviceId)`, this action, and the PKCE verifier), so the app adds no check of its own
/// beyond `state`.
@MainActor
final class ReauthSheetController {
    typealias Presenter = @MainActor (URL) async -> Result<URL, any Error>

    /// ⚠️ A PAGE, NOT AN API ROUTE, like the sign-in window's `/auth/native`.
    static let sheetPath = "/auth/native/reauth"

    private let baseURL: URL
    private let repository: NativeReauthRepository
    private let deviceId: String
    private let presenter: Presenter

    /// In flight, and single-slot: a second attempt abandons the first.
    private var pending: PKCEChallenge?

    init(baseURL: URL, repository: NativeReauthRepository, deviceId: String, presenter: Presenter? = nil) {
        self.baseURL = baseURL
        self.repository = repository
        self.deviceId = deviceId
        self.presenter = presenter ?? WebAuthSheet.present
    }

    func reauthenticate(provider: ReauthProvider, action: NativeReauthAction) async -> SSOReauthOutcome {
        let challenge = PKCE.newChallenge()
        pending = challenge
        guard let url = Self.sheetURL(
            baseURL: baseURL,
            challenge: challenge,
            provider: provider,
            deviceHash: AppleNonce.sha256Hex(deviceId),
            action: action
        ) else {
            pending = nil
            return .couldNotOpen
        }

        switch await presenter(url) {
        case let .success(callback):
            return await complete(callback, action: action)
        case let .failure(error):
            pending = nil
            return WebAuthSheet.isUserCancellation(error) ? .cancelled : .couldNotOpen
        }
    }

    /// The window's address.
    ///
    /// ⚠️ `snake_case` QUERY NAMES, the page's own (`code_challenge`, `redirect_uri`); the
    /// exchange's body is `camelCase`. `device` is the installation id's SHA-256 in hex, never
    /// the id itself.
    static func sheetURL(
        baseURL: URL,
        challenge: PKCEChallenge,
        provider: ReauthProvider,
        deviceHash: String,
        action: NativeReauthAction
    ) -> URL? {
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard var components = URLComponents(string: base + sheetPath) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge.challenge),
            URLQueryItem(name: "state", value: challenge.state),
            URLQueryItem(name: "redirect_uri", value: WebAuthLoginController.redirectURI),
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "device", value: deviceHash),
            URLQueryItem(name: "action", value: action.rawValue),
        ]
        return components.url
    }

    private func complete(_ callback: URL, action: NativeReauthAction) async -> SSOReauthOutcome {
        guard let attempt = pending else { return .stateMismatch }
        // Spent whatever happens: a second callback must not reuse the verifier.
        pending = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let state = value("state"), state == attempt.state else { return .stateMismatch }
        guard let code = value("code"), !code.isEmpty else { return .noCode }

        let result = await repository.reauthenticate(
            action: action,
            code: code,
            codeVerifier: attempt.verifier,
            redirectUri: WebAuthLoginController.redirectURI
        )
        switch result {
        case let .success(seconds):
            return .proved(expiresInSeconds: seconds)
        case let .failure(error):
            return .refused(error)
        }
    }
}

/// One `ASWebAuthenticationSession`, presented and awaited.
///
/// ⛔ THE SESSION AND ITS COMPLETION HANDLER ARE ``WebAuthLoginController``'s, NOT A CLOSURE
/// WRITTEN HERE. AuthenticationServices calls the handler on its own XPC queue, and a closure
/// written inside this `@MainActor` type would inherit that isolation under Swift 6 and trap the
/// moment the window closes (every sign-in crashed build 20012). district-ios builds its closure
/// inline; the Mac cannot. ``WebAuthLoginController/makeSession(url:resumer:)`` builds it outside
/// the main actor, and ``SingleResume`` resumes once.
///
/// ⚠️ NOT EPHEMERAL, and the session and its anchor are held until it ends (the
/// `presentationContextProvider` is weak).
@MainActor
enum WebAuthSheet {
    static func present(_ url: URL) async -> Result<URL, any Error> {
        let anchor = WindowAnchor()
        var session: ASWebAuthenticationSession?
        let result = await withCheckedContinuation { continuation in
            let resumer = SingleResume(continuation)
            let started = WebAuthLoginController.makeSession(url: url, resumer: resumer)
            started.presentationContextProvider = anchor
            started.prefersEphemeralWebBrowserSession = false
            session = started
            // ⚠️ `start()` returning false does not call the completion handler.
            if !started.start() {
                resumer.finish(.failure(WebAuthLoginError.couldNotStart))
            }
        }
        // Held to here, so neither is released while the window is up.
        _ = (anchor, session)
        return result
    }

    static func isUserCancellation(_ error: any Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    /// The key window, else the main window, else any visible one, as sign-in anchors it.
    private final class WindowAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                NSApplication.shared.keyWindow
                    ?? NSApplication.shared.mainWindow
                    ?? NSApplication.shared.windows.first { $0.isVisible }
                    ?? ASPresentationAnchor()
            }
        }
    }
}
