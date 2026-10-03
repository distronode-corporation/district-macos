import AuthenticationServices
import SwiftUI

/// The two closures the Sign in with Apple button needs, owned by the controller.
struct AppleSignInHandlers {
    let prepare: (ASAuthorizationAppleIDRequest) -> Void
    let finish: (Result<ASAuthorization, any Error>) -> Void
}

/// The signed-out screen: the web sign-in door, the Apple door, and why the user is here.
///
/// ⚠️ A FIRST CUT OF THE iOS SignInView, kept to what the doors need. The full screen
/// (brand art, the status tone) is ported with the rest of the UI in Wave 5.
struct SignInView: View {
    let reason: String
    let actionTitle: String
    let isBusy: Bool
    let action: () -> Void
    /// Nil on the "Try again" screen, where offering a fresh sign-in would hide the reason
    /// the saved session could not be read.
    let apple: AppleSignInHandlers?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "phone.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("District AI")
                .font(.largeTitle.weight(.semibold))
            if !reason.isEmpty {
                Text(reason)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            }
            Button(action: action) {
                Text(actionTitle)
                    .frame(width: 260)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)

            if let apple {
                SignInWithAppleButton(.signIn, onRequest: apple.prepare, onCompletion: apple.finish)
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 260, height: 32)
                    .disabled(isBusy)
            }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            terms
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terms: some View {
        VStack(spacing: 4) {
            Text(SignInTermsCopy.prefix)
            HStack(spacing: 0) {
                Link(SignInTermsCopy.termsName, destination: SignInTermsCopy.termsURL)
                Text(SignInTermsCopy.conjunction)
                Link(SignInTermsCopy.privacyName, destination: SignInTermsCopy.privacyURL)
                Text(SignInTermsCopy.terminator)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
