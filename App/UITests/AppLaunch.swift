import XCTest

/// The one launch shape every UI test gives the app: the session seam armed, a session in
/// the environment, and the window sized for a store screenshot.
///
/// ⛔ THE LAUNCH CONTRACT, DUPLICATED ON PURPOSE: `UITestSession` is `#if DEBUG` inside the
/// app target, which a `bundle.ui-testing` target cannot import. These literals must match
/// it.
///
/// ⛔ ONE BUILDER FOR THE SCREENSHOT CASE AND THE LAUNCH SMOKE CASE, so the shape CI proves
/// with a dummy session (``LaunchSmokeTests``) is the shape the screenshot run uses with a
/// real one. A launch argument added to one and not the other is how a screenshot run came
/// to open no window at all.
enum AppLaunch {
    static let argument = "-UITestSession"
    static let sessionVariable = "DISTRICT_UITEST_SESSION"
    static let baseURLVariable = "DISTRICT_UITEST_BASE_URL"
    static let windowVariable = "DISTRICT_UITEST_WINDOW_POINTS"
    static let windowPoints = "1440x900"

    /// The app, configured and not yet launched.
    ///
    /// ⛔ NEVER `-ApplePersistenceIgnoreState YES` BESIDE `-UITestSession`. With the pair the
    /// app opens NO window, in every build: measured on a macOS 26 runner, 0 windows in 30 of
    /// 30 launches across Debug and Release builds of #18 and of v1.0 (which has no seam at
    /// all). `-ApplePersistenceIgnoreState YES` alone opened one in 15 of 15, and
    /// `-UITestSession` alone in 12 of 12 wherever the old sizer view was absent
    /// (`UITestWindowSize.swift`). A restored window does not need the flag: the sizer sets
    /// the frame after the window appears, whatever size it came back at.
    static func app(session: String, baseURL: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launchEnvironment[sessionVariable] = session
        app.launchEnvironment[windowVariable] = windowPoints
        if let baseURL, !baseURL.isEmpty {
            app.launchEnvironment[baseURLVariable] = baseURL
        }
        return app
    }
}
