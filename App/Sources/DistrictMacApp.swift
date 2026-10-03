import SwiftUI

/// District AI for Mac.
///
/// ⛔ ONE `AppContainer` FOR THE PROCESS, built here and passed down: it holds the only
/// `TokenRefreshCoordinator` (see the type). `WindowGroup` can open more windows; each
/// shares this container, so they share one session.
@main
struct DistrictMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: AppContainer
    private let push: PushRegistrar
    @State private var session: SessionModel

    init() {
        // Before anything else can crash. A no-op unless the build carries a DSN.
        DistrictSentry.startIfConfigured()
        let container = AppContainer()
        let push = PushRegistrar(container: container)
        self.container = container
        self.push = push
        _session = State(initialValue: SessionModel(container: container, push: push))
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container, session: session, push: push)
                .frame(minWidth: 820, minHeight: 520)
                // ⚠️ On EVERY launch, signed in or not: a sign-out whose revoke failed
                // last time is retried here.
                .task { await container.drainPendingRevoke() }
                .onAppear { appDelegate.adopt(registrar: push) }
        }
        .commands {
            DistrictCommands(session: session)
        }

        Settings {
            SettingsView(container: container, session: session, push: push)
        }
    }
}
