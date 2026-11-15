import DistrictData
import SwiftUI

/// The account deletion sheet: what is deleted and kept, a fresh re-authentication, the typed
/// email, then the deletion. See ``DeleteAccountModel``. Ported from district-ios.
///
/// ⚠️ A SHEET, NOT A ``Route``. The flow is modal and has no place in a back stack: a restored
/// stack must never land a person on its last step.
///
/// ⚠️ DRAWN IN ``MacSheetChrome``, where iOS has a `NavigationStack` with a Cancel in its
/// toolbar: the title, the step, then one bottom row with Cancel (Esc) and the step's own
/// button, as every Mac sheet here is. The ways to confirm it is you stay in the step, one
/// button each, as on iOS.
///
/// ⛔ AFTER A DELETION THE SHEET DOES NOT CLOSE ITSELF. ``SessionModel/finishDeletedAccount(
/// externalErasurePending:)`` signs out locally, and ``RootView`` swaps the shell, this sheet
/// with it, for the sign-in screen, which says the account was deleted.
struct DeleteAccountView: View {
    @State private var model: DeleteAccountModel
    @FocusState private var focused: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Field {
        case password, code, email
    }

    init(container: AppContainer, session: SessionModel) {
        let repository = NativeReauthRepository(client: container.api)
        let sheet = ReauthSheetController(
            baseURL: container.baseURL,
            repository: repository,
            deviceId: container.deviceId
        )
        _model = State(initialValue: DeleteAccountModel(
            repository: repository,
            sso: { provider in await sheet.reauthenticate(provider: provider, action: .deleteAccount) },
            deleted: { pending in await session.finishDeletedAccount(externalErasurePending: pending) }
        ))
    }

    /// For previews and tests: a model built elsewhere.
    init(model: DeleteAccountModel) {
        _model = State(initialValue: model)
    }

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        MacSheetChrome(title: DeleteAccountCopy.title) {
            ScrollView {
                VStack(alignment: .leading, spacing: DistrictSpacing.section) {
                    content
                }
                .padding(DistrictSpacing.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } buttons: {
            buttons
        }
        // ⚠️ NO ESC MID-REQUEST: the answer would land on a sheet nobody sees.
        .interactiveDismissDisabled(model.busy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.DeleteAccount.sheet)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .explain:
            warningCard
            failureLine
            methodsCard
        case let .password(needsCode):
            failureLine
            passwordCard(needsCode: needsCode)
        case .confirm:
            failureLine
            confirmCard
        }
    }

    // ── What is deleted ──────────────────────────────────────────────────────

    private var warningCard: some View {
        card {
            Text(DeleteAccountCopy.cannotBeUndone)
                .font(DistrictType.title)
                .foregroundStyle(colors.destructive)
            paragraph(DeleteAccountCopy.whatIsDeleted)
            paragraph(DeleteAccountCopy.subscriptionsCancelled)
            paragraph(DeleteAccountCopy.whatIsKept)
        }
    }

    // ── Confirm it is you ────────────────────────────────────────────────────

    private var methodsCard: some View {
        card {
            DistrictEyebrow(text: DeleteAccountCopy.confirmItIsYou)
            paragraph(DeleteAccountCopy.confirmIntro)
            ForEach(ReauthProvider.allCases, id: \.self) { provider in
                Button(DeleteAccountCopy.continueWith(provider.displayName)) {
                    Task { await model.reauthenticate(with: provider) }
                }
                .buttonStyle(.districtSecondary)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.DeleteAccount.provider(provider.rawValue))
            }
            Button(DeleteAccountCopy.usePassword) {
                model.usePassword()
                focused = .password
            }
            .buttonStyle(.districtSecondary)
            .disabled(model.busy)
            .accessibilityIdentifier(A11yID.DeleteAccount.usePassword)
        }
    }

    private func passwordCard(needsCode: Bool) -> some View {
        card {
            DistrictEyebrow(text: DeleteAccountCopy.confirmItIsYou)
            SecureField(DeleteAccountCopy.passwordLabel, text: $model.password)
                .textContentType(.password)
                .districtField()
                .focused($focused, equals: .password)
                .disabled(model.busy)
                .onSubmit {
                    if needsCode {
                        focused = .code
                    } else {
                        submitPassword()
                    }
                }
                .accessibilityIdentifier(A11yID.DeleteAccount.password)
            if needsCode {
                paragraph(MfaCopy.authenticatorPrompt)
                TextField(MfaCopy.authenticatorPlaceholder, text: $model.code)
                    // ⚠️ ONE FIELD FOR BOTH KINDS: the service takes an authenticator code or a
                    // recovery code in the same place.
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .districtField()
                    .focused($focused, equals: .code)
                    .disabled(model.busy)
                    .onSubmit(submitPassword)
                    .accessibilityIdentifier(A11yID.DeleteAccount.code)
            }
        }
    }

    // ── The last step ────────────────────────────────────────────────────────

    private var confirmCard: some View {
        card {
            DistrictEyebrow(text: DeleteAccountCopy.lastStep)
            paragraph(DeleteAccountCopy.typeEmail)
            TextField(DeleteAccountCopy.emailLabel, text: $model.confirmation)
                .autocorrectionDisabled()
                .districtField()
                .focused($focused, equals: .email)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.DeleteAccount.email)
        }
        .onAppear { focused = .email }
    }

    // ── The button row ───────────────────────────────────────────────────────

    /// Cancel (Esc) on every step, then the step's own: Back and Continue (Return) for the
    /// password, and the red Delete my account last.
    ///
    /// ⛔ DELETE IS NOT THE DEFAULT BUTTON. Return in the email field must never delete an
    /// account; it takes a click on the button that says so.
    @ViewBuilder
    private var buttons: some View {
        if model.busy {
            ProgressView()
                .controlSize(.small)
        }
        if case .password = model.step {
            Button(DeleteAccountCopy.back, action: model.back)
                .buttonStyle(.districtGhost)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.DeleteAccount.back)
        }
        Button(DeleteAccountCopy.cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
            .disabled(model.busy)
            .accessibilityIdentifier(A11yID.DeleteAccount.cancel)
        switch model.step {
        case .explain:
            EmptyView()
        case .password:
            Button(DeleteAccountCopy.continueButton, action: submitPassword)
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmitPassword)
                .accessibilityIdentifier(A11yID.DeleteAccount.passwordContinue)
        case .confirm:
            Button(model.busy ? DeleteAccountCopy.deleting : DeleteAccountCopy.submit) {
                Task { await model.delete() }
            }
            .buttonStyle(.districtDestructive)
            .disabled(!model.canDelete)
            .accessibilityIdentifier(A11yID.DeleteAccount.submit)
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private var failureLine: some View {
        if let failure = model.failure {
            VStack(alignment: .leading, spacing: DistrictSpacing.hairline) {
                if let title = failure.title {
                    Text(title)
                        .font(DistrictType.labelLarge)
                }
                Text(failure.message)
                    .font(DistrictType.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Tone.warning.ink(colors))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(A11yID.DeleteAccount.message)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(DistrictType.bodySmall)
            .foregroundStyle(colors.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(@ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.row) {
            rows()
        }
        .padding(DistrictSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .districtCardSurface()
    }

    private func submitPassword() {
        Task { await model.submitPassword() }
    }
}
