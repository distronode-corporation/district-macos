import DistrictModel
import SwiftUI

/// The session gate: checking, signed in, signed out, or unable to tell.
struct RootView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar

    var body: some View {
        content
            .task { await session.refreshPhase() }
            // ⛔ `districtai://handoff` IS TAKEN HERE AND HANDED TO THE ONE FLOW (S33); the
            // flow drops it unless it carries the state of the hand-off in flight.
            // ⚠️ `districtai://auth` never arrives here: `ASWebAuthenticationSession`
            // intercepts it in-session. Any other URL is ignored until app links are
            // ported (Wave 5).
            .onOpenURL { url in
                guard SchedulingHandoffCallback.isCallback(url) else { return }
                let flow = container.schedulingHandoffFlow
                Task { await flow.receive(url) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .checking:
            ProgressView("Checking your session...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .signedIn:
            ShellView(container: container, session: session, push: push)
                .onAppear { push.enableAfterSignIn() }

        case let .signedOut(reason):
            SignInView(
                reason: reason,
                actionTitle: "Sign in",
                isBusy: session.isBusy,
                action: { Task { await session.signIn() } },
                apple: appleDoor
            )

        case let .unavailable(reason):
            SignInView(
                reason: reason,
                actionTitle: "Try again",
                isBusy: session.isBusy,
                action: { Task { await session.refreshPhase() } },
                apple: nil
            )
        }
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
