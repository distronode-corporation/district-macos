import AppKit
import DistrictData
import DistrictModel
import Foundation
import Observation
import OSLog
import UserNotifications

/// The push lifecycle's log, read on the Mac with
/// `log stream --predicate 'subsystem == "com.distronode.district" AND category == "push"'`.
///
/// ⛔ PUBLIC ONLY FOR VALUES THAT NAME NOBODY: an outcome, a status code, a token's LENGTH, an
/// error's domain and code, a payload's `type`. Never the device token, an account, a
/// workspace or a call id.
enum PushLog {
    static let logger = Logger(subsystem: "com.distronode.district", category: "push")
}

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
/// silent-push badge refresh (PushKit's VoIP push is unavailable on macOS, and a closed
/// window keeps the app ringing over its socket instead (``BackgroundRinging``); the
/// unread badge is set by the Inbox when it reads, and cleared here on sign-out).
///
/// ⛔ IT NEVER THROWS INTO SIGN-IN OR SIGN-OUT. Push is a courtesy channel; a failed
/// registration must not fail the thing it was attached to.
///
/// ⛔ EVERY SIGNED-IN SESSION REGISTERS, AND EVERY ONE SENDS ITS REGISTER. The quit app's
/// ring is the server's APNs alert, so a Mac with no live alert row is a Mac that does not
/// ring once the app is quit. 3.0.0 asked once per LAUNCH (`hasAskedThisLaunch`), from the
/// window's appearance: a second account signed in on the same launch never called
/// `registerForRemoteNotifications`, while the sign-out before it had deleted the
/// installation's rows, so that account had no alert row at all (2026-10-15). Now the ask
/// is once per signed-in session (``forget()`` re-arms it), it is started by
/// ``SessionModel`` and not by a window, and the remembered token is forgotten first, so
/// the register is sent on every launch and every sign-in even when the token is the one
/// the server last affirmed: a row the server retired or deleted since is put back.
@MainActor
@Observable
final class PushRegistrar {
    /// ⚠️ A sign-out waits at most this long for the unregister before revoking anyway.
    static let unregisterTimeout: Double = 5

    private(set) var authorization: PushAuthorization = .notAsked
    private(set) var registration: PushRegistrationStatus = .notAttempted
    private(set) var lastRegistrationFailure: String?

    /// The payload of the notification the user last clicked, un-parsed.
    ///
    /// ⛔ FLAT `[String: String]`, AND NOTHING HERE ROUTES IT, as on iOS: `PushPayload` and
    /// `PushDeepLinks` live in the core, where they are tested, and ``ShellView`` routes.
    /// ``AppDelegate`` writes it; the shell empties it on pickup.
    var pendingTapPayload: [String: String]?

    private let container: AppContainer
    private let system: PushSystem

    /// Whether this signed-in session has asked for permission and an APNs token.
    ///
    /// ⚠️ PER SESSION, NOT PER LAUNCH: ``forget()`` clears it on every transition into
    /// signed-out, which is what makes the next sign-in, on this launch or a later one,
    /// register again. It still stops a second ask within one session (the gate reaching
    /// signed-in again after "Try again").
    private var hasAskedThisSession = false

    /// - Parameter system: the OS's notification calls. ⚠️ The live one everywhere but a
    ///   test, which records them instead of asking macOS.
    init(container: AppContainer, system: PushSystem = .live) {
        self.container = container
        self.system = system
    }

    /// Ask for permission once per signed-in session, then register with APNs.
    ///
    /// ⛔ THE REMEMBERED TOKEN IS FORGOTTEN FIRST, so the token APNs hands back is sent to
    /// the server even when it is byte-identical to the last one affirmed: APNs reissues the
    /// same token for this app on this Mac whoever is signed in, and the server's row may
    /// have been deleted (a sign-out) or retired (a failed send) since it was affirmed.
    func enableAfterSignIn() {
        guard !hasAskedThisSession else { return }
        hasAskedThisSession = true
        container.pushTokens.forgetRegistration()
        Task { await requestAuthorizationThenRegister() }
    }

    /// APNs issued (or re-issued) this Mac's token. Sent as `{token, platform:"macos"}`.
    func deviceTokenReceived(_ token: String) {
        PushLog.logger.notice("APNs issued a token (\(token.count, privacy: .public) hex characters)")
        let repository = container.pushTokens
        Task {
            let status = await Self.status(for: repository.register(token: token))
            self.registration = status
            PushLog.logger.notice("the service register answered: \(String(describing: status), privacy: .public)")
        }
    }

    func remoteRegistrationFailed(_ error: any Error) {
        let nsError = error as NSError
        PushLog.logger.error(
            "APNs refused a token: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)"
        )
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
    ///
    /// ⛔ AND THIS MAC STOPS TAKING REMOTE NOTIFICATIONS UNTIL THE NEXT SIGN-IN. A session
    /// the SERVER ended (or one whose rotated token never reached the keychain) leaves no
    /// credential to unregister with, so the account's alert row stays live and its
    /// messages and calls would keep arriving on a Mac showing the sign-in screen.
    /// `unregisterForRemoteNotifications` is the one withdrawal that needs no session: APNs
    /// refuses the token from then on, and the server retires the row on its next send.
    /// The next sign-in registers again (``enableAfterSignIn()``).
    func forget() {
        container.pushTokens.forgetRegistration()
        registration = .notAttempted
        hasAskedThisSession = false
        PushLog.logger.notice("signed out: unregistering from APNs until the next sign-in")
        system.unregister()
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
            case let .http(status, _, _): .refused(status: status)
            case .transport: .unreachable
            case .decoding: .refused(status: 200)
            }
        }
    }

    private func requestAuthorizationThenRegister() async {
        do {
            let granted = try await system.requestAuthorization()
            authorization = granted ? .authorized : .denied
            PushLog.logger.notice("notification authorization granted: \(granted, privacy: .public)")
            guard granted else { return }
        } catch {
            authorization = .unavailable(String(describing: error))
            let nsError = error as NSError
            PushLog.logger.error(
                "authorization failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)"
            )
            return
        }
        PushLog.logger.notice("registering with APNs")
        system.register()
    }
}

/// The OS's half of push: the permission prompt, and APNs registration.
///
/// ⚠️ CLOSURES RATHER THAN THE CALLS, SO A TEST ASKS NOTHING OF macOS. The test host is this
/// app, and a real `requestAuthorization` there is a system prompt nobody answers.
struct PushSystem: Sendable {
    let requestAuthorization: @MainActor @Sendable () async throws -> Bool
    let register: @MainActor @Sendable () -> Void
    let unregister: @MainActor @Sendable () -> Void

    /// `UNUserNotificationCenter` and `NSApplication`.
    static let live = PushSystem(
        requestAuthorization: {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        },
        register: { NSApplication.shared.registerForRemoteNotifications() },
        unregister: { NSApplication.shared.unregisterForRemoteNotifications() }
    )
}
