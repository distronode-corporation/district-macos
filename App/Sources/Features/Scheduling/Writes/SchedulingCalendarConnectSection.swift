import AppKit
import DistrictModel
import SwiftUI

/// The Connect controls for the two OAuth calendar providers.
///
/// ⛔ THE SECOND OF THE TWO WAYS OUT OF THE APP ON THIS SURFACE, AS ON iOS, which
/// opens the provider's consent in an in-app Safari sheet. A Mac has no in-app browser
/// (and the providers refuse an embedded web view), so the hand-off URL opens in the
/// default browser, named (``BrowserHandOff``), and is kept nowhere: it carries a
/// 60-second single-use token, so it is opened the moment it is answered.
///
/// ⛔ AND A NEW ONE IS MINTED PER PRESS. The code is single-use and lives about
/// sixty seconds, so a cached one is stale exactly when somebody needs it.
///
/// ⚠️ THE APP IS NOT TOLD WHAT HAPPENED IN THE BROWSER. The provider's callback
/// appends `calendar=connected` or `calendar=error` to a page this process never
/// sees. iOS re-reads when its sheet is dismissed; the Mac re-reads when the app
/// becomes active again after a hand-off (the person coming back, as the note above the
/// buttons asks), and the status is what says which accounts are connected.
struct SchedulingCalendarConnectSection: View {
    let model: SchedulingCalendarConnectModel
    let status: SchedulingCalendarStatus

    /// A hand-off went to the browser and the app has not been brought back since.
    @State private var awaitingReturn = false

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    private var providers: [String] {
        SchedulingCalendarConnectModel.offeredProviders(status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.row) {
            content
            if let failure = model.failure {
                SchedulingWriteFailureLine(failure: failure, onDismiss: model.dismissFailure)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ⚠️ APPKIT POSTS `didBecomeActive` ON THE MAIN THREAD, so this closure runs where
        // its main-actor isolation says it does; no Apple API is handed a callback here.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard awaitingReturn else { return }
            awaitingReturn = false
            model.handOffFinished()
        }
    }

    @ViewBuilder
    private var content: some View {
        if providers.isEmpty {
            // ⚠️ ONE SENTENCE AND NO CONTROL. An instance with no calendar
            // credentials cannot be fixed from a phone, and a button that could only
            // fail is worse than none.
            Text(SchedulingWriteCopyC.connectNotConfigured)
                .font(DistrictType.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        } else {
            Text(SchedulingWriteCopyC.connectHandOffNote)
                .font(DistrictType.caption)
                .foregroundStyle(colors.mutedForeground)
            ForEach(providers, id: \.self) { provider in
                Button(SchedulingWriteCopyC.connectProvider(provider)) {
                    connect(provider)
                }
                .buttonStyle(.districtSecondary)
                .disabled(model.busy)
                .accessibilityIdentifier(A11yID.SchedulingCalendarWrites.connect(provider))
            }
        }
    }

    private func connect(_ provider: String) {
        Task {
            guard let url = await model.connect(provider: provider) else { return }
            awaitingReturn = BrowserHandOff.open(url)
        }
    }
}
