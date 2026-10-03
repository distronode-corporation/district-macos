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
                apple: AppleSignInHandlers(
                    prepare: { container.appleLogin.prepare($0) },
                    finish: { result in Task { await session.signInWithApple(result) } }
                )
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
}
