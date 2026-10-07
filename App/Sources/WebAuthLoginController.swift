import AppKit
import AuthenticationServices
import DistrictAuthCore
import DistrictNetwork
import Foundation

/// Drives the two-leg native login. Ported from district-ios.
///
/// ⛔ LEG ONE HAPPENS IN `ASWebAuthenticationSession`, NOT A `WKWebView`. It reuses the
/// server's login surface (Google SSO, Microsoft SSO, the password route), and an
/// embedded web view would be refused by Google's OAuth policy and would hand this app
/// the user's password.
///
/// ⛔ LEG TWO IS A DIRECT POST NO OTHER PROCESS OBSERVED. The browser hands back only a
/// URL carrying a single-use code, worthless without the PKCE verifier kept in memory.
///
/// ⚠️ THE VERIFIER IS NEVER PERSISTED. A login interrupted by a quit is restarted.
@MainActor
final class WebAuthLoginController: NSObject {
    /// ⛔ BYTE-FOR-BYTE THE SERVER'S NATIVE REDIRECT ALLOWLIST, compared literally twice.
    nonisolated static let redirectURI = "districtai://auth"

    /// The scheme half of ``redirectURI``: no `://`, no path.
    nonisolated static let callbackScheme = "districtai"

    /// ⚠️ A PAGE, NOT AN API ROUTE: `/auth/native` bounces an unauthenticated visitor
    /// through `/login?redirect=...`.
    private static let authorizePath = "/auth/native"

    private let baseURL: URL
    private let exchange: AppNativeAuthClient
    private let coordinator: TokenRefreshCoordinator
    private let deviceId: String
    private let deviceName: String?

    /// The in-flight attempt, single-slot: a new login abandons the previous one.
    private var pending: PKCEChallenge?

    /// Held so the session outlives `present(_:)`.
    private var session: ASWebAuthenticationSession?

    init(
        baseURL: URL,
        exchange: AppNativeAuthClient,
        coordinator: TokenRefreshCoordinator,
        deviceId: String,
        deviceName: String?
    ) {
        self.baseURL = baseURL
        self.exchange = exchange
        self.coordinator = coordinator
        self.deviceId = deviceId
        self.deviceName = deviceName
        super.init()
    }

    /// Run one complete login.
    func signIn() async -> LoginOutcome {
        let challenge = PKCE.newChallenge()
        pending = challenge

        guard let url = authorizeURL(for: challenge) else {
            pending = nil
            return .denied("unbuildable_authorize_url")
        }

        switch await present(url) {
        case let .success(callback):
            return await complete(callback)
        case let .failure(error):
            pending = nil
            return Self.isUserCancellation(error) ? .cancelled : .unreachable
        }
    }

    /// Abandon an in-flight attempt.
    func cancel() {
        pending = nil
        session?.cancel()
        session = nil
    }

    // MARK: - Leg one

