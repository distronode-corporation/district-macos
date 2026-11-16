import AppKit
import DistrictData
import DistrictModel
import SwiftUI

/// The setup wizard, as a sheet over the overview: the web's six steps, in its order and
/// with its words, most of them run here (see ``SetupWizardModel``). Ported from district-ios.
///
/// ⚠️ A SHEET, NOT A ``Route``, as ``DeleteAccountView`` is: the flow is modal, and a restored
/// back stack must never land a person in its middle. Where they left off is the service's
/// to say (``SetupFlow/firstOpen(_:)``).
///
/// ⚠️ DRAWN IN ``MacSheetChrome``, where iOS has a `NavigationStack` with Finish later in its
/// toolbar and Back and Skip under the step. The three moves that mean the same on every
/// step are the bottom row here: Back, Skip and Finish later (Esc), each in one treatment
/// (``ButtonStyle/districtSecondary``) and one height, as on the deletion and two-step
/// sheets. A step's own primary action is a save whose shape only the step knows, so each
/// step draws it, as on iOS (the web replaces Cloudscape's Next the same way); some steps
/// have more than one, which is why none of them takes Return.
///
/// ⛔ A PAGE HANDED TO THE WEB OPENS IN THE DEFAULT BROWSER (``SetupHandOff``), and the wizard
/// reads its state again when the app becomes active after it, where iOS reads it when its
/// Safari sheet closes.
struct SetupWizardView: View {
    @State private var model: SetupWizardModel
    /// A page went to the browser and the app has not been brought back since.
    @State private var awaitingReturn = false

    private let container: AppContainer
    private let onRenamed: () -> Void
    private let onClose: () -> Void

    init(
        container: AppContainer,
        workspaceId: String,
        workspaceName: String,
        onRenamed: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: SetupWizardModel(
            container: container,
            workspaceId: workspaceId,
            workspaceName: workspaceName
        ))
        self.container = container
        self.onRenamed = onRenamed
        self.onClose = onClose
    }

    /// For previews and tests: a model built elsewhere (its storefront among what it was given).
    init(model: SetupWizardModel, container: AppContainer, onClose: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.container = container
        onRenamed = {}
        self.onClose = onClose
    }

    private static let top = "district-setup-top"

    var body: some View {
        MacSheetChrome(title: SetupCopy.title) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DistrictSpacing.section) {
                        content
                    }
                    .id(Self.top)
                    .padding(DistrictSpacing.gutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // ⚠️ A NEW STEP OPENS AT ITS TOP, not wherever the last one was scrolled to.
                .onChange(of: model.active) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        } buttons: {
            buttons
        }
        // ⚠️ NO CLOSE MID-WRITE: the answer would land on a sheet nobody sees.
        .interactiveDismissDisabled(model.isMoving)
        .task { await model.load() }
        // ⚠️ APPKIT POSTS `didBecomeActive` ON THE MAIN THREAD, so this closure runs where its
        // main-actor isolation says it does.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard awaitingReturn else { return }
            awaitingReturn = false
            Task { await model.refreshAfterHandOff() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Setup.root)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView(message: SetupCopy.loading)
                .accessibilityIdentifier(A11yID.Setup.loading)
        case let .refused(refusal):
            ending(
                symbol: "person.badge.key",
                title: refusal == .notOwner ? SetupCopy.notOwnerTitle : SetupCopy.notAvailableTitle,
                message: refusal == .notOwner ? SetupCopy.notOwnerBody : SetupCopy.notAvailableBody,
                identifier: A11yID.Setup.refused
            )
        case let .failed(failure):
            FailureView(failure: failure, onRetry: { Task { await model.load() } })
                .accessibilityIdentifier(A11yID.Setup.failed)
        case .finished:
            ending(
                symbol: "checkmark.circle",
                title: SetupCopy.finishedTitle,
                message: SetupCopy.finishedBody,
                identifier: A11yID.Setup.finished
            )
        case .ready:
            SetupProgressHeader(model: model)
            step
                .id(model.active)
            if let error = model.stepError {
                SetupErrorLine(text: error.message)
                    .accessibilityIdentifier(A11yID.Setup.stepError)
            }
        }
    }

    /// ⚠️ ITS DONE IS THE BOTTOM ROW'S DEFAULT BUTTON (``buttons``), not under the sentence as
    /// on iOS: a Mac sheet's way out is in one place.
    private func ending(symbol: String, title: String, message: String, identifier: String) -> some View {
        EmptyStateView(systemImage: symbol, title: title, message: message)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var step: some View {
        let open: (URL) -> Void = { url in
            // ⚠️ ONLY A PAGE THAT OPENED IS WAITED FOR: with no browser for `https` nothing opens.
            if BrowserHandOff.open(url) {
                awaitingReturn = true
            }
        }
        switch model.active {
        case .business:
            SetupBusinessStep(wizard: model, container: container, open: open, onRenamed: onRenamed)
        case .number:
            SetupNumberStep(wizard: model, baseURL: container.baseURL, open: open)
        case .receptionist:
            SetupReceptionistStep(wizard: model, container: container)
        case .callers:
            SetupCallersStep(wizard: model)
        case .calls:
            SetupCallsStep(wizard: model, container: container, open: open)
        case .golive:
            SetupGoLiveStep(wizard: model, container: container)
        }
    }

    /// Back and Skip, the two moves every step shares, then Finish later (Esc); or Done (Return)
    /// once there is nothing left to do here.
    ///
    /// ⛔ ONE HEIGHT AND ONE TREATMENT FOR EVERY MOVE IN THE ROW (visual QA, #111 and #112): a bare
    /// button is drawn by macOS as a small bezel pill and a ghost one as plain text, so Back, Skip
    /// and Finish later all take ``ButtonStyle/districtSecondary``, and Done takes
    /// ``View/macSheetDefaultButton()``. `MacSetupWizardTests` pins it.
    @ViewBuilder
    private var buttons: some View {
        if model.isMoving {
            ProgressView()
                .controlSize(.small)
        }
        switch model.phase {
        case .refused, .finished:
            Button(SetupCopy.done, action: onClose)
                .macSheetDefaultButton()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(A11yID.Setup.done)
        case .ready:
            if SetupFlow.previous(before: model.active) != nil {
                Button(SetupCopy.back) { model.back() }
                    .buttonStyle(.districtSecondary)
                    .disabled(model.isMoving)
                    .accessibilityIdentifier(A11yID.Setup.back)
            }
            Button(SetupCopy.skipStep) { Task { await model.skip() } }
                .buttonStyle(.districtSecondary)
                .disabled(model.isMoving)
                .accessibilityIdentifier(A11yID.Setup.skip)
            finishLater
        case .loading, .failed:
            finishLater
        }
    }

    private var finishLater: some View {
        Button(SetupCopy.finishLater, action: onClose)
            .buttonStyle(.districtSecondary)
            .keyboardShortcut(.cancelAction)
            .disabled(model.isMoving)
            .accessibilityIdentifier(A11yID.Setup.finishLater)
    }
}

