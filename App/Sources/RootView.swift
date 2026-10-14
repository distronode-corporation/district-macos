import DistrictModel
import SwiftUI

/// The session gate: checking, signed in, signed out, or unable to tell.
///
/// ⚠️ NO `onOpenURL` HERE: the scheduling hand-off's callback and app links are both taken
/// by ``ShellView``, the signed-in gate, as on iOS.
struct RootView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar
    let live: DesktopLive

    var body: some View {
        content
            // ⚠️ THE BRAND TINT, PUBLISHED ONCE, ABOVE EVERYTHING, as on iOS (`RootView`). It is
            // the only part of the theme that travels through the environment: the palette is
            // derived per view from `colorScheme`, so a subtree without it is still correctly
            // coloured and only SwiftUI's own controls (switches, prominent buttons, progress,
            // the sidebar's symbols) fall back to the system accent. ⚠️ MAC: a window is its
            // own root, so the Settings window and the ring panel apply it too.
            .districtTheme()
            // ⚠️ A NO-OP ONCE THE APP DELEGATE HAS LAUNCHED THE SESSION, which it does with or
            // without a window. ⛔ The ring follows the session gate in ``SessionModel``, not
            // here: the app keeps ringing with this window closed (``BackgroundRinging``).
            .task { await session.launch() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .checking:
            ProgressView(CommonCopy.checkingYourSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .signedIn:
            ShellView(container: container, session: session, push: push, live: live)
                .onAppear { push.enableAfterSignIn() }

        case let .signedOut(reason):
            SignInView(
                reason: reason,
                actionTitle: CommonCopy.signIn,
                isBusy: session.isBusy,
                action: { Task { await session.signIn() } },
                apple: appleDoor
            )
            // ⛔ THE AUTHENTICATOR STEP IS A SHEET OVER THIS SCREEN, NOT A PHASE. The phase
            // stays `signedOut` until the code is accepted, so Cancel leaves exactly the
            // sign-in screen, and an accepted code removes this branch and the sheet with
            // it. Reached only from the Apple door, so never in the Developer ID build.
            .sheet(item: pendingMfa) { _ in
                MfaCodeSheet(
                    message: session.mfaMessage,
                    isBusy: session.isVerifyingCode,
                    submit: { code in Task { await session.submitMfaCode(code) } },
                    cancel: { session.cancelMfa() }
                )
                .interactiveDismissDisabled(session.isVerifyingCode)
            }

        case let .unavailable(reason):
            SignInView(
                reason: reason,
                actionTitle: CommonCopy.tryAgain,
                isBusy: session.isBusy,
                action: { Task { await session.refreshPhase() } },
                apple: nil
            )
        }
    }

    /// The authenticator step as a sheet item. ⚠️ Writing nil is a dismissal, which drops
    /// the ticket; nothing else writes through it.
    private var pendingMfa: Binding<PendingMfa?> {
        Binding(
            get: { session.pendingMfa },
            set: { item in
                if item == nil {
                    session.cancelMfa()
                }
            }
        )
    }

    /// The native Sign in with Apple door, in the App Store build only.
    ///
    /// ⛔ NIL IN THE DEVELOPER ID BUILD, which does not claim the entitlement: Apple leaves
    /// `com.apple.developer.applesignin` out of this app's Developer ID provisioning
    /// profile (it grants push, associated domains and the keychain group), and an export
    /// that claims it fails. A native request there would fail too. Apple stays one click
    /// away in that build: the website's sign-in offers it beside Google and Microsoft.
    private var appleDoor: AppleSignInHandlers? {
        #if DEVELOPER_ID
            return nil
        #else
            return AppleSignInHandlers(
                prepare: { container.appleLogin.prepare($0) },
                finish: { result in Task { await session.signInWithApple(result) } }
            )
        #endif
    }
}
