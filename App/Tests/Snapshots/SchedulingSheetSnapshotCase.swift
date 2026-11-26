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
/// (``afterLoad(_:then:)``). Several sheets read their rows when they appear, and that read
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
        try await assertView(
            name,
            rules: rules + ScreenRules.loaded,
            locale: locale,
            size: Self.sheetSize,
            file: file,
            testName: testName,
            line: line,
            build: build
        )
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
    /// ⚠️ BOUNDED, like the harness's settle: a read that never answers runs `step` anyway
    /// after ten seconds, and the image shows what that left.
    func afterLoad(
        _ ready: @autoclosure @escaping @MainActor () -> Bool,
        then step: @escaping @MainActor () async -> Void
    ) {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(10)
            while !ready(), Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await step()
        }
    }

    /// A scheduling op answered with a 500 and the service's error envelope: the write's
    /// failure state.
    static func failing(_ op: String) -> FixtureTransport.Rule {
        .scheduling(op, .status(500))
    }
}
