import AppKit
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
            // ⚠️ DECORATION: VoiceOver read it as "phone.bubble", in every language.
            Image(systemName: "phone.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(SignInCopy.districtAi)
                .font(.largeTitle.weight(.semibold))
            if !reason.isEmpty {
                Text(reason)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            }
            // ⚠️ THE TWO DOORS ARE ONE SIZE AND ONE SHAPE (``SignInDoor``): the Sign in capsule
            // was wider and rounder than Apple's rectangle beside it (3.0.1 visual QA,
            // AP-030), and Apple asks that its button be no smaller than the others.
            Button(action: action) {
                Text(actionTitle)
            }
            .buttonStyle(SignInDoorStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)

            if let apple {
                SignInWithAppleButton(.signIn, onRequest: apple.prepare, onCompletion: apple.finish)
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: SignInDoor.width, height: SignInDoor.height)
                    .clipShape(RoundedRectangle(cornerRadius: SignInDoor.radius))
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

    /// ⚠️ THE TWO PAGES READ AS LINKS: the link colour, underlined, as the system draws one.
    /// The line's own words are secondary. Until 3.0.1 the secondary ink covered the links
    /// too, so nothing said they could be clicked (visual QA, AP-030).
    private var terms: some View {
        VStack(spacing: 4) {
            Text(SignInTermsCopy.prefix)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Link(SignInTermsCopy.termsName, destination: SignInTermsCopy.termsURL)
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .underline()
                Text(SignInTermsCopy.conjunction)
                    .foregroundStyle(.secondary)
                Link(SignInTermsCopy.privacyName, destination: SignInTermsCopy.privacyURL)
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .underline()
                Text(SignInTermsCopy.terminator)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// The size and shape both sign-in doors share.
enum SignInDoor {
    static let width: CGFloat = 280
    static let height: CGFloat = 32
    static let radius: CGFloat = 6
}

/// The Sign in door: the accent filled to Apple's button's size and corner.
private struct SignInDoorStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SignInDoorLabel(configuration: configuration)
    }
}

private struct SignInDoorLabel: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DistrictColors.resolve(colorScheme)
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colors.districtForeground)
            .frame(width: SignInDoor.width, height: SignInDoor.height)
            .background(colors.district, in: RoundedRectangle(cornerRadius: SignInDoor.radius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: SignInDoor.radius))
    }
}
