import AppKit
import DistrictAuthCore
import DistrictL10n
@testable import DistrictMac
import SnapshotTesting
import SwiftUI
import XCTest

/// The base of the screen snapshot tests: the whole Mac window (``ShellView``, sidebar
/// included) drawn from the service's recorded responses, on one screen, in one state and one
/// language, compared pixel by pixel with a reference image committed beside the tests.
///
/// ⛔ THE REFERENCE IMAGES ARE RECORDED ON CI, NEVER ON A DEVELOPER'S MAC. Text rendering and
/// control drawing differ between macOS versions, so an image recorded anywhere but the `app`
/// job's runner (macOS 26, Xcode 26.3) would fail there. A missing reference makes the test
/// FAIL and writes the new image (SnapshotTesting's `.missing` record mode); the `app` job
/// uploads every new or failing image as the `snapshots` artifact, and the images are
/// committed from it into `App/Tests/Snapshots/__Snapshots__/<suite>/`.
///
/// ⛔ READ FROM THE BUNDLE, WRITTEN TO THE CONTAINER'S TEMPORARY DIRECTORY: the test host runs in
/// the App Sandbox (App/AdHoc.entitlements), so the source tree is out of reach. The references
/// are a folder resource of the test bundle and are copied next to the new images before each
/// comparison; the `app` job finds that directory by its name, `DistrictSnapshots`.
///
/// ⚠️ ONE PIXEL SCALE AND ONE APPEARANCE, WHATEVER THE RUNNER'S DISPLAY: the window is drawn
/// into a bitmap of exactly its size in points, in the light appearance, so the image does not
/// change with the runner's screen scale or a dark-mode default.
///
/// ⚠️ THE SIDEBAR IS AN EMPTY PANEL IN EVERY IMAGE. macOS 26 draws the split view's sidebar as
/// glass, which the window server composites, and a bitmap drawn from the view tree in-process
/// gets the panel without its rows. The sidebar's SwiftUI body still runs (its rows are laid
/// out), and its content is pinned by the sidebar unit tests (`MacSidebarItemTests`).
///
/// ⚠️ THE CLOCK THE SCREENS READ IS THE DEVICE ZONE, PINNED HERE to America/Toronto, so the
/// recorded instants in the fixtures read the same on every runner.
@MainActor
class ScreenSnapshotCase: XCTestCase {
    /// The agency workspace from `district-workspace-list.json`, made the default so every
    /// section is drawn as a role that may see it.
    nonisolated static let workspaceId = "ws-contract-active"

    /// The window the screens are drawn in: wide enough for the three columns, the size the
    /// window opens at on a 13-inch display.
    static let regular = CGSize(width: 1200, height: 800)
    /// The smallest the window may be made (`ListColumnWidth.windowMin` by
    /// `MacWindowSize.minHeight`).
    static let compact = CGSize(width: 1000, height: 560)

    private var window: NSWindow?
    private var savedZone: TimeZone?

    override func setUp() async throws {
        try await super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Toronto") ?? .current
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        L10nRuntime.locale = .en
        if let savedZone {
            NSTimeZone.default = savedZone
        }
        try await super.tearDown()
    }

    /// Draw the shell on `item` (and `route` pushed on it, if any), answered by `rules`, wait
    /// until every read has answered, and compare the window with its reference image.
    func assertScreen(
        _ name: String,
        item: SidebarItem,
        route: Route? = nil,
        rules: [FixtureTransport.Rule],
        locale: L10nLocale = .en,
        size: CGSize = ScreenSnapshotCase.regular,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        try await assertView(
            name,
            rules: rules,
            locale: locale,
            size: size,
            file: file,
            testName: testName,
            line: line
        ) { app in
            var paths = ShellPaths()
            paths.select(item)
            if let route {
                paths.open(route)
            }
            return AnyView(
                ShellView(container: app.container, session: app.session, push: app.push, live: app.live, paths: paths)
            )
        }
    }

