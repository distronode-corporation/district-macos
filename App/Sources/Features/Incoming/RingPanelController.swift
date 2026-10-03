import AppKit
import Observation
import SwiftUI

/// The incoming call's own window: a small floating panel that shows the ring, then the
/// answered call, then its ended summary, until the person presses Done.
///
/// ⚠️ THE MAC'S STAND-IN FOR iOS'S FULL-SCREEN COVER OVER THE CALLKIT RING. A sheet on the
/// main window would be hidden behind whatever app is in front, and lost when that window
/// is minimised; this panel floats above other apps, follows the person across Spaces and
/// full-screen apps, and does not take keyboard focus from the app they are typing in
/// until they click it.
///
/// ⛔ IT CANNOT BE CLOSED WITH THE TITLE BAR. A close button would be a third way to end a
/// ring or a call with no say in which, so the panel offers only what the call offers
/// (Answer, Decline, Mute, Hang up, Done), and it goes away when the model is idle.
///
/// ⚠️ IT FOLLOWS ``IncomingCallModel/isPresented`` THROUGH OBSERVATION, so nothing that
/// changes the model has to remember the window.
@MainActor
final class RingPanelController {
    private let model: IncomingCallModel
    private let devices: AudioDevices
    private var panel: NSPanel?

    init(model: IncomingCallModel, devices: AudioDevices) {
        self.model = model
        self.devices = devices
        track()
    }

    private func track() {
        withObservationTracking {
            sync(presented: model.isPresented)
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func sync(presented: Bool) {
        if presented {
            show()
        } else {
            panel?.orderOut(nil)
            panel = nil
        }
    }

    private func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = IncomingCallCopy.panelTitle
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: IncomingCallView(model: model, devices: devices)
            .frame(minWidth: 340, minHeight: 320)
            .districtTheme())
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
