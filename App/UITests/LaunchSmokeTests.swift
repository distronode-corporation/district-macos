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
