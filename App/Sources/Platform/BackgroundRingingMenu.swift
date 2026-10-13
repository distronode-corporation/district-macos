import AppKit
import SwiftUI

/// SPIKE (spike/v3-mac-voip, not for merge): the menu bar item that stands for the app
/// while its window is closed. See ``BackgroundRinging``.
struct BackgroundRingingMenu: View {
    static let mainWindowId = "main"

    @Environment(\.openWindow) private var openWindow
    @State private var opensAtLogin = BackgroundRinging.opensAtLogin

    var body: some View {
        Button("Open District AI") {
            openWindow(id: Self.mainWindowId)
            NSApplication.shared.activate()
        }
        Toggle("Open at Login", isOn: $opensAtLogin)
            .onChange(of: opensAtLogin) { _, enabled in
                BackgroundRinging.setOpensAtLogin(enabled)
                opensAtLogin = BackgroundRinging.opensAtLogin
            }
        Divider()
        Button("Quit District AI") {
            NSApplication.shared.terminate(nil)
        }
    }
}
