import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The setup wizard's sheet on each of its six steps, in English and French, and its loading
/// failure. The wizard opens on the first step still `todo` in `setupProgress`, so each step
/// is reached by marking the steps before it done in the recorded `district-setup.json`.
final class SetupWizardScreenTests: ScreenSnapshotCase {
    /// The size the shell presents the sheet at (`macSheetSize(width: 640, height:
    /// MacSheetFit.maxHeight)`).
    private static let sheet = CGSize(width: 640, height: MacSheetFit.maxHeight)

    func testBusiness() async throws {
        try await step(.business)
    }

    func testNumber() async throws {
        try await step(.number)
    }

    func testReceptionist() async throws {
        try await step(.receptionist)
    }

    func testCallers() async throws {
        try await step(.callers)
    }

    func testCalls() async throws {
        try await step(.calls)
    }

    func testGoLive() async throws {
        try await step(.golive)
    }

    func testFailed() async throws {
        try await assertView("failed-en", rules: ScreenRules.failing, size: Self.sheet) { app in
            Self.wizard(app)
        }
    }

    private func step(
        _ open: SetupStep,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        let rules = [Self.setup(openingOn: open)] + ScreenRules.loaded
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                "\(open.rawValue)-\(locale == .en ? "en" : "fr")",
                rules: rules,
                locale: locale,
                size: Self.sheet,
                file: file,
                testName: testName,
                line: line
            ) { app in
                Self.wizard(app)
            }
        }
    }

    private static func wizard(_ app: SignedInApp) -> AnyView {
        AnyView(SetupWizardView(
            container: app.container,
            workspaceId: app.workspaceId,
            workspaceName: "Zulu Agency",
            onClose: {}
        ))
    }

    /// The recorded setup state with every step before `open` done and the rest `todo`.
    private static func setup(openingOn open: SetupStep) -> FixtureTransport.Rule {
        .get("/api/district/setup", .edited("mobile/district-setup.json") { body in
            var progress = body["setupProgress"] as? [String: Any] ?? [:]
            var steps: [String: String] = [:]
            var reached = false
            for step in SetupStep.allCases {
                reached = reached || step == open
                steps[step.rawValue] = reached ? "todo" : "done"
            }
            progress["steps"] = steps
            body["setupProgress"] = progress
        })
    }
}
