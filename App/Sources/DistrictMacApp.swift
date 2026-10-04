import SwiftUI

/// District AI for Mac.
///
/// ⛔ ONE `AppContainer` FOR THE PROCESS, built here and passed down: it holds the only
/// `TokenRefreshCoordinator` (see the type). `WindowGroup` can open more windows; each
/// shares this container, so they share one session.
///
/// ⛔ AND ONE OF EACH LIVE-CALL OBJECT, BUILT BESIDE IT, BECAUSE A RING AND A CALL OUTLIVE
/// EVERY VIEW: the ``IncomingCallModel`` (a ring can arrive while any section is on
/// screen), its ``RingPanelController`` (the call's own window), and ``DesktopLive`` (the
/// socket and presence that make this Mac ring at all).
@main
struct DistrictMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: AppContainer
    private let push: PushRegistrar
    private let incoming: IncomingCallModel
    private let live: DesktopLive
    private let ringPanel: RingPanelController
    private let ringPresenter: RingPresenter
    @State private var session: SessionModel

    init() {
        // Before anything else can crash. A no-op unless the build carries a DSN.
        DistrictSentry.startIfConfigured()
        let container = AppContainer.live()
        let push = PushRegistrar(container: container)
        let presenter = RingPresenter()
        let incoming = IncomingCallModel(container: container, presenter: presenter)
        let live = DesktopLive(
            calls: container.callStack,
            factory: DesktopLiveSession.factory(container: container, ring: incoming)
        )
        // ⚠️ THE MODEL TELLS THE GATE WHEN IT IS DONE WITH A RING, so a second call can ring
        // straight after a decline rather than waiting out the first one's thirty seconds.
        incoming.onRingSettled = { [weak live] in live?.ringSettled() }
        self.container = container
        self.push = push
        self.incoming = incoming
        self.live = live
        ringPresenter = presenter
        ringPanel = RingPanelController(model: incoming, devices: container.callStack.devices)
        _session = State(initialValue: SessionModel(container: container, push: push, live: live))
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container, session: session, push: push, live: live, incoming: incoming)
                // ⚠️ WIDE ENOUGH FOR A LIST SECTION'S THREE COLUMNS: the sidebar, a sortable
                // table (Calls, Contacts) and the open row beside it.
                .frame(minWidth: 1000, minHeight: 560)
                // ⚠️ A NO-OP OUTSIDE A SCREENSHOT RUN, AND ABSENT FROM RELEASE (`UITestWindowSize.swift`).
                .uiTestWindowSize()
                // ⚠️ On EVERY launch, signed in or not: a sign-out whose revoke failed
                // last time is retried here.
                .task { await container.drainPendingRevoke() }
                .onAppear {
                    appDelegate.adopt(registrar: push)
                    appDelegate.adopt(calls: AppDelegate.Calls(
                        incoming: incoming,
                        presenter: ringPresenter,
                        live: live
                    ))
                }
        }
        .commands {
            // ⚠️ View > Show Sidebar / Hide Sidebar (⌃⌘S) is one of these, the shell's own.
            DistrictCommands(session: session)
        }

        Settings {
            SettingsView(container: container, session: session, push: push, live: live)
        }
    }
}