    /// Draw whatever `build` returns (a sheet, a single screen) in a window of `size`, signed in
    /// and answered by `rules`, and compare it with its reference image.
    func assertView(
        _ name: String,
        rules: [FixtureTransport.Rule],
        locale: L10nLocale = .en,
        size: CGSize,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        build: (SignedInApp) async throws -> AnyView
    ) async throws {
        L10nRuntime.locale = locale
        let transport = FixtureTransport(rules: rules)
        // ⚠️ THE SHELL'S WORKSPACE MODEL READS THE SELECTION FROM THE STANDARD DEFAULTS (it builds
        // its own `WorkspaceSelectionStore()`), so a workspace another test chose is forgotten
        // there first; every screen then opens on the list's default, the agency workspace.
        WorkspaceSelectionStore().setSelectedWorkspaceId(nil)
        let app = await SignedInApp(transport: transport, defaults: Self.scratchDefaults())
        let view = try await build(app)
        host(view, size: size)
        await settle(transport)
        let unanswered = transport.unansweredRequests
        if !unanswered.isEmpty {
            print("SNAPSHOT-UNANSWERED \(Self.suite(self)).\(name): \(unanswered.joined(separator: ", "))")
        }
        let image = try await steadyFrame(size: size, name: name)
        compare(image, named: name, file: file, testName: testName, line: line)
    }

