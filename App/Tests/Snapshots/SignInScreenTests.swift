import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The signed-out window and the authenticator-code sheet over it, in the states the session
/// puts them in (``SessionModel``'s phases and its code step).
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class SignInScreenTests: ScreenSnapshotCase {
    /// The code sheet is 380 points wide (its own `frame`), as tall as its content.
    private static let codeSize = CGSize(width: 380, height: 300)

    // MARK: - Sign in

    func testSignIn() async throws {
        // A first launch: no reason, and both doors (Sign in, and Sign in with Apple).
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("first", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.regular
            ) { _ in
                Self.signIn(reason: "")
            }
        }
        // Signed out by the service: the reason above the doors.
        try await assertView("expired-en", rules: ScreenRules.loaded, size: Self.regular) { _ in
            Self.signIn(reason: SessionCopy.refreshTokenExpired)
        }
        // A sign-in under way.
        try await assertView("busy-en", rules: ScreenRules.loaded, size: Self.regular) { _ in
            Self.signIn(reason: "", isBusy: true)
        }
        // The session could not be checked: Try again, and no fresh sign-in offered.
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("unavailable", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.regular
            ) { _ in
                AnyView(SignInView(
                    reason: SessionCopy.refreshThrottled,
                    actionTitle: CommonCopy.tryAgain,
                    isBusy: false,
                    action: {},
                    apple: nil
                )
                .districtTheme())
            }
        }
    }

    /// The signed-out screen as ``RootView`` draws it, with the Apple door.
    private static func signIn(reason: String, isBusy: Bool = false) -> AnyView {
        AnyView(SignInView(
            reason: reason,
            actionTitle: CommonCopy.signIn,
            isBusy: isBusy,
            action: {},
            apple: AppleSignInHandlers(prepare: { _ in }, finish: { _ in })
        )
        .districtTheme())
    }

    // MARK: - Authenticator code

    func testMfaCode() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("code", locale),
                rules: ScreenRules.loaded,
                locale: locale,
                size: Self.codeSize
            ) { _ in
                Self.code(message: nil, isBusy: false)
            }
        }
        // The service refused the code, and the sheet stays up saying so.
        try await assertView("wrong-code-en", rules: ScreenRules.loaded, size: Self.codeSize) { _ in
            Self.code(message: MfaCopy.wrongCode, isBusy: false)
        }
        try await assertView("verifying-en", rules: ScreenRules.loaded, size: Self.codeSize) { _ in
            Self.code(message: nil, isBusy: true)
        }
    }

    private static func code(message: String?, isBusy: Bool) -> AnyView {
        AnyView(MfaCodeSheet(message: message, isBusy: isBusy, submit: { _ in }, cancel: {}).districtTheme())
    }
}
