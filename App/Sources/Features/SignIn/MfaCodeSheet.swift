import DistrictAuthCore
import SwiftUI

/// The authenticator-code step after Sign in with Apple, for an account with an
/// authenticator app enrolled. Ported from district-ios's `MfaCodeSheet` in this app's
/// system-control style (the sign-in screen it sits over uses system controls too).
///
/// ⛔ IT COLLECTS A SECOND FACTOR, NEVER A FIRST ONE. Apple has already verified who this
/// is; this asks only for the 6-digit code (or a recovery code), checked server-side
/// against the same enrolment the web sign-in uses.
///
/// ⚠️ THE INPUTS ARE ``SessionModel``'S. The sheet owns what is being typed and which kind
/// of code it is; the ticket, the request and the outcome live in the session gate.
struct MfaCodeSheet: View {
    let message: String?
    let isBusy: Bool
    let submit: (String) -> Void
    let cancel: () -> Void

    @State private var kind: NativeMfaCodeKind = .authenticator
    @State private var input = ""
    @FocusState private var focused: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    /// The value Verify would send, or nil while the field cannot hold a code.
    private var code: String? {
        NativeMfaCode.normalized(input, as: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MfaCopy.title)
                .font(.title2.weight(.semibold))
            Text(kind == .authenticator ? MfaCopy.authenticatorPrompt : MfaCopy.recoveryPrompt)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            field
            if let message {
                Text(message)
                    .foregroundStyle(Tone.warning.ink(colors))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.SignIn.mfaMessage)
            }
            Button(kind == .authenticator ? MfaCopy.useRecovery : MfaCopy.useAuthenticator, action: toggleKind)
                .buttonStyle(.link)
                .disabled(isBusy)
                .accessibilityIdentifier(A11yID.SignIn.mfaKind)
            HStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button(MfaCopy.cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBusy)
                    .accessibilityIdentifier(A11yID.SignIn.mfaCancel)
                Button(MfaCopy.verify, action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code == nil || isBusy)
                    .accessibilityIdentifier(A11yID.SignIn.mfaVerify)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { focused = true }
        .accessibilityIdentifier(A11yID.SignIn.mfaSheet)
    }

    @ViewBuilder
    private var field: some View {
        if kind == .authenticator {
            TextField(MfaCopy.authenticatorPlaceholder, text: $input)
                // ⛔ `.oneTimeCode` lets AutoFill offer the code from Passwords or Messages.
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit())
                .onChange(of: input) { _, typed in
                    let digits = NativeMfaCode.authenticatorInput(typed)
                    if digits != typed {
                        input = digits
                    }
                }
                .districtField()
                .focused($focused)
                .disabled(isBusy)
                .onSubmit(send)
                .accessibilityIdentifier(A11yID.SignIn.mfaCode)
        } else {
            TextField(MfaCopy.recoveryPlaceholder, text: $input)
                .autocorrectionDisabled()
                .districtField()
                .focused($focused)
                .disabled(isBusy)
                .onSubmit(send)
                .accessibilityIdentifier(A11yID.SignIn.mfaCode)
        }
    }

    private func send() {
        guard let code, !isBusy else { return }
        submit(code)
    }

    private func toggleKind() {
        kind = kind == .authenticator ? .recovery : .authenticator
        input = ""
        focused = true
    }
}
