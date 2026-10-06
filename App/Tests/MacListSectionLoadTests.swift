import AppKit
import DistrictAuthCore
@testable import DistrictMac
import DistrictNetwork
import SwiftUI
import XCTest

/// A list section reads its list once per appearance, including while the workspace list
/// is still loading.
///
/// ⛔ MAC ONLY, AND A REGRESSION TEST FOR A REAL DOUBLE READ. With no workspace yet the shell
/// draws a list section in its whole-column layout behind the workspace gate; the update that
/// resolves the workspace also flips it to three columns, and the gate used to build the
/// section's screen in that same update, so a second Desk (or Support) lived for one frame and
/// its `.task` ran too. It happened on every reload of the workspace list while a list section
/// was on screen (a workspace switch, a new sign-in), and every time the screenshot harness
/// opened one. See the ⛔ in ``ShellView``'s `workspaceSection`.
///
/// ⚠️ THE WHOLE SHELL, HOSTED IN A WINDOW THAT IS NEVER SHOWN: the bug is in how SwiftUI
/// builds the two layouts, so nothing short of rendering ``ShellView`` reaches it. The window
/// sits off every screen and is not ordered in.
@MainActor
final class MacListSectionLoadTests: XCTestCase {
    func test_MAC_LOAD_1_theDeskReadsOnceWhenOpenedBeforeTheWorkspaceResolves() async throws {
        let transport = try await render(.desk)
        await arrival(of: "/desk/tickets", on: transport)
        try await settle()
        XCTAssertEqual(transport.count("/desk/settings"), 1, "\(transport.paths)")
        XCTAssertEqual(transport.count("/desk/tickets"), 1, "\(transport.paths)")
    }

    func test_MAC_LOAD_2_supportReadsOnceWhenOpenedBeforeTheWorkspaceResolves() async throws {
        let transport = try await render(.support)
        await arrival(of: "/support/requests", on: transport)
        try await settle()
        XCTAssertEqual(transport.count("/support/requests"), 1, "\(transport.paths)")
    }

    // MARK: - Harness

    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
        try await super.tearDown()
    }

    /// Wait for the request itself, however long a loaded machine takes to make it.
    ///
    /// ⛔ THE EVENT, NOT A POLL AGAINST A DEADLINE: the first read follows the workspace list's
    /// 200 ms answer, the shell's first layout and the section's `.task`, which on a 4-core
    /// Mac under a parallel build took more than the old 5 s poll. The transport fulfils the
    /// expectation when the request is sent; the timeout only turns a request that never
    /// comes into a failure instead of a hung run, and a passing run never waits on it.
    private func arrival(
        of suffix: String,
        on transport: CannedTransport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let sent = transport.arrival(of: suffix)
        let result = await XCTWaiter().fulfillment(of: [sent], timeout: 120)
        if result != .completed {
            XCTFail("no request for \(suffix): \(transport.paths)", file: file, line: line)
        }
    }

    /// ⚠️ LONG ENOUGH FOR A SECOND SCREEN'S `.task` TO HAVE SENT ITS FIRST REQUEST: the double
    /// read arrived within milliseconds of the first in the harness. ⚠️ A WINDOW FOR A READ THAT
    /// MUST NOT COME, so no load can turn it red: a slow machine can only see less of it.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }

    private func render(_ item: SidebarItem) async throws -> CannedTransport {
        let transport = CannedTransport()
        let container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )
        // ⚠️ A SESSION IN MEMORY ONLY: the access token is adopted so no request waits on a
        // refresh, and nothing reaches the keychain.
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
        let push = PushRegistrar(container: container)
        // ⛔ NO LIVE SESSION: the factory builds nothing, so no socket is opened.
        let live = DesktopLive(calls: container.callStack) { _ in nil }
        let session = SessionModel(container: container, push: push, live: live)
        var paths = ShellPaths()
        paths.select(item)
        let shell = ShellView(container: container, session: session, push: push, live: live, paths: paths)
            .frame(width: 1200, height: 800)

        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: shell)
        window.contentView?.layoutSubtreeIfNeeded()
        self.window = window
        return transport
    }
}

/// Answers by path: one workspace, an enabled desk with no tickets, no support requests.
private final class CannedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var awaited: [(suffix: String, sent: XCTestExpectation)] = []

    var paths: [String] {
        lock.withLock { recorded }
    }

    func count(_ suffix: String) -> Int {
        paths.filter { $0.hasSuffix(suffix) }.count
    }

    /// Fulfilled once a request whose path ends in `suffix` has been sent: at once if one
    /// has been already.
    func arrival(of suffix: String) -> XCTestExpectation {
        let sent = XCTestExpectation(description: "a request for \(suffix)")
        let already: Bool = lock.withLock {
            guard recorded.contains(where: { $0.hasSuffix(suffix) }) else {
                awaited.append((suffix, sent))
                return false
            }
            return true
        }
        if already {
            sent.fulfill()
        }
        return sent
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        let path = request.url.path
        let arrived: [XCTestExpectation] = lock.withLock {
            recorded.append(path)
            let due = awaited.filter { path.hasSuffix($0.suffix) }.map(\.sent)
            awaited.removeAll { path.hasSuffix($0.suffix) }
            return due
        }
        arrived.forEach { $0.fulfill() }
        // ⚠️ THE WORKSPACE LIST ANSWERS LATE, so the section is on screen while it loads,
        // which is the window the second screen was built in.
        if path.hasSuffix("/workspace/list") {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard let body = Self.body(for: path) else {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(#"{"error":"not_found"}"#.utf8))
        }
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    private static func body(for path: String) -> String? {
        if path.hasSuffix("/workspace/list") {
            return #"{"success":true,"workspaces":[{"id":"ws_load","name":"Load","region":"us","role":"agency","#
                + #""subscriptionTier":"VoicePro"}],"total":1,"limit":100,"offset":0,"degradedRegions":[],"#
                + #""inactiveCount":0,"defaultWorkspaceId":"ws_load"}"#
        }
        if path.hasSuffix("/desk/settings") {
            return #"{"success":true,"settings":{"enabled":true,"notifyCustomersByEmail":false,"#
                + #""publicBrandName":null,"publicLogoUrl":null}}"#
        }
        if path.hasSuffix("/desk/tickets") {
            return #"{"success":true,"tickets":[]}"#
        }
        if path.hasSuffix("/support/requests") {
            return #"{"success":true,"requests":[]}"#
        }
        return nil
    }
}
