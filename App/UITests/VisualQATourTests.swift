import AppKit
import XCTest

/// Visual and style QA only, never merged: the app walked over the contract fixtures (and,
/// in French, the fictional Québec sample data) served by `qa/mock_server.py`, captured as
/// attachments named `<tag>__<NN>-<screen>` with the accessibility tree beside each frame.
/// One test method per configuration (language, appearance, window size), so a tag cannot
/// name the wrong one. Adapted from the v3 French tour (run 38662580001); it adds English,
/// dark appearance, a wide window, and the empty, error and loading states the mock
/// produces (`QA_MODE`).
final class VisualQATourTests: XCTestCase {
    private var app: XCUIApplication!
    private var tag = "fr-CA-light"
    private var language = "fr-CA"
    private var locale = "fr_CA"
    private var dark = false
    private var window = "1000x700"
    private var openPrefix = "Ouvrir"
    private var reached: [String] = []
    private var missed: [String] = []

    private static let session = """
    {"tokenType":"Bearer","accessToken":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.\
    eyJzdWIiOiJ1c2VyLWNvbnRyYWN0IiwiZGlkIjoicWEtdzQtZGV2aWNlIiwiZXhwIjo0MTAyNDQ0ODAwfQ.cWEtdzQ",\
    "accessTokenExpiresAt":4102444800000,"refreshToken":"qa-w4-refresh",\
    "refreshTokenExpiresAt":4102444800000,"deviceId":"qa-w4-device"}
    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
    }

    // MARK: - Configurations

    @MainActor func test_01_enUS_light() {
        full(language: "en-US", locale: "en_US", dark: false, window: "1000x700", tag: "en-US-light")
    }

    @MainActor func test_02_frCA_light() {
        full(language: "fr-CA", locale: "fr_CA", dark: false, window: "1000x700", tag: "fr-CA-light")
    }

    @MainActor func test_03_enUS_dark() {
        full(language: "en-US", locale: "en_US", dark: true, window: "1000x700", tag: "en-US-dark")
    }

    @MainActor func test_04_frCA_dark() {
        full(language: "fr-CA", locale: "fr_CA", dark: true, window: "1000x700", tag: "fr-CA-dark")
    }

    /// The store window size, to see how each screen uses a wide window.
    @MainActor func test_05_frCA_wide() {
        full(language: "fr-CA", locale: "fr_CA", dark: false, window: "1440x900", tag: "fr-CA-light-wide")
    }

    /// A common laptop window (1280x800), on a runner whose display was set to hold it.
    @MainActor func test_14_enUS_1280() {
        full(language: "en-US", locale: "en_US", dark: false, window: "1280x800", tag: "en-US-light-1280")
    }

    @MainActor func test_15_frCA_1280() {
        full(language: "fr-CA", locale: "fr_CA", dark: false, window: "1280x800", tag: "fr-CA-light-1280")
    }

    /// With QA_MODE=empty, error or slow on the mock, the principal sections only.
    @MainActor func test_06_enUS_empty() {
        states(tag: "en-US-light-empty")
    }

    @MainActor func test_07_enUS_error() {
        states(tag: "en-US-light-error")
    }

    @MainActor func test_08_enUS_loading() {
        states(tag: "en-US-light-loading", settle: 1.0)
    }

    @MainActor func test_09_frCA_empty() {
        states(tag: "fr-CA-light-empty", language: "fr-CA", locale: "fr_CA")
    }

    /// The ring panel, after the workflow arms the mock's ring.
    @MainActor func test_10_ring_frCA() {
        ring(language: "fr-CA", locale: "fr_CA", answer: "Répondre", tag: "fr-CA-ring")
    }

    @MainActor func test_11_ring_enUS() {
        ring(language: "en-US", locale: "en_US", answer: "Answer", tag: "en-US-ring")
    }

    @MainActor func test_12_ring_frCA_dark() {
        ring(language: "fr-CA", locale: "fr_CA", answer: "Répondre", tag: "fr-CA-dark-ring", dark: true)
    }

    @MainActor func test_13_ring_enUS_dark() {
        ring(language: "en-US", locale: "en_US", answer: "Answer", tag: "en-US-dark-ring", dark: true)
    }

    // MARK: - The walks

    private var settleTime: TimeInterval = 2.5

    @MainActor private func configure(language: String, locale: String, dark: Bool, window: String, tag: String) {
        self.language = language
        self.locale = locale
        self.dark = dark
        self.window = window
        self.tag = tag
        openPrefix = language.hasPrefix("fr") ? "Ouvrir" : "Open"
    }

    @MainActor private func states(tag: String, language: String = "en-US", locale: String = "en_US",
                                   settle: TimeInterval = 2.5) {
        configure(language: language, locale: locale, dark: false, window: "1000x700", tag: tag)
        settleTime = settle
        guard launch() else { return }
        capture("01-overview")
        let rows: [(String, String)] = [
            (SidebarIDs.inbox, "02-inbox"), (SidebarIDs.calls, "06-calls"), (SidebarIDs.contacts, "10-contacts"),
            (SidebarIDs.account, "12-account"), (SidebarIDs.hq, "14-hq"), (SidebarIDs.analytics, "15-analytics"),
            (SidebarIDs.marketplace, "16-numbers"), (SidebarIDs.billing, "18-billing"), (SidebarIDs.rooms, "19-rooms"),
            (SidebarIDs.workflows, "20-workflows"), (SidebarIDs.desk, "21-desk"), (SidebarIDs.scheduling, "25-scheduling"),
            (SidebarIDs.support, "40-support"), (SidebarIDs.settings, "42-settings"),
        ]
        for (row, name) in rows where go(row) {
            capture(name)
        }
        report()
        app.terminate()
    }

    @MainActor private func full(language: String, locale: String, dark: Bool, window: String, tag: String) {
        configure(language: language, locale: locale, dark: dark, window: window, tag: tag)
        walk()
    }

    @MainActor private func walk() {
        signedOut()
        guard launch() else { return }
        capture("01-overview")
        scrollCapture("01b-overview")
        menus()
        menuBarItem()

        if go(SidebarIDs.inbox) {
            capture("02-inbox")
            if openFirst(prefix: "district-inbox-row") {
                capture("03-thread")
                if tapID("district-thread-menu") {
                    capture("04-thread-menu")
                    if tapID("district-thread-report") {
                        capture("05-report")
                        if !tapID("district-report-cancel") { escape() }
                    } else {
                        escape()
                    }
                }
            }
        }
        if go(SidebarIDs.calls) {
            capture("06-calls")
            captureElement(app.tables.firstMatch, "06c-calls-table")
            captureElement(app.outlines.firstMatch, "06d-calls-outline")
            if openFirst(prefix: "district-call-row") {
                capture("07-call-detail")
                scrollCapture("07b-call-detail")
                if tapID("district-call-detail-show-transcript") { capture("08-call-transcript") }
            }
        }
        if go(SidebarIDs.contacts) {
            capture("10-contacts")
            if openFirst(prefix: "district-contact-row") {
                capture("11-contact")
                scrollCapture("11b-contact")
            }
        }
        if go(SidebarIDs.account) {
            capture("12-account")
            scrollCapture("12b-account")
            if tapID("district-account-devices") { capture("13-devices") }
        }
        simple(SidebarIDs.hq, "14-hq")
        simple(SidebarIDs.analytics, "15-analytics", scrolls: 2)
        if go(SidebarIDs.marketplace) {
            capture("16-numbers")
            scrollCapture("16b-numbers")
            if openFirst(prefix: "district-marketplace-number-row") {
                capture("17-number-actions")
                escape()
            }
        }
        simple(SidebarIDs.billing, "18-billing", scrolls: 3)
        simple(SidebarIDs.rooms, "19-rooms")
        simple(SidebarIDs.workflows, "20-workflows", scrolls: 1)
        if go(SidebarIDs.desk) {
            capture("21-desk")
            if openButton(containing: "Reschedule Thursday") || openButton(containing: "jeudi") {
                capture("22-ticket")
                scrollCapture("22b-ticket")
            }
            if tapID("district-desk-new-ticket") {
                capture("23-new-ticket")
                if !tapID("district-desk-compose-cancel") { escape() }
            }
        }
        simple(SidebarIDs.dialer, "24-dialer")
        scheduling()
        if launch(), go(SidebarIDs.support) {
            capture("40-support")
            if openButton(containing: "Outbound calls failing") || openButton(containing: "Appels sortants") {
                capture("41-support-thread")
                scrollCapture("41b-support-thread")
            }
        }
        settings()
        report()
        app.terminate()
    }

    /// The ring panel: the mock, armed by the workflow before this test, rings every open
    /// telemetry socket for the contract caller, and the panel is its own window.
    @MainActor private func ring(language: String, locale: String, answer label: String, tag: String, dark: Bool = false) {
        configure(language: language, locale: locale, dark: dark, window: "1000x700", tag: tag)
        guard launch() else { return }
        capture("70-ring-shell")
        let answer = app.buttons.matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
        if answer.waitForExistence(timeout: 90) {
            Thread.sleep(forTimeInterval: 1.5)
            captureScreen("71-ring-panel")
            let panel = app.windows.matching(NSPredicate(format: "identifier != 'main-AppWindow-1'")).firstMatch
            if panel.exists { captureElement(panel, "71b-ring-panel-window") }
        } else {
            missed.append("ring-panel")
            captureScreen("71-no-ring")
        }
        report()
        app.terminate()
    }

    @MainActor private func simple(_ row: String, _ name: String, scrolls: Int = 0) {
        guard go(row) else { return }
        capture(name)
        let letters = ["b", "c", "d", "e"]
        for index in 0 ..< scrolls {
            scrollCapture(name.replacingOccurrences(
                of: "-", with: "\(letters[index])-", options: [], range: name.range(of: "-")
            ))
        }
    }

    @MainActor private func scheduling() {
        guard launch(), go(SidebarIDs.scheduling) else { return }
        capture("25-scheduling")
        scrollCapture("25b-scheduling")
        let sections = ["overview", "event-types", "hours", "bookings", "calendar", "team", "settings", "developer"]
        for (index, segment) in sections.enumerated() {
            let number = 26 + index
            guard launch(), go(SidebarIDs.scheduling) else { return }
            guard tapID("district-scheduling-section-\(segment)") else { continue }
            capture("\(number)-sched-\(segment)")
            scrollCapture("\(number)b-sched-\(segment)")
            switch segment {
            case "event-types":
                if openFirst(prefix: "district-scheduling-event-type-row") { capture("\(number)c-sched-event-type") }
            case "bookings":
                if openFirst(prefix: "district-scheduling-booking-row") { capture("\(number)c-sched-booking") }
            case "team":
                if tapID("district-scheduling-entry-user-archive") {
                    capture("\(number)c-sched-archive")
                    escape()
                }
            case "settings":
                tabs(prefix: "district-scheduling-settings-tab", number: number)
            case "developer":
                tabs(prefix: "district-scheduling-developer-tab", number: number)
            default:
                break
            }
        }
    }

    @MainActor private func tabs(prefix: String, number: Int) {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix + "-"))
        let count = min(query.count, 6)
        guard count > 1 else { return }
        for index in 1 ..< count {
            let tab = query.element(boundBy: index)
            guard tab.exists else { continue }
            reveal(tab)
            guard tab.isHittable else { continue }
            tab.click()
            capture("\(number)t\(index)-tab")
            scrollCapture("\(number)t\(index)b-tab")
        }
    }

    @MainActor private func settings() {
        let sections = ["persona", "voiceStudio", "capabilities", "calls", "directory", "routing",
                        "knowledge", "messaging", "members", "scheduling"]
        guard launch(), go(SidebarIDs.settings) else { return }
        capture("42-settings")
        scrollCapture("42b-settings")
        for (index, raw) in sections.enumerated() {
            guard launch(), go(SidebarIDs.settings) else { return }
            guard tapID("district-workspace-settings-row-\(raw)") else { continue }
            capture("\(43 + index)-settings-\(raw)")
            scrollCapture("\(43 + index)b-settings-\(raw)")
        }
    }

    /// The application's menus, each opened and photographed with the whole screen.
    @MainActor private func menus() {
        let items = app.menuBars.menuBarItems
        let count = min(items.count, 9)
        guard count > 1 else { return }
        for index in 1 ..< count {
            let item = items.element(boundBy: index)
            guard item.exists else { continue }
            item.click()
            Thread.sleep(forTimeInterval: 0.8)
            captureScreen(String(format: "60-menu-%02d", index))
            escape()
        }
    }

    /// The menu bar item (the phone in the status bar) and its menu.
    @MainActor private func menuBarItem() {
        let status = app.statusItems.firstMatch
        guard status.waitForExistence(timeout: 5) else {
            missed.append("status-item")
            return
        }
        status.click()
        Thread.sleep(forTimeInterval: 1)
        captureScreen("61-menu-bar-item")
        escape()
    }

    // MARK: - Launching

    @MainActor private var arguments: [String] {
        ["-UITestSession", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            + (dark ? ["-AppleInterfaceStyle", "Dark"] : [])
    }

    /// The signed-out gate: an armed launch with no session is a fresh install.
    @MainActor private func signedOut() {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["DISTRICT_UITEST_WINDOW_POINTS"] = window
        app.launch()
        if ensureWindow() {
            Thread.sleep(forTimeInterval: 3)
            capture("00-sign-in")
        } else {
            missed.append("sign-in")
        }
        app.terminate()
    }

    @MainActor @discardableResult
    private func launch() -> Bool {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["DISTRICT_UITEST_SESSION"] = Self.session
        app.launchEnvironment["DISTRICT_UITEST_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["DISTRICT_UITEST_WINDOW_POINTS"] = window
        app.launch()
        _ = ensureWindow()
        let overview = app.descendants(matching: .any)[SidebarIDs.overview].firstMatch
        guard overview.waitForExistence(timeout: 30) else {
            missed.append("shell")
            capture("00-no-shell")
            return false
        }
        Thread.sleep(forTimeInterval: 2)
        return true
    }

    /// A Debug launch sometimes opens no window (see UITestWindowSize.swift). Activating the
    /// app is the Dock's reopen; failing that, a fresh launch, twice at most.
    ///
    /// ⚠️ NOT THE MENU BAR EXTRA'S "OPEN" ITEM ANY MORE: in the dark run (38771069047) its
    /// menu never reported open, and a failed menu traversal ends the test outright, so one
    /// missing window cost the whole walk.
    @MainActor private func ensureWindow() -> Bool {
        for attempt in 0 ..< 3 {
            let window = app.windows.firstMatch
            if window.waitForExistence(timeout: 20) { return true }
            app.activate()
            if window.waitForExistence(timeout: 10) { return true }
            guard attempt < 2 else { break }
            app.terminate()
            app.launch()
        }
        missed.append("window")
        return false
    }

    // MARK: - Navigation

    /// Scroll the window, over the element's own column, until the element can be pressed.
    @MainActor private func reveal(_ element: XCUIElement) {
        let window = app.windows.firstMatch
        guard window.exists else { return }
        for _ in 0 ..< 8 where element.exists && !element.isHittable {
            let frame = window.frame
            let x = min(max(element.frame.midX, frame.minX + 20), frame.maxX - 20) - frame.minX
            let point = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: frame.height * 0.6))
            point.scroll(byDeltaX: 0, deltaY: element.frame.midY > frame.midY ? -250 : 250)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @MainActor @discardableResult
    private func go(_ row: String) -> Bool {
        press(app.descendants(matching: .any)[row].firstMatch, timeout: 8, name: row)
    }

    @MainActor private func openFirst(prefix: String) -> Bool {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix + "-"))
        return press(query.firstMatch, timeout: 8, name: prefix)
    }

    /// A row found by its button's label, which carries the row's text.
    @MainActor private func openButton(containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 8) {
            return press(button, timeout: 1, name: "button:\(text)")
        }
        let any = app.descendants(matching: .any).matching(predicate).firstMatch
        return press(any, timeout: 2, name: "text:\(text)")
    }

    @MainActor private func tapID(_ id: String) -> Bool {
        press(app.descendants(matching: .any)[id].firstMatch, timeout: 6, name: id)
    }

    @MainActor private func press(_ target: XCUIElement, timeout: TimeInterval, name: String) -> Bool {
        guard target.waitForExistence(timeout: timeout) else {
            missed.append(name)
            return false
        }
        reveal(target)
        guard target.isHittable else {
            missed.append("\(name) (not hittable)")
            return false
        }
        target.click()
        return true
    }

    @MainActor private func escape() {
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.6)
    }

    // MARK: - Capture

    @MainActor private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: settleTime)
        guard app.windows.firstMatch.exists else {
            captureScreen(name)
            return
        }
        reached.append(name)
        attach(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()), name)
    }

    @MainActor private func captureScreen(_ name: String) {
        reached.append(name)
        attach(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), name)
    }

    @MainActor private func captureElement(_ element: XCUIElement, _ name: String) {
        guard element.exists, element.frame.width > 1, element.frame.height > 1 else {
            missed.append(name)
            return
        }
        reached.append(name)
        attach(XCTAttachment(screenshot: element.screenshot()), name)
    }

    @MainActor private func attach(_ shot: XCTAttachment, _ name: String) {
        shot.name = "\(tag)__\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        let text = XCTAttachment(string: app.debugDescription)
        text.name = "\(tag)__\(name).txt"
        text.lifetime = .keepAlways
        add(text)
    }

    @MainActor private func scrollCapture(_ name: String) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).scroll(byDeltaX: 0, deltaY: -600)
        capture(name)
    }

    @MainActor private func report() {
        print("VQA-TOUR[\(tag)] reached \(reached.count): \(reached.joined(separator: " | "))")
        print("VQA-TOUR[\(tag)] missed: \(missed.joined(separator: " | "))")
    }
}

/// The sidebar rows, as `A11yID.Sidebar` names them (compiled into this bundle too).
private enum SidebarIDs {
    static let overview = A11yID.Sidebar.overview
    static let inbox = A11yID.Sidebar.inbox
    static let calls = A11yID.Sidebar.calls
    static let contacts = A11yID.Sidebar.contacts
    static let hq = A11yID.Sidebar.hq
    static let analytics = A11yID.Sidebar.analytics
    static let marketplace = A11yID.Sidebar.marketplace
    static let billing = A11yID.Sidebar.billing
    static let rooms = A11yID.Sidebar.rooms
    static let workflows = A11yID.Sidebar.workflows
    static let desk = A11yID.Sidebar.desk
    static let dialer = A11yID.Sidebar.dialer
    static let scheduling = A11yID.Sidebar.scheduling
    static let support = A11yID.Sidebar.support
    static let settings = A11yID.Sidebar.settings
    static let account = A11yID.Sidebar.account
}
