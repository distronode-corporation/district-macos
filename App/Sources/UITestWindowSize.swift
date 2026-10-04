#if DEBUG

    import AppKit

    /// Sizes the main window to the points a screenshot run asks for
    /// (``UITestSession/windowPoints(arguments:environment:)``), and does nothing otherwise.
    ///
    /// ⚠️ A STORE SCREENSHOT IS A FIXED PIXEL SIZE. App Store Connect takes 2880x1800 for the
    /// Mac and rejects anything else rather than scaling, so `DistrictMacUITests` asks for a
    /// 1440x900-point window on a 2x display and captures the window alone.
    ///
    /// ⛔ FROM APPKIT, NEVER FROM THE SCENE'S VIEW TREE. This was a zero-size
    /// `NSViewRepresentable` in the root view's `.background`, and with it in the tree the
    /// Debug app often opened NO window at all: `NSApp.windows` stayed empty, the main thread
    /// sat idle, and the screenshot run timed out as if the session were bad. Measured on a
    /// macOS 26 runner, Debug builds of the same commit: with the view, a window in 0 of 6
    /// armed launches and 1 of 6 plain ones; without it, 6 of 6 and 6 of 6. Nothing here
    /// touches `DistrictMacApp.body`, so the scene is the one a Release build runs.
    ///
    /// ⛔ THE WHOLE FILE IS `#if DEBUG`, like ``UITestSession``: a Release build has no sizer.
    @MainActor
    enum UITestWindowSizer {
        /// How long to look for the main window after launch before giving up.
        private static let attempts = 80
        private static let interval: Duration = .milliseconds(250)

        /// Called once from the app's `init`. A no-op unless a screenshot run asked for a size.
        static func startIfRequested() {
            guard let points = UITestSession.windowPoints() else { return }
            Task { @MainActor in
                for _ in 0 ..< attempts {
                    if let window = mainWindow() {
                        size(window, to: points)
                        // ⚠️ ONCE MORE A MOMENT LATER: SwiftUI sizes a new window after its
                        // content first lays out, and can undo a frame set before that.
                        try? await Task.sleep(for: .seconds(1))
                        size(window, to: points)
                        return
                    }
                    try? await Task.sleep(for: interval)
                }
            }
        }

        /// The shell's window: visible, and not a panel (the ring is an `NSPanel`).
        private static func mainWindow() -> NSWindow? {
            NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }
        }

        private static func size(_ window: NSWindow, to points: CGSize) {
            let origin = window.screen?.visibleFrame.origin ?? .zero
            window.setFrame(NSRect(origin: origin, size: points), display: true)
        }
    }

#endif
