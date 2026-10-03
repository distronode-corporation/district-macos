import SwiftUI

/// The app's Settings window (District AI > Settings..., ⌘,).
///
/// ⚠️ APP PREFERENCES ONLY. Workspace settings are a sidebar section, as on the iPad; this
/// window holds what belongs to this Mac: its notifications and, in the Developer ID
/// build, updates. Ringing on this Mac joins it in Wave 6.
struct SettingsView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar

    var body: some View {
        Form {
            Section("Notifications") {
                LabeledContent("Permission", value: AccountView.text(push.authorization))
                LabeledContent("Registration", value: AccountView.text(push.registration))
            }
            #if DEVELOPER_ID
                Section("Updates") {
                    AutomaticUpdatesToggle()
                }
            #endif
            Section("About") {
                LabeledContent("Version", value: AccountView.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
