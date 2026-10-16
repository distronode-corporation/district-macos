import ApplicationServices
import XCTest

/// Launches the app the way the screenshot run does, on a DUMMY session, and asserts it
/// opens a window on the signed-in shell. Run by CI on every push (unlike the screenshots).
///
/// ⛔ IT REACHES NO SERVER. The session is made up here, and the base URL is a closed port
/// on this machine, so every request the shell makes fails at once and the shell draws its
/// offline state. That is enough: what this proves is the launch, not the data. The access
/// token is unexpired, so the coordinator never tries to refresh it.
///
/// ⚠️ THE REGRESSION IT GUARDS. The screenshot case once launched with
/// `-ApplePersistenceIgnoreState YES`, with which the app opens no window; it failed after
/// minutes as "the injected session never reached the signed-in shell", which read as a
/// broken session. See ``AppLaunch``.
final class LaunchSmokeTests: XCTestCase {
    /// The discard port on the loopback interface: nothing listens, so a request fails fast.
    private static let unreachableBaseURL = "http://127.0.0.1:9/"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func test_aSeamSessionOpensAWindowOnTheSignedInShell() {
        let app = AppLaunch.app(session: Self.dummySession(), baseURL: Self.unreachableBaseURL)
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60), "the app opened no window")
        let overview = app.descendants(matching: .any)[A11yID.Sidebar.overview]
        XCTAssertTrue(
            overview.waitForExistence(timeout: 30),
            "the window opened but never showed the signed-in shell's sidebar"
        )
    }

    /// The five `/api/auth/native/token` keys plus `deviceId`, every value made up. The access
    /// token is good for an hour and the refresh token for a day, in epoch milliseconds.
    /// ⛔ SIGN IN IS AN AXBUTTON THAT AXPRESS PRESSES, read and pressed through the C
    /// Accessibility API from this process, as VoiceOver and an automation script do
    /// (``AXProbe``). 3.0.1 draws it with a style of its own (`SignInDoorStyle`) where
    /// 3.0.0 used `.borderedProminent`. Signed out: armed with no session, an empty
    /// in-memory store. The press starts the sign-in, which reaches no server until a
    /// person continues it, and the app is terminated.
    @MainActor
    func test_signInIsAnAXButtonThatAXPressPresses() throws {
        let app = XCUIApplication()
        app.launchArguments = [AppLaunch.argument]
        app.launchEnvironment[AppLaunch.windowVariable] = AppLaunch.windowPoints
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60), "the app opened no window")
        // ⛔ AN AXBUTTON TO XCUITEST, which reads the Accessibility tree through the system's
        // trusted test daemon: this half runs everywhere, CI included.
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 30), "no AXButton 'Sign in' (XCUITest)")
        // ⚠️ THE PRESS NEEDS THIS RUNNER TRUSTED FOR ACCESSIBILITY, which a hosted GitHub
        // runner is not (CI 38857464008: AXIsProcessTrusted() false, every AXUIElement call
        // empty). On a Mac that trusts it (the iMac's QA host), it runs in full.
        try XCTSkipUnless(AXIsProcessTrusted(), "this runner is not trusted for Accessibility; AXPress not checked")
        guard let found = AXProbe.waitForButton("Sign in", timeout: 30) else {
            XCTFail("no AXButton 'Sign in': " + (AXProbe.pid().map(AXProbe.report(pid:)) ?? "no app"))
            return
        }
        let (pid, button) = found
        XCTAssertTrue(AXProbe.actions(button).contains(kAXPressAction), "\(AXProbe.actions(button)) in \(pid)")
        XCTAssertEqual(AXUIElementPerformAction(button, kAXPressAction as CFString), .success)
    }

    private static func dummySession() -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let payload: [String: Any] = [
            "tokenType": "Bearer",
            "accessToken": "launch-smoke-access",
            "accessTokenExpiresAt": now + 3_600_000,
            "refreshToken": "launch-smoke-refresh",
            "refreshTokenExpiresAt": now + 86_400_000,
            "deviceId": "launch-smoke-device",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