/// "Step n of 6", a segment per step, and the step's title and description.
///
/// ⚠️ THE SEGMENTS ARE ONE ACCESSIBILITY ELEMENT whose value is the sentence, and each
/// step's state is said in words, never only by its colour.
struct SetupProgressHeader: View {
    let model: SetupWizardModel

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        let position = SetupFlow.position(of: model.active) + 1
        VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
            HStack(spacing: DistrictSpacing.hairline) {
                ForEach(SetupFlow.steps, id: \.self) { step in
                    Capsule()
                        .fill(fill(step))
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SetupCopy.progressLabel)
            .accessibilityValue(spokenProgress)
            .accessibilityIdentifier(A11yID.Setup.progress)
            Text(SetupCopy.stepOf(position, SetupFlow.steps.count))
                .font(DistrictType.label)
                .foregroundStyle(colors.mutedForeground)
                .accessibilityHidden(true)
            Text(SetupFlow.title(model.active))
                .font(DistrictType.headline)
                .foregroundStyle(colors.foreground)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(SetupCopy.stepOf(position, SetupFlow.steps.count) + ", " + SetupFlow
                    .title(model.active))
            SetupNote(text: SetupFlow.description(model.active))
        }
    }

    private func fill(_ step: SetupStep) -> Color {
        if step == model.active {
            return colors.district
        }
        switch model.state(of: step) {
        case .done: return colors.success
        case .skipped: return colors.mutedForeground.opacity(0.5)
        default: return colors.border
        }
    }

    private var spokenProgress: String {
        SetupFlow.steps.map { step in
            let word: String = if step == model.active {
                SetupCopy.stepCurrent
            } else {
                switch model.state(of: step) {
                case .done: SetupCopy.stepDone
                case .skipped: SetupCopy.stepSkipped
                default: SetupCopy.stepTodo
                }
            }
            return SetupFlow.title(step) + ": " + word
        }
        .joined(separator: ", ")
    }
}

/// Which workspace the wizard sheet is open for, and whether step 1 renamed it.
///
/// ⚠️ A CLASS, so the flag set inside the sheet is still readable in its `onDismiss`.
@MainActor
final class SetupWizardTarget: Identifiable {
    let workspaceId: String
    let workspaceName: String
    var renamed = false

    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    init(workspaceId: String, workspaceName: String) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
    }
}

/// Presents the wizard for a target, and tidies up after it closes.
///
/// ⚠️ THE WORKSPACE LIST IS READ AGAIN ONLY AFTER A RENAME: a reload takes the whole shell
/// through its loading state, which a close with nothing renamed must not cost. The card is
/// always asked again, because a finished wizard retires it.
private struct SetupWizardSheet: ViewModifier {
    @Binding var target: SetupWizardTarget?
    let container: AppContainer
    let workspaceSession: WorkspaceSessionModel
    let card: FinishSetupModel

    /// The target, kept past the sheet's close so `onDismiss` can read whether it renamed.
    @State private var last: SetupWizardTarget?

    func body(content: Content) -> some View {
        content
            .onChange(of: target?.id) {
                if let target {
                    last = target
                }
            }
            .sheet(item: $target, onDismiss: closed, content: { target in
                SetupWizardView(
                    container: container,
                    workspaceId: target.workspaceId,
                    workspaceName: target.workspaceName,
                    onRenamed: { target.renamed = true },
                    onClose: { self.target = nil }
                )
                .macSheetSize(width: 640, height: MacSheetFit.maxHeight)
            })
    }

    private func closed() {
        let renamed = last?.renamed == true
        last = nil
        Task {
            if renamed {
                await workspaceSession.load()
            }
            if let workspaceId = workspaceSession.workspaceId {
                await card.refresh(workspaceId: workspaceId)
            }
        }
    }
}

extension View {
    func setupWizardSheet(
        _ target: Binding<SetupWizardTarget?>,
        container: AppContainer,
        workspaceSession: WorkspaceSessionModel,
        card: FinishSetupModel
    ) -> some View {
        modifier(SetupWizardSheet(target: target, container: container, workspaceSession: workspaceSession, card: card))
    }
}
