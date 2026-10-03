import DistrictModel
import SwiftUI

/// The session gate: checking, signed in, signed out, or unable to tell.
struct RootView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar
    let live: DesktopLive
    let incoming: IncomingCallModel

    var body: some View {
        content
            // ⚠️ THE BRAND TINT, PUBLISHED ONCE, ABOVE EVERYTHING, as on iOS (`RootView`). It is
            // the only part of the theme that travels through the environment: the palette is
            // derived per view from `colorScheme`, so a subtree without it is still correctly
            // coloured and only SwiftUI's own controls (switches, prominent buttons, progress,
            // the sidebar's symbols) fall back to the system accent. ⚠️ MAC: a window is its
            // own root, so the Settings window and the ring panel apply it too.
            .districtTheme()
            .task { await session.refreshPhase() }
            // ⛔ THE RING FOLLOWS THE SESSION GATE IN BOTH DIRECTIONS: a ring waiting on an
            // unresolved session is resolved here, and a session that ends (or cannot be
            // checked) stops this Mac ringing. The shell starts it again with a workspace.
            .onChange(of: session.phase, initial: true) {
                incoming.sessionChanged(session.phase)
                switch session.phase {
                case .signedOut, .unavailable:
                    live.sessionEnded()
                case .checking, .signedIn:
                    break
                }
            }
            // ⛔ `districtai://handoff` IS TAKEN HERE AND HANDED TO THE ONE FLOW (S33); the
            // flow drops it unless it carries the state of the hand-off in flight.
            // ⚠️ `districtai://auth` never arrives here: `ASWebAuthenticationSession`
            // intercepts it in-session. Any other URL is ignored: routing an app link
            // (iOS `AppLinkRouting`) into a section is not ported yet.
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
            ShellView(container: container, session: session, push: push, live: live)
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
