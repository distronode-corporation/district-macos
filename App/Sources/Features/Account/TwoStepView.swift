import AppKit
import DistrictData
import SwiftUI

/// The two-step verification sheet: whether it is on, turning it on with an authenticator app,
/// the recovery codes once, and turning it off. See ``TwoStepModel``. Ported from district-ios.
///
/// ⚠️ A SHEET, NOT A ``Route``, as ``DeleteAccountView``: the flow is modal, and a restored back
/// stack must never land on a step that held a secret. ⚠️ ON ACCOUNT, NOT IN THE SETTINGS
/// WINDOW: that window holds only what belongs to this Mac (``SettingsView``), and this is the
/// account's.
///
/// ⚠️ DRAWN IN ``MacSheetChrome``, where iOS has a `NavigationStack` with a Close in its toolbar:
/// the choices stay in the step (Turn on or off, the ways to confirm it is you), and Back, Close
/// (Esc) and the step's own button (Return) are the bottom row.
///
/// ⛔ THE SECRET AND THE CODES ARE COVERED WHENEVER THE APP IS NOT ACTIVE, so neither another
/// app's window nor a screen shared while switching away shows them, and are marked
/// privacy-sensitive. On the Mac "not active" is `NSApplication`'s, not the scene phase, which
/// stays `.active` while another app is in front. Closing the sheet drops them
/// (``TwoStepModel/leave()``).
struct TwoStepView: View {
    @State private var model: TwoStepModel
    @State private var appActive = NSApplication.shared.isActive
    @FocusState private var focused: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Field {
        case password, code
    }

    init(container: AppContainer) {
        let reauth = NativeReauthRepository(client: container.api)
        let sheet = ReauthSheetController(
            baseURL: container.baseURL,
            repository: reauth,
            deviceId: container.deviceId
        )
        _model = State(initialValue: TwoStepModel(
            settings: TwoStepSettingsRepository(client: container.api),
            reauth: reauth,
            sso: { provider in await sheet.reauthenticate(provider: provider, action: .twoFactorChange) }
        ))
    }

    /// For previews and tests: a model built elsewhere, and whether the app starts active (a
    /// test host never is, so its sheet would open covered).
    init(model: TwoStepModel, appActive: Bool = NSApplication.shared.isActive) {
        _model = State(initialValue: model)
        _appActive = State(initialValue: appActive)
    }

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    /// ⚠️ ONLY THE STEPS THAT HOLD A CREDENTIAL ARE COVERED: the overview has nothing to hide.
    static func covers(_ step: TwoStepModel.Step, appActive: Bool) -> Bool {
        !appActive && (step == .scan || step == .recoveryCodes)
    }

    /// ⛔ NOT PAST THE CODES: they are never shown again. Nor mid-request: the answer would land
    /// on a sheet nobody sees.
    static func canClose(_ step: TwoStepModel.Step, busy: Bool) -> Bool {
        !busy && step != .recoveryCodes
    }

