import AppKit
import DistrictNetwork
import Observation
import SwiftUI

/// The S33 bound hand-off into the scheduler's admin, in the user's default browser.
///
/// ⛔ ALL THREE LEGS USE THE DEFAULT BROWSER, AND THAT IS THE BINDING. Leg 1
/// (`/dashboard/handoff/start?state=...`) opens there with `NSWorkspace.open`, so the
/// website's session cookie is that browser's; its redirect to `districtai://handoff`
/// comes back through Launch Services to `.onOpenURL` (RootView), which hands it to the
/// one ``SchedulingHandoffFlow``; leg 3 opens the minted URL in the same browser, which
/// therefore already holds the cookie the nonce was bound to.
///
/// ⚠️ THE MAC CANNOT SEE THE BROWSER, unlike iOS's `SFSafariViewController`: it never
/// learns that leg 1 rendered a page instead of redirecting, or that the tab was closed.
/// The flow's own timeout (``SchedulingHandoffFlow/callbackTimeout``, 10 seconds) is the
/// only signal, and it falls back to the unbound mint, which is what iOS does on a
/// rendered page too.
@MainActor
@Observable
final class SchedulingHandoffModel {
    private(set) var opening = false
    private(set) var notice: String?

    private let flow: SchedulingHandoffFlow
    private let workspaceId: String

    init(container: AppContainer, workspaceId: String) {
        flow = container.schedulingHandoffFlow
        self.workspaceId = workspaceId
    }

    /// ⛔ RE-MINTED ON EVERY PRESS, NEVER CACHED: the code is single-use and short-lived.
    func manageScheduling() async {
        guard !opening else { return }
        opening = true
        notice = nil
        let outcome = await flow.run(workspaceId: workspaceId) { url, _ in
            NSWorkspace.shared.open(url)
        }
        opening = false
        switch outcome {
        case let .minted(handoff):
            NSWorkspace.shared.open(handoff.url)
        case let .failed(failure):
            notice = Self.notice(for: failure)
        case .alreadyPending, .abandoned:
            break
        }
    }

    /// The iOS app's sentences (`SchedulingModel.handOffNotice`, `SchedulingCopy`).
    /// ⚠️ The server's own `nonce_required` sentence wins whenever it sends one.
    nonisolated static func notice(for failure: SchedulingHandoffFailure) -> String {
        switch failure {
        case let .nonceRequired(message): message ?? "Update the app to open the website from it."
        case .invalidNonce: "The website could not be opened. Try again."
        case .api(.http(status: 409, message: _)):
            "Scheduling is not ready yet. Turn it on, or wait for setup to finish."
        case let .api(error): FailureText.from(error).message
        }
    }
}

struct SchedulingHandoffView: View {
    @State private var model: SchedulingHandoffModel

    init(container: AppContainer, workspaceId: String) {
        _model = State(initialValue: SchedulingHandoffModel(container: container, workspaceId: workspaceId))
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: SidebarItem.scheduling.symbol)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(SidebarItem.scheduling.title)
                .font(.title2.weight(.semibold))
            Text(ComingLaterView.caption)
                .foregroundStyle(.secondary)
            Button("Manage scheduling in your browser") {
                Task { await model.manageScheduling() }
            }
            .disabled(model.opening)
            if model.opening {
                ProgressView().controlSize(.small)
            }
            if let notice = model.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
