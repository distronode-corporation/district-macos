import DistrictData
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

    /// The wizard as the app builds it, with two seams pinned:
    ///
    /// ⛔ NO APP STORE STOREFRONT. The app asks StoreKit for the storefront before the wizard
    /// leaves its loading state, and on the runner the first ask can take longer than the
    /// harness waits: testBusiness's first reference caught "Loading your setup" (run
    /// 45871221841 then drew the step). Nil is what a Mac with no storefront answers, and the
    /// Developer ID build's answer always.
    /// ⛔ ITS OWN, EMPTY DRAFT STORE. The wizard restores step 1's unsaved draft per workspace
    /// over the service's answer, and the standard defaults can hold one another test saved.
    private static func wizard(_ app: SignedInApp) -> AnyView {
        let workspaces = app.container.workspaces
        let workspaceId = app.workspaceId
        let suite = "snapshots.setup.\(UUID().uuidString)"
        let model = SetupWizardModel(
            repository: SetupWizardRepository(client: app.container.api),
            workspaceId: workspaceId,
            workspaceName: "Zulu Agency",
            store: SetupDraftStore(defaults: UserDefaults(suiteName: suite) ?? .standard),
            personaLanguage: { try? await workspaces.config(workspaceId: workspaceId).get().aiPersona?.language },
            storefront: { nil }
        )
        return AnyView(SetupWizardView(model: model, container: app.container, onClose: {}))
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
