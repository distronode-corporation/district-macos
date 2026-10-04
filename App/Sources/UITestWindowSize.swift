import AppKit
import SwiftUI

extension View {
    /// Sizes the window this view lives in to the points a screenshot run asks for
    /// (``UITestSession/windowPoints(arguments:environment:)``), and does nothing otherwise.
    ///
    /// ⚠️ A STORE SCREENSHOT IS A FIXED PIXEL SIZE. App Store Connect takes 2880x1800 for the
    /// Mac and rejects anything else rather than scaling, so `DistrictMacUITests` asks for a
    /// 1440x900-point window on a 2x display and captures the window alone.
    ///
    /// ⛔ RELEASE BUILDS COMPILE THIS TO `self`: the sizer, like ``UITestSession``, is
    /// `#if DEBUG`.
    func uiTestWindowSize() -> some View {
        #if DEBUG
            background(UITestWindowSizer(points: UITestSession.windowPoints()))
        #else
            self
        #endif
    }
}

#if DEBUG

    /// The zero-size view that finds its window and sets its frame once.
    private struct UITestWindowSizer: NSViewRepresentable {
        let points: CGSize?

        func makeNSView(context _: Context) -> NSView {
            SizerView(points: points)
        }

        func updateNSView(_: NSView, context _: Context) {}

        final class SizerView: NSView {
            private let points: CGSize?

            init(points: CGSize?) {
                self.points = points
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let points, let window else { return }
                // ⚠️ ON THE NEXT TURN OF THE RUN LOOP: SwiftUI sizes a new window after its
                // content first moves into it, and would otherwise undo this frame.
                DispatchQueue.main.async {
                    let origin = window.screen?.visibleFrame.origin ?? .zero
                    window.setFrame(NSRect(origin: origin, size: points), display: true)
                }
            }
        }
    }

#endif