    /// The window drawn once three drawings in a row, 200 ms apart, are pixel for pixel the same,
    /// or as it stands after six seconds.
    ///
    /// ⚠️ WHY: some screens finish drawing a moment after the last answer, a table's alternating
    /// row backgrounds or a toggle settling into place, and a single drawing caught that moment
    /// on one run and not on the next (run 45842857065: the call detail's list stripes, the
    /// Account toggle). Two identical drawings a quarter of a second apart were not enough: a
    /// thread's scroll position (#159), the code sheet's busy layout (#154) and the supervise
    /// note box (#149) still moved after them on some runs. district-ios waits for three
    /// identical drawings in a row; so does this, over 400 ms of stillness rather than 200.
    ///
    /// ⚠️ A SCREEN THAT NEVER STOPS CHANGING (a spinning progress indicator) is drawn as it
    /// stands after the cap, and the log says so (`SNAPSHOT-UNSETTLED`); the comparison's
    /// tolerance is unchanged.
    private func steadyFrame(size: CGSize, name: String) async throws -> NSImage {
        var (image, bytes) = try render(size: size)
        var same = 0
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .milliseconds(200))
            window?.contentView?.layoutSubtreeIfNeeded()
            window?.displayIfNeeded()
            let (next, nextBytes) = try render(size: size)
            same = nextBytes == bytes ? same + 1 : 0
            (image, bytes) = (next, nextBytes)
            if same >= 2 {
                return image
            }
        }
        print("SNAPSHOT-UNSETTLED \(Self.suite(self)).\(name): still changing after 6 s")
        return image
    }

    // MARK: - Harness

    /// The app's object graph, signed in, with every request going to the fixture transport.
    @MainActor
    struct SignedInApp {
        let container: AppContainer
        let push: PushRegistrar
        let live: DesktopLive
        let session: SessionModel
        let workspaceId = ScreenSnapshotCase.workspaceId

        init(transport: FixtureTransport, defaults: UserDefaults) async {
            container = AppContainer(
                baseURL: URL(string: "https://api.invalid")!,
                microphone: FakeMicrophoneAccess(status: .denied),
                transport: transport,
                tokenStore: InMemoryTokenStore()
            )
            // ⚠️ A SESSION IN MEMORY ONLY, as `MacListSectionLoadTests` adopts it: the access
            // token is fresh so no request waits on a refresh, and nothing reaches the keychain.
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
            push = PushRegistrar(container: container, system: .silent)
            // ⛔ NO LIVE SESSION: the factory builds nothing, so no socket is opened.
            live = DesktopLive(calls: container.callStack) { _ in nil }
            session = SessionModel(
                container: container,
                push: push,
                live: live,
                selection: WorkspaceSelectionStore(defaults: defaults)
            )
        }
    }

    /// ⚠️ NO ANIMATION ANYWHERE IN THE DRAWN TREE, as district-ios draws its screens: a change
    /// lands in one step, so no drawing is taken halfway through a move, and the steady drawing
    /// is the screen's resting state rather than one frame of a transition.
    private func host(_ view: AnyView, size: CGSize) {
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.animationBehavior = .none
        window.contentView = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        )
        window.contentView?.layoutSubtreeIfNeeded()
        self.window = window
    }

    /// ⚠️ A FRESH, EMPTY DEFAULTS DOMAIN PER SCREEN, so a workspace another test selected is
    /// not the one this screen opens on.
    private static func scratchDefaults() -> UserDefaults {
        let name = "snapshots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Wait until no read is in flight and none has been sent for a while, then give SwiftUI
    /// a moment to draw the last answer.
    ///
    /// ⚠️ BOUNDED: a screen that keeps reading (a poll) is drawn as it stands after the cap,
    /// which its reference image then shows; it never hangs the run.
    private func settle(_ transport: FixtureTransport) async {
        let deadline = Date().addingTimeInterval(20)
        try? await Task.sleep(for: .milliseconds(300))
        while !transport.isIdle(for: 0.6), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func render(size: CGSize) throws -> (NSImage, Data) {
        guard let view = window?.contentView,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(size.width),
                  pixelsHigh: Int(size.height),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              )
        else {
            throw XCTSkip("no window to draw")
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let bytes = bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) } ?? Data()
        return (image, bytes)
    }

    private func compare(_ image: NSImage, named name: String, file: StaticString, testName: String, line: UInt) {
        let suite = Self.suite(self)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DistrictSnapshots", isDirectory: true)
            .appendingPathComponent(suite, isDirectory: true)
        Self.stageReference(of: suite, file: "\(Self.sanitized(testName)).\(Self.sanitized(name)).png", in: directory)
        // ⚠️ 98% PERCEPTUAL: a pixel counts as the same when a person could not tell the
        // difference (anti-aliasing that moves by a fraction). ⚠️ AND 99.98% OF PIXELS MUST PASS:
        // at most 1 in 5,000 may differ (192 in the regular window), far fewer than any changed
        // word draws. The Account screen's last pixel row, where a scrolled form is cut off,
        // differed in 52 pixels between two runs of the same commit (run 45850364894).
        let failure = verifySnapshot(
            of: image,
            as: .image(precision: 0.9998, perceptualPrecision: 0.98),
            named: name,
            snapshotDirectory: directory.path,
            file: file,
            testName: testName,
            line: line
        )
        if let failure {
            XCTFail("\(failure)\nSNAPSHOT-DIR \(directory.path)", file: file, line: line)
        }
    }

    private static func suite(_ test: XCTestCase) -> String {
        String(describing: type(of: test))
    }

    /// SnapshotTesting's file-name rule: every run of non-word characters becomes one `-`, and
    /// none is left at either end.
    private static func sanitized(_ component: String) -> String {
        component
            .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }

    /// Put this one image's committed reference where SnapshotTesting looks for it, or nothing.
    ///
    /// ⛔ THE FILE IS DELETED FIRST, so an image an earlier run RECORDED there (a missing
    /// reference) can never pass as a reference on a retry. Only this image's file is touched:
    /// the images other tests in the suite recorded in this run stay for the `app` job to collect.
    private static func stageReference(of suite: String, file: String, in directory: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(file)
        try? manager.removeItem(at: target)
        guard let source = Bundle(for: ScreenSnapshotCase.self).resourceURL?
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(suite, isDirectory: true)
            .appendingPathComponent(file),
            manager.fileExists(atPath: source.path)
        else { return }
        try? manager.copyItem(at: source, to: target)
    }
}
