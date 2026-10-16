import AppKit
@testable import DistrictCall
import DistrictData
@testable import DistrictMac
import DistrictNetwork
import SwiftUI
import XCTest

/// The buttons an assistive app presses, read the way VoiceOver and every Accessibility
/// client read them: the hosting view's `NSAccessibility` tree, each node's role and label,
/// and `accessibilityPerformPress()`, the AXPress action, not a mouse click.
///
/// ⛔ WHY: 3.0.1 drew the ring panel's Decline and Answer (``RingButtonStyle``) and the
/// sign-in screen's Sign in (`SignInDoorStyle`) with styles of the app's own, where 3.0.0
/// used the system's `.borderedProminent`. A button that stopped being an AXButton, or
/// stopped answering AXPress, would leave a VoiceOver user unable to answer a call. The
/// walk is checked first on a stock `.borderedProminent` button, so a walk that finds
/// nothing fails as a broken walk rather than passing or blaming a style.
@MainActor
final class AccessibilityButtonRoleTests: XCTestCase {
    private struct Node {
        let role: String
        let label: String
        let object: NSObject
    }

    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.close()
        }
        windows = []
        try await super.tearDown()
    }

    // MARK: - The walk

    private func host(_ view: some View, size: NSSize) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        windows.append(window)
        return host
    }

    /// Every node under `root`, by the informal protocol's selectors, so a node that
    /// implements NSAccessibility without declaring the protocol is read too.
    private func nodes(under root: NSObject) -> [Node] {
        var found: [Node] = []
        var queue: [(NSObject, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (object, depth) = queue.removeFirst()
            let role = string(object, "accessibilityRole")
            found.append(Node(role: role, label: string(object, "accessibilityLabel"), object: object))
            guard depth < 40 else { continue }
            let children = call(object, "accessibilityChildren") as? [Any] ?? []
            queue += children.compactMap { $0 as? NSObject }.map { ($0, depth + 1) }
        }
        return found
    }

    private func call(_ object: NSObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func string(_ object: NSObject, _ name: String) -> String {
        (call(object, name) as? String) ?? ""
    }

    private func buttons(under root: NSObject) -> [Node] {
        nodes(under: root).filter { $0.role == NSAccessibility.Role.button.rawValue }
    }

    /// AXPress on the node, as an Accessibility client sends it. The count the button's
    /// action keeps is the proof that it was pressed.
    private func press(_ node: Node) {
        if let element = node.object as? NSAccessibilityProtocol, let axPress = element.accessibilityPerformPress {
            XCTAssertTrue(axPress(), node.label)
        } else if node.object.responds(to: NSSelectorFromString("accessibilityPerformPress")) {
            _ = node.object.perform(NSSelectorFromString("accessibilityPerformPress"))
        } else {
            XCTFail("\(node.label): no accessibilityPerformPress (role \(node.role))")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func report(_ root: NSObject) -> String {
        nodes(under: root).map { "\($0.role) '\($0.label)'" }.joined(separator: " | ")
    }

    // MARK: - The control

    /// ⛔ THE WALK ITSELF: the system's own style (3.0.0's) is an AXButton that AXPress
    /// presses. If this fails, the other results here say nothing.
    func test_AXBUTTON_1_theWalkFindsAndPressesASystemButton() {
        let pressed = Presses()
        let root = host(
            Button("Control") { pressed.count += 1 }.buttonStyle(.borderedProminent),
            size: NSSize(width: 200, height: 80)
        )
        let found = buttons(under: root).filter { $0.label == "Control" }
        XCTAssertEqual(found.count, 1, report(root))
        if let button = found.first {
            press(button)
        }
        XCTAssertEqual(pressed.count, 1)
    }

    // MARK: - The ring panel (AP-018)

    /// ⛔ A BUTTON IN ``RingButtonStyle`` IS AN AXBUTTON AND AXPRESS PRESSES IT.
    func test_AXBUTTON_2_theRingStyleIsAPressableButton() {
        let pressed = Presses()
        let root = host(
            Button { pressed.count += 1 } label: { Label("Answer", systemImage: "phone.fill") }
                .buttonStyle(RingButtonStyle(action: .answer)),
            size: NSSize(width: 200, height: 80)
        )
        let found = buttons(under: root).filter { $0.label == "Answer" }
        XCTAssertEqual(found.count, 1, report(root))
        if let button = found.first {
            press(button)
        }
        XCTAssertEqual(pressed.count, 1)
    }

    /// ⛔ THE RINGING PANEL ITSELF: Decline and Answer are its two AXButtons, by name.
    func test_AXBUTTON_3_theRingPanelHasDeclineAndAnswerAsButtons() throws {
        let transport = RoutedTransport { _ in HTTPResponse(statusCode: 404, body: Data("{}".utf8)) }
        let api = try ApiClient(
            baseURL: XCTUnwrap(URL(string: "https://www.example.test")),
            transport: transport,
            accessToken: { "a.b.c" }
        )
        let model = IncomingCallModel(
            calls: CallStack(microphone: FakeMicrophoneAccess(status: .granted)),
            inbound: InboundCallRepository(client: api),
            callLog: CallsRepository(client: api),
            presenter: SilentPresenter()
        )
        let devices = AudioDevices(defaults: UserDefaults(suiteName: "ax-button-roles") ?? .standard)
        let root = host(
            IncomingCallView(model: model, devices: devices).districtTheme(),
            size: NSSize(width: 380, height: 360)
        )
        let labels = Set(buttons(under: root).map(\.label))
        XCTAssertTrue(labels.isSuperset(of: ["Decline", "Answer"]), report(root))
    }

    // MARK: - Sign in (AP-030)

    /// ⛔ SIGN IN IS AN AXBUTTON AND AXPRESS PRESSES IT.
    func test_AXBUTTON_4_signInIsAPressableButton() {
        let pressed = Presses()
        let root = host(
            SignInView(reason: "", actionTitle: "Sign in", isBusy: false, action: { pressed.count += 1 }, apple: nil)
                .districtTheme(),
            size: NSSize(width: 600, height: 500)
        )
        let found = buttons(under: root).filter { $0.label == "Sign in" }
        XCTAssertEqual(found.count, 1, report(root))
        if let button = found.first {
            press(button)
        }
        XCTAssertEqual(pressed.count, 1)
    }
}

@MainActor
private final class Presses {
    var count = 0
}

private final class SilentPresenter: RingPresenting {
    func startRinging(workspaceId _: String, callId _: String) {}
    func stopRinging() {}
    func withdrawAlerts(callId _: String) {}
}
