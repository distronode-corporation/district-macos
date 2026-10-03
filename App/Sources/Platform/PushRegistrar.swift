import AppKit
import DistrictData
import DistrictModel
import Foundation
import Observation
import UserNotifications

/// Where notification permission stands on this Mac.
enum PushAuthorization: Equatable, Sendable {
    case notAsked
    case authorized
    case denied
    case unavailable(String)
}

/// What the last attempt to register this Mac's APNs token with the service did.
enum PushRegistrationStatus: Equatable, Sendable {
    case notAttempted
    case registered
    case refused(status: Int)
    case unreachable
    /// APNs itself refused to issue a token, which on a Mac usually means the build is not
    /// signed with a profile carrying `com.apple.developer.aps-environment`.
    case apnsRefused
}

/// The sequencing of push registration: after sign-in, on a token from APNs, and before
/// the sign-out's revoke. Ported from district-ios, without PushKit, CallKit or the
/// silent-push badge refresh (the Mac has no VoIP push by decision; the unread badge is
/// set by the Inbox when it reads, and cleared here on sign-out).
///
/// ⛔ IT NEVER THROWS INTO SIGN-IN OR SIGN-OUT. Push is a courtesy channel; a failed
/// registration must not fail the thing it was attached to.
@MainActor
@Observable
final class PushRegistrar {
    /// ⚠️ A sign-out waits at most this long for the unregister before revoking anyway.
    static let unregisterTimeout: Double = 5

    private(set) var authorization: PushAuthorization = .notAsked
    private(set) var registration: PushRegistrationStatus = .notAttempted
    private(set) var lastRegistrationFailure: String?

    private let container: AppContainer
    private var hasAskedThisLaunch = false

    init(container: AppContainer) {
        self.container = container
    }

    /// Ask for permission once per launch after a sign-in, then register with APNs.
    func enableAfterSignIn() {
        guard !hasAskedThisLaunch else { return }
        hasAskedThisLaunch = true
        Task { await requestAuthorizationThenRegister() }
    }

    /// APNs issued (or re-issued) this Mac's token. Sent as `{token, platform:"macos"}`.
    func deviceTokenReceived(_ token: String) {
        let repository = container.pushTokens
        Task {
            self.registration = await Self.status(for: repository.register(token: token))
        }
    }

    func remoteRegistrationFailed(_ error: any Error) {
        lastRegistrationFailure = String(describing: error)
        registration = .apnsRefused
    }

    /// The first step of a sign-out, bounded so a hung request cannot hold the revoke.
    func unregisterForSignOut() async {
        let repository = container.pushTokens
        let work = Task { await repository.unregister() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(Self.unregisterTimeout))
            work.cancel()
        }
        _ = await work.value
        deadline.cancel()
    }

    /// ⛔ ON EVERY TRANSITION INTO SIGNED-OUT, not only the sign-out button: the server's
    /// row is keyed on the installation, so a remembered token surviving into another
    /// account's session would skip the register that moves the row to that account.
    func forget() {
        container.pushTokens.forgetRegistration()
        registration = .notAttempted
        // ⛔ AND THE BADGE GOES WITH THE MEMORY: a number left on the Dock icon is a count
        // of the previous account's unread messages. Here because this runs on EVERY
        // transition into signed-out, including the one the server ends.
        UnreadBadge.clear()
    }

    static func status(for result: Result<PushRegistrationOutcome, ApiError>) -> PushRegistrationStatus {
        switch result {
        case let .success(outcome):
            switch outcome {
            case .registered, .alreadyRegistered: .registered
            case .noTokenToRegister: .notAttempted
            }
        case let .failure(error):
            switch error {
            case let .http(status, _): .refused(status: status)
            case .transport: .unreachable
            case .decoding: .refused(status: 200)
            }
        }
    }

    private func requestAuthorizationThenRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            authorization = granted ? .authorized : .denied
            guard granted else { return }
        } catch {
            authorization = .unavailable(String(describing: error))
            return
        }
        NSApplication.shared.registerForRemoteNotifications()
    }
}
