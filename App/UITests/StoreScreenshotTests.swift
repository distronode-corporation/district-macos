import AppKit
import XCTest

/// Captures the Mac App Store screenshots: one window frame per main section, 2880x1800.
///
/// The Mac twin of district-ios's `StoreScreenshotTests`, fed the same way: an operator mints
/// a session for the review account with `mint-native-session.ts` and exports it to the run.
/// The steps are in docs/screenshots.md.
///
/// ⛔ NEVER RUN BY CI, TWICE OVER. CI tests the `DistrictMacScreenshots` scheme with
/// `-only-testing` of ``LaunchSmokeTests`` alone, and this case skips when the run carries no
/// session, so even a stray `xcodebuild test` of that scheme cannot reach production.
///
/// ⛔ ONE LAUNCH. The injected refresh token is single-use; a second launch replays it and the
/// server revokes the whole family. Everything happens in the one case below.
///
/// ⚠️ THE SIZE COMES FROM THE WINDOW AND THE DISPLAY. The app sizes its window to
/// `DISTRICT_UITEST_WINDOW_POINTS` (1440x900) and the case captures that window, so on a 2x
/// (Retina) display every frame is 2880x1800, the 16:10 size App Store Connect takes. On a 1x
/// display the frames are 1440x900, which App Store Connect also takes, but the case asserts
/// the 2x size so a run on the wrong display fails instead of producing a weaker set.
final class StoreScreenshotTests: XCTestCase {
    /// Where the PNGs are written, when the run names a folder (exported to xcodebuild as
    /// `TEST_RUNNER_DISTRICT_STORE_SCREENSHOTS_DIR`). They are attachments in the result
    /// bundle either way.
    private static let folderVariable = "DISTRICT_STORE_SCREENSHOTS_DIR"

    private static let pixels = (width: 2880, height: 1800)

    /// Sidebar row, then the frame name, in the order the listing should read. Only the
    /// sidebar is ever clicked: nothing here sends, buys, deletes or signs out.
    private static let screens: [(row: String, name: String)] = [
        (A11yID.Sidebar.overview, "1-overview"),
        (A11yID.Sidebar.inbox, "2-inbox"),
        (A11yID.Sidebar.calls, "3-calls"),
        (A11yID.Sidebar.contacts, "4-contacts"),
        (A11yID.Sidebar.scheduling, "5-scheduling"),
    ]

    /// Fewer frames than this is a failed run, not a short set.
    private static let minimumFrames = 3

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func test_captureStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let session = environment[AppLaunch.sessionVariable], !session.isEmpty else {
            throw XCTSkip("no minted review session in this run; see docs/screenshots.md")
        }
        // ⚠️ THE SAME LAUNCH CI PROVES ON A DUMMY SESSION (``LaunchSmokeTests``).
        let app = AppLaunch.app(session: session, baseURL: environment[AppLaunch.baseURLVariable])
        app.launch()

        // ⚠️ THE WINDOW FIRST, so a launch that opens none is not reported as a bad session.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 60), "the app opened no window")
        let overview = app.descendants(matching: .any)[A11yID.Sidebar.overview]
        XCTAssertTrue(
            overview.waitForExistence(timeout: 60),
            "the injected session never reached the signed-in shell (expired or already used?)"
        )
        // ⚠️ TIME FOR THE SIZER AND THE FIRST LOAD to settle before the first frame.
        Thread.sleep(forTimeInterval: 3)

        var captured = 0
        for screen in Self.screens {
            let row = app.descendants(matching: .any)[screen.row]
            guard row.waitForExistence(timeout: 10) else {
                // A section this role does not have: leave it out rather than fail the set.
                print("STORE: no sidebar row \(screen.row); \(screen.name) skipped")
                continue
            }
            row.click()
            Thread.sleep(forTimeInterval: 4)
            capture(app.windows.firstMatch.screenshot(), named: screen.name)
            captured += 1
        }
        XCTAssertGreaterThanOrEqual(captured, Self.minimumFrames, "only \(captured) frames were captured")
    }

    private func capture(_ frame: XCUIScreenshot, named name: String) {
        let shot = XCTAttachment(screenshot: frame)
        shot.name = "STORE-MAC-" + name
        // ⚠️ `keepAlways`: the default discards a passing run's attachments.
        shot.lifetime = .keepAlways
        add(shot)
        let data = frame.pngRepresentation
        let rep = NSBitmapImageRep(data: data)
        let size = (width: rep?.pixelsWide ?? 0, height: rep?.pixelsHigh ?? 0)
        XCTAssertTrue(
            size == Self.pixels,
            "\(name) is \(size.width)x\(size.height), not \(Self.pixels.width)x\(Self.pixels.height)"
        )
        write(data, named: name)
    }

    private func write(_ data: Data, named name: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment[Self.folderVariable], !root.isEmpty else { return }
        let folder = URL(fileURLWithPath: root).appendingPathComponent("mac-16x10", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name + ".png"))
        } catch {
            XCTFail("could not write \(name).png into \(folder.path): \(error)")
        }
    }
}
