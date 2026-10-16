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
///
/// ⛔ THE APP OUTLIVES ITS WINDOW. Closing the window leaves the app running behind its menu
/// bar item, ringing (``BackgroundRinging``), so nothing that rings may be wired from a
/// view: the delegate adopts the registrar and the call objects at launch, and
/// ``SessionModel/launch()`` checks the session and starts the ringing, with or without a
/// window.
@main
struct DistrictMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: AppContainer
    private let push: PushRegistrar
    private let incoming: IncomingCallModel
    private let live: DesktopLive
    private let ringPanel: RingPanelController
    private let ringPresenter: RingPresenter
    private let background: BackgroundRinging
    @State private var session: SessionModel

    init() {
        // Before anything else can crash. A no-op unless the build carries a DSN.
        DistrictSentry.startIfConfigured()

        // Before the container, so nothing it builds reads a string in the default
        // language before the device's is known: Canadian French on a Mac that puts French
        // first, English otherwise.
        AppL10n.bootstrap()

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
        // ⚠️ THE SERVER LEARNS THIS APP'S LANGUAGE on every sign-in and language change, so
        // email and the server's own text match it (`Accept-Language` rides every request).
        let settings = container.accountSettings
        let language = AccountLanguageSync(save: { await settings.saveLocale($0) })
        AppL10n.onChange = { language.languageChanged() }
        let session = SessionModel(
            container: container,
            push: push,
            live: live,
            incoming: incoming,
            language: language
        )
        _session = State(initialValue: session)
        background = BackgroundRinging()
        // ⛔ HANDED TO THE DELEGATE HERE, NOT FROM A WINDOW'S `onAppear`: a launch at login
        // may restore no window, and a notification's Answer, a quit with a call up and a
        // tapped notification all need these. The delegate adopts them when the app has
        // finished launching, which is after this initialiser.
        AppDelegate.launch = AppDelegate.Launch(
            registrar: push,
            calls: AppDelegate.Calls(incoming: incoming, presenter: presenter, live: live),
            session: session
        )
        #if DEBUG
            // ⚠️ A NO-OP OUTSIDE A SCREENSHOT RUN, AND ABSENT FROM RELEASE. ⛔ NOT A VIEW
            // MODIFIER: see `UITestWindowSize.swift` for the window that never opened.
            UITestWindowSizer.startIfRequested()
        #endif
    }

    var body: some Scene {
        // ⚠️ AN ID, SO THE MENU BAR ITEM CAN BRING THE WINDOW BACK AFTER IT WAS CLOSED.
        WindowGroup(id: MenuBarMenu.mainWindowId) {
            RootView(container: container, session: session, push: push, live: live)
                // ⚠️ WIDE ENOUGH FOR A LIST SECTION'S THREE COLUMNS: the sidebar, a sortable
                // table (Calls, Contacts) and the open row beside it (``ListColumnWidth``).
                // ⛔ EVERY SHEET IS SIZED TO FIT THIS HEIGHT (``MacSheetFit``): change it there.
                .frame(minWidth: ListColumnWidth.windowMin, minHeight: MacWindowSize.minHeight)
        }
        // ⚠️ A FIRST WINDOW WITH ROOM TO READ THE OPEN ROW, not the minimum: SwiftUI opened
        // the window at its 1000pt minimum, where the open call is the narrowest it may be.
        // The system clamps it to a smaller screen, and a window the person sized is restored
        // as they left it.
        .defaultSize(width: 1280, height: 800)
        .commands {
            // ⚠️ View > Show Sidebar / Hide Sidebar (⌃⌘S) is one of these, the shell's own.
            DistrictCommands(session: session)
        }

        Settings {
            SettingsView(container: container, session: session, push: push, live: live)
        }

        // ⛔ WHAT IS LEFT ON SCREEN WHEN THE WINDOW IS CLOSED AND THE APP KEEPS RINGING: Open
        // District AI, Open at Login, Quit. See ``BackgroundRinging``.
        MenuBarExtra(NavigationCopy.menuBarLabel, systemImage: "phone") {
            MenuBarMenu(background: background)
        }
    }
}
