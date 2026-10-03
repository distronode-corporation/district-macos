import SwiftUI

/// The app's Settings window (District AI > Settings..., ⌘,).
///
/// ⛔ THIS INSTALLATION'S PREFERENCES ONLY, AND NOTHING THE SERVER STORES. The split with
/// the sidebar's Workspace settings (the iPad's hub, `SettingsHubView`) is by owner: that
/// section edits one WORKSPACE (persona, capabilities, call handling, directory, routing,
/// knowledge, messaging, members) and is the same for every device signed in to it; this
/// window holds what belongs to THIS MAC and is kept in its own defaults: whether calls
/// ring here and on which microphone and speaker, its notifications and, in the Developer
/// ID build, updates. Neither repeats the other. ⚠️ Account's "Calls to you" (whether THIS
/// PERSON can be rung, a server-side membership flag) stays in Account, as on the iPad;
/// "Ring on this computer" decides whether this Mac rings when they can.
///
/// ⚠️ THE NOTIFICATIONS LINE IS ACCOUNT'S (``PushStatusCopy``), word for word, so the two
/// places that report it cannot disagree.
struct SettingsView: View {
    let container: AppContainer
    let session: SessionModel
    let push: PushRegistrar
    let live: DesktopLive

    var body: some View {
        Form {
            Section("Calls") {
                RingHereToggle(live: live)
                AudioDevicePickers(devices: container.callStack.devices)
            }
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
        .districtTheme()
    }

    /// `MARKETING_VERSION (CURRENT_PROJECT_VERSION)`, read from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
