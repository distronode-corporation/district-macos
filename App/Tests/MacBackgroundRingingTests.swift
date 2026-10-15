import DistrictAuthCore
@testable import DistrictMac
import DistrictNetwork
import Foundation
import ServiceManagement
import XCTest

/// Ringing with the window closed: the session starts it with no view, and Open at Login
/// does what the system says.
///
/// ⛔ NO VIEW IS BUILT HERE, AND THAT IS THE POINT: the app keeps ringing behind its menu
/// bar item, so ``SessionModel`` (not ``ShellView``) must start the ringing.
@MainActor
final class MacBackgroundRingingTests: XCTestCase {
    // MARK: - The session starts the ringing

    /// ⛔ A SIGNED-IN SESSION RINGS FOR THE RESOLVED WORKSPACE WITHOUT A WINDOW.
    func test_MAC_BGRING_01_aSignedInSessionRingsForItsWorkspaceWithNoView() async {
        let harness = await Harness(signedIn: true)

        await harness.session.refreshPhase()
        await harness.session.ringingLookup?.value

        XCTAssertEqual(harness.session.phase, .signedIn)
        XCTAssertTrue(harness.live.signedIn)
        XCTAssertEqual(harness.live.workspaceId, "ws_ring")
        XCTAssertEqual(harness.live.workspaceName, "Ring")
    }

    /// ⛔ THE SHELL'S CHOICE WINS: a workspace the shell already reported is not moved by the
    /// session's own read, which only covers a Mac with no window.
    func test_MAC_BGRING_02_aWorkspaceTheShellReportedIsKept() async {
        let harness = await Harness(signedIn: true)
        harness.live.signedIn(workspaceId: "ws_chosen", workspaceName: "Chosen")

        await harness.session.refreshPhase()
        await harness.session.ringingLookup?.value

        XCTAssertEqual(harness.live.workspaceId, "ws_chosen")
    }

    /// ⛔ A SESSION THAT IS NOT SIGNED IN STOPS THE RINGING, with no view to see it end.
    func test_MAC_BGRING_03_aSessionThatEndedStopsTheRinging() async {
        let harness = await Harness(signedIn: false)
        harness.live.signedIn(workspaceId: "ws_ring", workspaceName: "Ring")

        await harness.session.refreshPhase()

        XCTAssertNotEqual(harness.session.phase, .signedIn)
        XCTAssertFalse(harness.live.signedIn)
        XCTAssertNil(harness.live.workspaceId)
        XCTAssertEqual(harness.transport.count("/workspace/list"), 0, "nothing is read without a session")
    }

    // MARK: - Open at Login

    /// ⛔ OFF UNTIL THE USER TURNS IT ON (App Review 2.4.5(iii)): nothing registers on its own.
    func test_MAC_BGRING_04_openAtLoginIsOffUntilTurnedOn() {
        let item = FakeLoginItem()
        let background = BackgroundRinging(loginItem: item)
        XCTAssertFalse(background.opensAtLogin)
        XCTAssertEqual(item.calls, [])

        background.setOpensAtLogin(true)
        XCTAssertTrue(background.opensAtLogin)
        XCTAssertEqual(item.calls, ["register"])

        background.setOpensAtLogin(false)
        XCTAssertFalse(background.opensAtLogin)
        XCTAssertEqual(item.calls, ["register", "unregister"])
    }

    /// ⚠️ SWITCHED OFF IN SYSTEM SETTINGS: the app opens the page where it can be switched
    /// back on, and the toggle shows what the system says rather than what was asked.
    func test_MAC_BGRING_05_aLoginItemAwaitingApprovalOpensSystemSettings() {
        let item = FakeLoginItem()
        item.statusAfterRegister = .requiresApproval
        let background = BackgroundRinging(loginItem: item)

        background.setOpensAtLogin(true)

        XCTAssertFalse(background.opensAtLogin)
        XCTAssertEqual(item.calls, ["register", "openSystemSettings"])
    }

    /// ⚠️ A REFUSED REGISTRATION LEAVES THE TOGGLE OFF.
    func test_MAC_BGRING_06_aRefusedRegistrationLeavesItOff() {
        let item = FakeLoginItem()
        item.refuses = true
        let background = BackgroundRinging(loginItem: item)

        background.setOpensAtLogin(true)

        XCTAssertFalse(background.opensAtLogin)
    }

    /// The status at launch is the system's.
    func test_MAC_BGRING_07_theStatusAtLaunchIsTheSystems() {
        let item = FakeLoginItem()
        item.status = .enabled
        XCTAssertTrue(BackgroundRinging(loginItem: item).opensAtLogin)
    }
}

// MARK: - Harness

/// A container with an in-memory session (or none), a live object that opens no socket,
/// and a workspace selection kept out of the real defaults.
@MainActor
private struct Harness {
    let transport = ListTransport()
    let live: DesktopLive
    let session: SessionModel

    init(signedIn: Bool) async {
        let container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )
        if signedIn {
            let hour: Int64 = 3_600_000
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            await container.coordinator.adopt(
                NativeTokens(
                    accessToken: "access",
                    accessTokenExpiresAt: now + hour,
                    refreshToken: "refresh",
                    refreshTokenExpiresAt: now + 24 * hour
                ),
                deviceId: container.deviceId
            )
        }
        // ⛔ NO LIVE SESSION: the factory builds nothing, so no socket is opened.
        live = DesktopLive(calls: container.callStack) { _ in nil }
        let defaults = UserDefaults(suiteName: "MacBackgroundRingingTests-\(UUID().uuidString)") ?? .standard
        session = SessionModel(
            container: container,
            push: PushRegistrar(container: container, system: .silent),
            live: live,
            selection: WorkspaceSelectionStore(defaults: defaults)
        )
    }
}

/// Answers `workspace/list` with one workspace, and 404 to anything else.
private final class ListTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func count(_ suffix: String) -> Int {
        lock.withLock { recorded }.filter { $0.hasSuffix(suffix) }.count
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        let path = request.url.path
        lock.withLock { recorded.append(path) }
        guard path.hasSuffix("/workspace/list") else {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(#"{"error":"not_found"}"#.utf8))
        }
        let body = #"{"success":true,"workspaces":[{"id":"ws_ring","name":"Ring","region":"us","role":"agency","#
            + #""subscriptionTier":"VoicePro"}],"total":1,"limit":100,"offset":0,"degradedRegions":[],"#
            + #""inactiveCount":0,"defaultWorkspaceId":"ws_ring"}"#
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}

/// `SMAppService.mainApp`, recorded.
@MainActor
private final class FakeLoginItem: LoginItem {
    var status: SMAppService.Status = .notRegistered
    var statusAfterRegister: SMAppService.Status = .enabled
    var refuses = false
    private(set) var calls: [String] = []

    func register() throws {
        calls.append("register")
        if refuses {
            throw CocoaError(.featureUnsupported)
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        status = .notRegistered
    }

    func openSystemSettings() {
        calls.append("openSystemSettings")
    }
}
