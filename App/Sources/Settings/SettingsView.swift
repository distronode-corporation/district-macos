import SwiftUI

/// The app's Settings window (District AI > Settings..., ⌘,).
///
/// ⚠️ APP PREFERENCES ONLY. Workspace settings are a sidebar section, as on the iPad; this
/// window holds what belongs to this Mac: its notifications and, in the Developer ID
/// build, updates. Ringing on this Mac joins it in Wave 6.
///
/// ⚠️ THE NOTIFICATIONS LINE IS ACCOUNT'S (``PushStatusCopy``), word for word, so the two
/// places that report it cannot disagree.
struct SettingsView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar

    var body: some View {
        Form {
            Section(PushStatusCopy.title) {
                Text(PushStatusCopy.subtitle(authorization: push.authorization, registration: push.registration))
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if DEVELOPER_ID
                Section("Updates") {
                    AutomaticUpdatesToggle()
                }
            #endif
            Section("About") {
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }

    /// `MARKETING_VERSION (CURRENT_PROJECT_VERSION)`, read from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
