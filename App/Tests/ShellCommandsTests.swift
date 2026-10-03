@testable import DistrictMac
import DistrictModel
import XCTest

/// The menu commands: when each one can run, which digit selects which section, and which
/// screen ⌘R refreshes. Ported from the iPad's hardware-keyboard tests.
///
/// ⚠️ THE KEY PRESSES THEMSELVES ARE NOT DRIVEN HERE. A command reaches a screen only in a
/// signed-in shell; these pin the decisions the menu and the screens read.
final class ShellCommandsTests: XCTestCase {
    // MARK: - Availability

    /// ⛔ SIGNED OUT, OR NO WORKSPACE YET: EVERY COMMAND BUT ACCOUNT IS DISABLED.
    ///
    /// ⚠️ THE MAC'S ONE DIFFERENCE: Go > Account stays enabled, because the Mac draws
    /// Account with no workspace at all (it is where you sign out).
    func test_IOS_COMMANDS_01_nothingRunsWithoutAWorkspace() {
        for availability in [
            ShellCommandAvailability.unavailable,
            ShellCommandAvailability(workspaceId: nil, role: .agency, refreshAvailable: true),
        ] {
            for item in SidebarItem.allCases where item != .account {
                XCTAssertFalse(availability.canSelect(item), "\(item)")
            }
            XCTAssertTrue(availability.canSelect(.account))
            XCTAssertFalse(availability.canCompose)
            XCTAssertFalse(availability.canSearch)
            XCTAssertFalse(availability.canRefresh)
        }
    }

    /// ⛔ ⌘N FOLLOWS THE SEND GATE: a viewer, and a role that could not be established, may
    /// not compose; everyone may still select, search and refresh.
    func test_IOS_COMMANDS_02_composeFollowsTheSendGate() {
        let roles: [WorkspaceRole?] = WorkspaceRole.allCases.map(\.self) + [nil]
        for role in roles {
            let availability = ShellCommandAvailability(workspaceId: "ws_1", role: role, refreshAvailable: true)
            XCTAssertEqual(availability.canCompose, WorkspaceRole.allowsMutation(role), String(describing: role))
            XCTAssertTrue(availability.canSelect(.inbox))
            XCTAssertTrue(availability.canSearch)
            XCTAssertTrue(availability.canRefresh)
        }
        XCTAssertFalse(ShellCommandAvailability(workspaceId: "ws_1", role: .viewer, refreshAvailable: true).canCompose)
        XCTAssertFalse(ShellCommandAvailability(workspaceId: "ws_1", role: nil, refreshAvailable: true).canCompose)
    }

    /// ⚠️ ⌘R NEEDS A SCREEN THAT REFRESHES ON SCREEN.
    func test_IOS_COMMANDS_03_refreshNeedsAScreenThatRefreshes() {
        let availability = ShellCommandAvailability(workspaceId: "ws_1", role: .agency, refreshAvailable: false)
        XCTAssertFalse(availability.canRefresh)
    }

    /// ⌘1 to ⌘5 are the iPad tab bar's order.
    func test_IOS_COMMANDS_04_theDigitsFollowTheTabOrder() {
        let digits = Tab.allCases.map { SidebarItem(tab: $0).shortcutDigit }
        XCTAssertEqual(digits, ["1", "2", "3", "4", "5"])
    }

    /// ⛔ THE GO MENU OFFERS WHAT THE SIDEBAR OFFERS: a viewer cannot select Dial, Desk or
    /// Support from the menu any more than from the sidebar.
    func test_MAC_COMMANDS_01_theGoMenuFollowsTheSidebarsGates() {
        let viewer = ShellCommandAvailability(workspaceId: "ws_1", role: .viewer, refreshAvailable: false)
        let offered = SidebarItem.visible(workspaceId: "ws_1", role: .viewer)
        for item in SidebarItem.allCases {
            XCTAssertEqual(viewer.canSelect(item), offered.contains(item), "\(item)")
        }
        XCTAssertFalse(viewer.canSelect(.dialer))
        XCTAssertFalse(viewer.canSelect(.desk))
        XCTAssertFalse(viewer.canSelect(.support))
        let agency = ShellCommandAvailability(workspaceId: "ws_1", role: .agency, refreshAvailable: false)
        XCTAssertTrue(SidebarItem.allCases.allSatisfy(agency.canSelect))
    }

    // MARK: - Which screen ⌘R refreshes

    /// ⛔ THE SCREEN THAT APPEARED LAST, and the one under it once that one has gone.
    @MainActor
    func test_IOS_COMMANDS_05_theLastScreenToAppearIsRefreshed() async {
        let center = ShellCommandCenter()
        let log = RefreshLog()
        XCTAssertFalse(center.canRefresh)

        let list = UUID()
        let pushed = UUID()
        center.register(list) { await log.append("list") }
        center.register(pushed) { await log.append("pushed") }
        XCTAssertTrue(center.canRefresh)

        await center.refresh()
        center.unregister(pushed)
        await center.refresh()
        center.unregister(list)
        XCTAssertFalse(center.canRefresh)
        await center.refresh()

        let entries = await log.entries
        XCTAssertEqual(entries, ["pushed", "list"])
    }

    /// ⚠️ A SCREEN THAT APPEARS AGAIN MOVES TO THE TOP rather than being listed twice.
    @MainActor
    func test_IOS_COMMANDS_06_reappearingMovesAScreenToTheTop() async {
        let center = ShellCommandCenter()
        let log = RefreshLog()
        let first = UUID()
        let second = UUID()
        center.register(first) { await log.append("first") }
        center.register(second) { await log.append("second") }
        center.register(first) { await log.append("first again") }

        await center.refresh()
        center.unregister(first)
        await center.refresh()

        let entries = await log.entries
        XCTAssertEqual(entries, ["first again", "second"])
    }

    /// ⛔ ONE REFRESH AT A TIME: ⌘R is disabled, and does nothing, while one runs.
    @MainActor
    func test_IOS_COMMANDS_07_aRefreshInFlightBlocksASecond() async {
        let center = ShellCommandCenter()
        let gate = RefreshGate()
        let log = RefreshLog()
        center.register(UUID()) {
            await log.append("run")
            await gate.wait()
        }

        let running = Task { await center.refresh() }
        while await log.entries.isEmpty {
            await Task.yield()
        }
        XCTAssertTrue(center.isRefreshing)
        XCTAssertFalse(center.canRefresh)
        await center.refresh()

        await gate.open()
        await running.value
        XCTAssertFalse(center.isRefreshing)
        XCTAssertTrue(center.canRefresh)
        let entries = await log.entries
        XCTAssertEqual(entries, ["run"])
    }
}

private actor RefreshLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

private actor RefreshGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
