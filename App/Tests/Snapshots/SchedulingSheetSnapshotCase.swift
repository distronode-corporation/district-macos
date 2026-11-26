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
        try await assertView(
            name,
            rules: rules + ScreenRules.loaded,
            locale: locale,
            size: size,
            file: file,
            testName: testName,
            line: line,
            build: build
        )
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
    ///
    /// ⚠️ ONLY A WINDOW OPENED AFTER THE CALL COUNTS: `build` runs before the harness opens the
    /// state's window, and an earlier state's window can still be listed.
    func chooseSegment(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        let earlier = Set(NSApp.windows.map(ObjectIdentifier.init))
        afterLoad(Self.segmentedControl(excluding: earlier) != nil, file: file, line: line) {
            guard let control = Self.segmentedControl(excluding: earlier) else { return }
            control.selectedSegment = index
            _ = control.sendAction(control.action, to: control.target)
        }
    }

    /// The first segmented control in the window ``ScreenSnapshotCase`` draws in, which it
    /// places at x = -20000, among the windows not in `earlier`.
    private static func segmentedControl(excluding earlier: Set<ObjectIdentifier>) -> NSSegmentedControl? {
        let window = NSApp.windows.last { $0.frame.minX == -20000 && !earlier.contains(ObjectIdentifier($0)) }
        return window?.contentView.flatMap(firstSegmentedControl(in:))
    }

    private static func firstSegmentedControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl {
            return control
        }
        for child in view.subviews {
            if let control = firstSegmentedControl(in: child) {
                return control
            }
        }
        return nil
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
