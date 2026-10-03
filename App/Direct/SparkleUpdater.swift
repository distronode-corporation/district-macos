import Combine
import Sparkle
import SwiftUI

/// Sparkle, for the Developer ID build only.
///
/// ⛔ THIS DIRECTORY IS COMPILED INTO `DistrictMacDirect` AND NOTHING ELSE (project.yml),
/// and it is the only code that imports Sparkle. The App Store build cannot reference
/// the framework even by accident, and App Review rejects an app that contains it.
///
/// ⛔ ONE UPDATER PER PROCESS. The feed URL and the EdDSA public key come from Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`).
///
/// ⛔ NOT STARTED WHILE THE KEY IS STILL THE PLACEHOLDER. Measured on 2026-10-03: a build
/// carrying `REPLACE_WITH_SPARKLE_PUBLIC_KEY` that starts the updater shows Sparkle's
/// "Unable to Check For Updates" alert at every launch. Until the release key exists
/// (Wave 0d), the updater stays stopped, "Check for Updates..." stays disabled, and no
/// update can install, which is the safe failure.
@MainActor
enum DistrictUpdater {
    nonisolated static let placeholderKey = "REPLACE_WITH_SPARKLE_PUBLIC_KEY"

    static let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Called once at launch by the app delegate, in the Developer ID build only.
    static func startIfConfigured(bundle: Bundle = .main) {
        guard isConfigured(publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) else {
            return
        }
        controller.startUpdater()
    }

    nonisolated static func isConfigured(publicKey: String?) -> Bool {
        guard let key = publicKey?.trimmingCharacters(in: .whitespaces), !key.isEmpty else { return false }
        return key != placeholderKey
    }
}

/// Publishes `canCheckForUpdates`, so the menu item is disabled while a check runs.
@MainActor
final class UpdaterState: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var observation: AnyCancellable?

    init(updater: SPUUpdater = DistrictUpdater.controller.updater) {
        observation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }
}

/// District AI > Check for Updates...
struct CheckForUpdatesCommand: View {
    @StateObject private var state = UpdaterState()

    var body: some View {
        Button("Check for Updates...") {
            DistrictUpdater.controller.checkForUpdates(nil)
        }
        .disabled(!state.canCheckForUpdates)
    }
}

/// The Settings toggle for Sparkle's own automatic-check preference.
struct AutomaticUpdatesToggle: View {
    @State private var enabled = DistrictUpdater.controller.updater.automaticallyChecksForUpdates

    var body: some View {
        // ⚠️ A SWITCH, as "Ring on this computer" above it is: one window, one control.
        Toggle("Check for updates automatically", isOn: $enabled)
            .toggleStyle(.switch)
            .onChange(of: enabled) { _, value in
                DistrictUpdater.controller.updater.automaticallyChecksForUpdates = value
            }
    }
}