    var body: some View {
        MacSheetChrome(title: TwoStepCopy.title) {
            ScrollView {
                VStack(alignment: .leading, spacing: DistrictSpacing.section) {
                    content
                }
                .padding(DistrictSpacing.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if Self.covers(model.step, appActive: appActive) {
                    cover
                }
            }
        } buttons: {
            buttons
        }
        .interactiveDismissDisabled(!Self.canClose(model.step, busy: model.busy))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appActive = true
        }
        .task { await model.load() }
        .onDisappear { model.leave() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.TwoStep.sheet)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .loading:
            card { SkeletonBlock(height: 72) }
        case .loadFailed:
            messageLines
        case .overview:
            messageLines
            statusCard
        case let .reauth(intent):
            messageLines
            methodsCard(intent)
        case let .password(_, needsCode):
            messageLines
            passwordCard(needsCode: needsCode)
        case .scan:
            // ⚠️ NO MESSAGE LINE ABOVE THE CARD HERE: the card is taller than the sheet, so a
            // refusal drawn above it is out of sight when Turn on is clicked. The card draws it
            // by the field.
            if let enrollment = model.enrollment {
                TwoStepScanCard(model: model, enrollment: enrollment)
            }
        case .recoveryCodes:
            TwoStepCodesCard(model: model)
        }
    }

    // ── On or off ────────────────────────────────────────────────────────────

    @ViewBuilder
    private var statusCard: some View {
        if let status = model.status {
            card {
                Text(status.enrolled ? TwoStepCopy.statusOn : TwoStepCopy.statusOff)
                    .font(DistrictType.title)
                    .foregroundStyle(colors.foreground)
                    .accessibilityIdentifier(A11yID.TwoStep.status)
                if status.enrolled {
                    if let since = status.enrolledAt {
                        paragraph(TwoStepCopy.onSince(WireDate.display(since)))
                    }
                    paragraph(status.backupCodesRemaining == 0
                        ? TwoStepCopy.codesNone
                        : TwoStepCopy.codesLeft(status.backupCodesRemaining))
                    if model.signsInWithoutPassword {
                        paragraph(TwoStepCopy.noPasswordNote)
                    }
                    Button(TwoStepCopy.turnOff) { model.begin(.turnOff) }
                        .buttonStyle(.districtDestructive)
                        .disabled(model.busy)
                        .accessibilityIdentifier(A11yID.TwoStep.turnOff)
                } else {
                    paragraph(TwoStepCopy.offExplain)
                    Button(TwoStepCopy.turnOn) { model.begin(.turnOn) }
                        .buttonStyle(.districtPrimary)
                        .disabled(model.busy)
                        .accessibilityIdentifier(A11yID.TwoStep.turnOn)
                }
            }
        }
    }

    // ── Confirm it is you ────────────────────────────────────────────────────

    private func methodsCard(_ intent: TwoStepModel.Intent) -> some View {
        card {
            DistrictEyebrow(text: DeleteAccountCopy.confirmItIsYou)
            paragraph(intent == .turnOn ? TwoStepCopy.reauthIntroOn : TwoStepCopy.reauthIntroOff)
            ForEach(ReauthProvider.allCases, id: \.self) { provider in
                Button(DeleteAccountCopy.continueWith(provider.displayName)) {
                    Task { await model.reauthenticate(with: provider) }
                }
                .buttonStyle(.districtSecondary)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.TwoStep.provider(provider.rawValue))
            }
            Button(DeleteAccountCopy.usePassword) {
                model.usePassword()
                focused = .password
            }
            .buttonStyle(.districtSecondary)
            .disabled(model.busy)
            .accessibilityIdentifier(A11yID.TwoStep.usePassword)
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
                .accessibilityIdentifier(A11yID.TwoStep.password)
            if needsCode {
                paragraph(MfaCopy.authenticatorPrompt)
                TextField(MfaCopy.authenticatorPlaceholder, text: $model.code)
                    // ⚠️ ONE FIELD FOR BOTH KINDS, as on the deletion sheet: an authenticator
                    // code or a recovery code.
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .districtField()
                    .focused($focused, equals: .code)
                    .disabled(model.busy)
                    .onSubmit(submitPassword)
                    .accessibilityIdentifier(A11yID.TwoStep.code)
            }
        }
    }

    // ── The button row ───────────────────────────────────────────────────────

    /// Back where a step has one, Close (Esc), then the step's own default button (Return).
    @ViewBuilder
    private var buttons: some View {
        if model.busy {
            ProgressView()
                .controlSize(.small)
        }
        switch model.step {
        case .reauth, .password, .scan:
            Button(DeleteAccountCopy.back, action: model.back)
                .buttonStyle(.districtGhost)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.TwoStep.back)
        case .loading, .loadFailed, .overview, .recoveryCodes:
            EmptyView()
        }
        if model.step != .recoveryCodes {
            Button(TwoStepCopy.close) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(!Self.canClose(model.step, busy: model.busy))
                .accessibilityIdentifier(A11yID.TwoStep.close)
        }
        defaultButton
    }

    @ViewBuilder
    private var defaultButton: some View {
        switch model.step {
        case .loadFailed:
            Button(TwoStepCopy.retry) { Task { await model.load() } }
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.TwoStep.retry)
        case .password:
            Button(DeleteAccountCopy.continueButton, action: submitPassword)
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmitPassword)
                .accessibilityIdentifier(A11yID.TwoStep.passwordContinue)
        case .scan:
            Button(TwoStepCopy.confirmButton) { Task { await model.confirm() } }
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canConfirm)
                .accessibilityIdentifier(A11yID.TwoStep.confirm)
        case .recoveryCodes:
            Button(TwoStepCopy.codesDone) { Task { await model.finishRecoveryCodes() } }
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.TwoStep.codesDone)
        case .loading, .overview, .reauth:
            EmptyView()
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────

    /// The notice of the last change, then the failure, each as one line.
    @ViewBuilder
    private var messageLines: some View {
        if let notice = model.notice {
            Text(notice)
                .font(DistrictType.bodySmall)
                .foregroundStyle(Tone.success.ink(colors))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(A11yID.TwoStep.notice)
        }
        if let failure = model.failure {
            Text(failure)
                .font(DistrictType.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Tone.warning.ink(colors))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(A11yID.TwoStep.message)
        }
    }

    private var cover: some View {
        ZStack {
            colors.background
            Image(systemName: "lock.fill")
                .font(DistrictType.title)
                .foregroundStyle(colors.mutedForeground)
                .accessibilityHidden(true)
        }
    }

    private func paragraph(_ text: String) -> some View {
        TwoStepParagraph(text: text)
    }

    private func card(@ViewBuilder rows: () -> some View) -> some View {
        TwoStepCard(rows: rows)
    }

    private func submitPassword() {
        Task { await model.submitPassword() }
    }
}
