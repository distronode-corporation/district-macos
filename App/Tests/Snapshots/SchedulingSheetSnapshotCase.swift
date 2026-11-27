import AppKit
import DistrictData
import DistrictL10n
@testable import DistrictMac
import SwiftUI
import XCTest

/// The base of the scheduling write sheets' snapshot tests: each sheet drawn alone, at the size
/// every one of them opens at, from the service's recorded answers.
///
/// ⚠️ THE MODELS ARE BUILT FROM THE RECORDED READS, THROUGH THE APP'S OWN REPOSITORY. A sheet
/// that edits a loaded row (an event type, a team, a webhook) is handed the row its read screen
/// would hand it, read from the fixture transport by ``SchedulingAdminRepository``, so the
/// form is filled from the service's answer and not from a retyped one.
///
/// ⚠️ A STATE A SHEET'S OWN `.task` WOULD OVERWRITE IS REACHED AFTER THAT READ
/// (``afterLoad(_:file:line:then:)``). Several sheets read their rows when they appear, and that read
/// replaces whatever the rows held, so an edit made before the view is returned would be drawn
/// as the recorded rows again.
@MainActor
class SchedulingSheetSnapshotCase: ScreenSnapshotCase {
    /// The size every scheduling write sheet opens at (`SchedulingWriteSheet`'s
    /// `macSheetSize(width: 520, height: 600)`, capped by ``MacSheetFit``).
    static let sheetSize = CGSize(width: 520, height: MacSheetFit.height(600))

    /// Draw the sheet `build` returns, answered by `rules` first and then by every recorded
    /// read (``ScreenRules/loaded``).
    func sheet(
        _ name: String,
        rules: [FixtureTransport.Rule] = [],
        locale: L10nLocale = .en,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        build: (SignedInApp) async throws -> AnyView
    ) async throws {
        try await screen(
            name,
            rules: rules,
            locale: locale,
            size: Self.sheetSize,
            file: file,
            testName: testName,
            line: line,
            build: build
        )
    }

    /// Draw what `build` returns at `size`, answered by `rules` first and then by every recorded
    /// read, and await the steps it scheduled.
    func screen(
        _ name: String,
        rules: [FixtureTransport.Rule] = [],
        locale: L10nLocale = .en,
        size: CGSize,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        build: (SignedInApp) async throws -> AnyView
    ) async throws {
        defer { probe = nil }
        try await assertView(
            name,
            rules: rules + ScreenRules.loaded,
            locale: locale,
            size: size,
            file: file,
            testName: testName,
            line: line
        ) { app in
            let view = try await build(app)
            // A driver (``chooseSegment(_:file:line:)``, ``typeAndSubmit(_:file:line:)``) asked
            // for the window this view will be drawn in: a zero-size probe behind it reports it.
            guard let probe else { return view }
            return AnyView(view.background(WindowProbe(box: probe)))
        }
        // ⛔ EVERY STEP THIS STATE SCHEDULED IS AWAITED BEFORE THE STATE IS DONE, so a step that
        // never ran fails this state's test, not whichever test happens to be running when its
        // wait gives up.
        let steps = pendingSteps
        pendingSteps = []
        for step in steps {
            let ran = await step.task.value
            if !ran {
                XCTFail("the sheet's own read never answered, so its step never ran", file: step.file, line: step.line)
            }
        }
    }

    /// Choose segment `index` of the drawn window's segmented control, as a click on it does:
    /// the control's selection changes and its action is sent, which is what a SwiftUI
    /// `Picker` in the segmented style listens to.
    ///
    /// ⚠️ THE ONLY WAY INTO A TAB A SCREEN KEEPS IN A MODEL OF ITS OWN (`MarketplaceView`,
    /// `SchedulingDeveloperView`, `SchedulingSettingsView`): nothing outside the view can set it.
    func chooseSegment(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let box = windowBox()
        afterLoad(box.find(NSSegmentedControl.self) != nil, file: file, line: line) {
            guard let control = box.find(NSSegmentedControl.self) else { return }
            control.selectedSegment = index
            _ = control.sendAction(control.action, to: control.target)
        }
    }