    /// The URL the authentication session opens.
    ///
    /// ⚠️ snake_case query names (`code_challenge`, `state`, `redirect_uri`), unlike the
    /// exchange's camelCase body.
    func authorizeURL(for challenge: PKCEChallenge) -> URL? {
        // ⚠️ Assembled as a string: `appendingPathComponent` would encode the slash.
        let base = baseURL.absoluteString
        let text = (base.hasSuffix("/") ? String(base.dropLast()) : base) + Self.authorizePath
        guard var components = URLComponents(string: text) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge.challenge),
            URLQueryItem(name: "state", value: challenge.state),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]
        return components.url
    }

    private func present(_ url: URL) async -> Result<URL, any Error> {
        await withCheckedContinuation { continuation in
            let resumer = SingleResume(continuation)
            let session = Self.makeSession(url: url, resumer: resumer)
            session.presentationContextProvider = self
            // ⛔ FALSE: share the browser's cookies, so a user already signed in to the
            // website is not asked to sign in to Google or Microsoft again.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            // ⚠️ `start()` returning false does not call the completion handler.
            if !session.start() {
                resumer.finish(.failure(WebAuthLoginError.couldNotStart))
            }
        }
    }

    /// The session, built OUTSIDE the main actor.
    ///
    /// ⛔ THE COMPLETION HANDLER MUST NOT BE MAIN-ACTOR ISOLATED. AuthenticationServices
    /// calls it on its own XPC reply queue (`com.apple.SafariLaunchAgent`). A closure
    /// written inside this `@MainActor` class inherits that isolation under Swift 6, and
    /// the runtime's executor check then traps (SIGILL in `dispatch_assert_queue`) the
    /// moment the session ends: every sign-in crashed build 20012. Built here, the
    /// closure is plain `@Sendable` and only resumes the continuation, which is safe from
    /// any thread; `MacWebAuthIsolationTests` calls it from a background queue.
    ///
    /// ⚠️ THE DEPRECATED INITIALISER, DELIBERATELY, as on iOS: its replacement's
    /// `.customScheme(_:)` is macOS 14.4+, and this target deploys to 14.0.
    nonisolated static func makeSession(url: URL, resumer: SingleResume) -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme,
            completionHandler: completionHandler(resumer)
        )
    }

    /// The session's completion handler, separate so a test can call it off the main thread.
    nonisolated static func completionHandler(_ resumer: SingleResume) -> @Sendable (URL?, (any Error)?) -> Void {
        { callback, error in
            if let callback {
                resumer.finish(.success(callback))
            } else {
                resumer.finish(.failure(error ?? WebAuthLoginError.noCallback))
            }
        }
    }

    // MARK: - Leg two

    /// The code exchange's request, as this app sends it.
    ///
    /// ⛔ `clientPlatform: .macos`, STATED HERE AND NOWHERE ELSE. The core defaults it to
    /// `.ios`, so a request built without it lists this Mac as an iPhone in Devices.
    /// `MacClientPlatformTests` pins the body this builds as `"platform":"macos"`.
    nonisolated static func codeExchangeRequest(
        code: String,
        verifier: String,
        deviceId: String,
        deviceName: String?
    ) -> CodeExchangeRequest {
        CodeExchangeRequest(
            code: code,
            codeVerifier: verifier,
            redirectUri: redirectURI,
            deviceId: deviceId,
            deviceName: deviceName,
            clientPlatform: .macos
        )
    }

    /// Validate the callback and exchange its code.
    ///
    /// ⛔ `state` IS CHECKED BEFORE THE CODE IS SPENT: a callback this app never initiated
    /// would bind the session to an attacker-chosen account.
    private func complete(_ callback: URL) async -> LoginOutcome {
        guard let attempt = pending else { return .noAttemptInProgress }
        pending = nil
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let state = value("state"), state == attempt.state else {
            return .stateMismatch
        }
        if let error = value("error") {
            return .denied(error)
        }
        guard let code = value("code") else {
            return .denied("missing_code")
        }

        let request = Self.codeExchangeRequest(
            code: code,
            verifier: attempt.verifier,
            deviceId: deviceId,
            deviceName: deviceName
        )

        switch await exchange.exchangeCode(request) {
        case let .success(tokens):
            // ⛔ THE COORDINATOR ADOPTS, NOTHING ELSE WRITES.
            await coordinator.adopt(tokens, deviceId: deviceId)
            return .success
        case .rejected:
            return .rejected
        case .rateLimited:
            return .rateLimited
        case .noAccount:
            return .noAccount
        case .transportFailure, .mfaRequired:
            // ⚠️ `mfaRequired` IS UNREACHABLE HERE: `exchangeCode` never produces it (the web
            // page asks for the code itself), and this door holds no ticket to spend.
            return .unreachable
        }
    }

    private static func isUserCancellation(_ error: any Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}

/// ⚠️ REQUIRED: the session refuses to start without a presentation context provider.
extension WebAuthLoginController: ASWebAuthenticationPresentationContextProviding {
    /// The key window, else the main window, else any visible window. ⚠️ The last
    /// fallback is an empty window rather than a crash; reaching it means the app has no
    /// window at all, and sign-in then reports `.unreachable`.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first { $0.isVisible }
            ?? ASPresentationAnchor()
    }
}

/// How one login attempt ended. Shared by both sign-in doors.
enum LoginOutcome: Sendable, Equatable {
    case success
    /// The user dismissed the sheet. ⚠️ Benign; never rendered as a failure.
    case cancelled
    /// A callback arrived with no attempt in flight.
    case noAttemptInProgress
    /// ⛔ The callback's `state` did not match. Treated as hostile; never exchanged.
    case stateMismatch
    /// The hand-off page refused, with its own reason.
    case denied(String)
    /// Expired, replayed or a PKCE mismatch, collapsed by the server on purpose.
    case rejected
    case rateLimited
    /// ⛔ The Apple door's 403: no District AI account uses this Apple ID.
    case noAccount
    /// ⛔ The Apple door's 401 `mfa_required`: the account has an authenticator on, so
    /// nothing is signed in until a code is entered. ``SessionModel`` opens the code step.
    case mfaRequired(NativeMfaChallenge)
    /// The exchange never got a usable answer.
    case unreachable
}

enum WebAuthLoginError: Error {
    case couldNotStart
    case noCallback
}

/// Guarantees a `CheckedContinuation` is resumed exactly once, because a checked
/// continuation traps on a second resume and the path that could cause one is the SDK's.
final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<URL, any Error>, Never>?

    init(_ continuation: CheckedContinuation<Result<URL, any Error>, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<URL, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: result)
    }
}