    /// Type `text` into the drawn window's first editable text field and press ⌘↩, as a
    /// person asking HQ a question does: the field takes focus, the text goes in through its
    /// editor (which is what a SwiftUI `TextField` listens to), and the key equivalent reaches
    /// the button that carries the shortcut.
    func typeAndSubmit(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let box = windowBox()
        afterLoad(box.textInput() != nil, file: file, line: line) {
            guard let window = box.window, let input = box.textInput() else { return }
            window.makeFirstResponder(input)
            (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: 0, length: 0))
            // Let SwiftUI take the new text before the shortcut asks the button to send it.
            try? await Task.sleep(for: .milliseconds(200))
            if let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            ) {
                _ = window.performKeyEquivalent(with: event)
            }
        }
    }

    /// The window the state being built will be drawn in, reported by a probe ``screen``
    /// puts behind the view.
    ///
    /// ⚠️ A PROBE AND NOT `NSApp.windows`: the harness's window is never ordered in, and a
    /// window that was never shown is not reliably listed there (the first run found none).
    private var probe: WindowBox?

    private func windowBox() -> WindowBox {
        if let probe {
            return probe
        }
        let box = WindowBox()
        probe = box
        return box
    }

    /// The same state in English (`<name>-en`) and Canadian French (`<name>-fr`).
    func sheetInBothLanguages(
        _ name: String,
        rules: [FixtureTransport.Rule] = [],
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        build: (SignedInApp) async throws -> AnyView
    ) async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await sheet(
                "\(name)-\(locale == .en ? "en" : "fr")",
                rules: rules,
                locale: locale,
                file: file,
                testName: testName,
                line: line,
                build: build
            )
        }
    }

    /// Run `step` once `ready` holds, which is the sheet's own read having answered.
    ///
    /// ⚠️ BOUNDED, like the harness's settle: a read that has not answered after ten seconds
    /// gives up and `step` never runs, since a step that indexes the rows it waited for would
    /// trap on an empty list. ``sheet(_:rules:locale:file:testName:line:build:)`` awaits the
    /// wait before it returns and fails the state if the step did not run. The image is taken
    /// by the harness's settle, which does not know about the step, so such a state fails
    /// after its comparison rather than before it.
    func afterLoad(
        _ ready: @autoclosure @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        then step: @escaping @MainActor () async -> Void
    ) {
        let task = Task { @MainActor in
            let deadline = Date().addingTimeInterval(10)
            while !ready() {
                guard Date() < deadline else { return false }
                try? await Task.sleep(for: .milliseconds(10))
            }
            await step()
            return true
        }
        pendingSteps.append(PendingStep(task: task, file: file, line: line))
    }

    /// A step ``afterLoad(_:file:line:then:)`` scheduled, and where it was asked for.
    private struct PendingStep {
        let task: Task<Bool, Never>
        let file: StaticString
        let line: UInt
    }

    private var pendingSteps: [PendingStep] = []

    /// A scheduling op answered with a 500 and the service's error envelope: the write's
    /// failure state.
    static func failing(_ op: String) -> FixtureTransport.Rule {
        .scheduling(op, .status(500))
    }
}

/// The window a probe found, and the controls a driver looks for in it.
@MainActor
final class WindowBox {
    weak var window: NSWindow?

    func find<Control: NSView>(_: Control.Type) -> Control? {
        window?.contentView.flatMap { root in Self.first(in: root) { view in view as? Control } }
    }

    /// The first editable text field or text view.
    func textInput() -> NSView? {
        window?.contentView.flatMap { root in
            Self.first(in: root) { view -> NSView? in
                if let field = view as? NSTextField, field.isEditable {
                    return field
                }
                if let text = view as? NSTextView, text.isEditable {
                    return text
                }
                return nil
            }
        }
    }

    private static func first<Found>(in view: NSView, _ match: (NSView) -> Found?) -> Found? {
        if let found = match(view) {
            return found
        }
        for child in view.subviews {
            if let found = first(in: child, match) {
                return found
            }
        }
        return nil
    }
}

/// A zero-size view that records the window it is placed in.
private struct WindowProbe: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context _: Context) -> ProbeView {
        let view = ProbeView()
        view.box = box
        return view
    }

    func updateNSView(_ view: ProbeView, context _: Context) {
        view.box = box
    }

    final class ProbeView: NSView {
        var box: WindowBox?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
    }
}
