import DistrictData
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The tabs three screens keep behind a segmented control: Phone numbers, the scheduling
/// Developer tab and the scheduling Settings tab, each reached by choosing its segment
/// (``SchedulingSheetSnapshotCase/chooseSegment(_:file:line:)``) on the screen itself, and drawn
/// from the service's recorded answers.
///
/// The first tab of each is drawn by ``SectionScreenTests``; these are the others.
final class SegmentedTabScreenTests: SchedulingSheetSnapshotCase {
    private static let size = MarketplaceTabScreenTests.size

    // MARK: - Phone numbers

    func testPhoneNumbersSearch() async throws {
        try await phoneNumbers(tab: 1, rules: [])
    }

    func testPhoneNumbersRegistrations() async throws {
        try await phoneNumbers(tab: 2, rules: MarketplaceTabScreenTests.registrations)
    }

    func testPhoneNumbersCarrier() async throws {
        try await phoneNumbers(tab: 3, rules: MarketplaceTabScreenTests.carrier)
    }

    /// A viewer on the carrier tab: the accounts without their controls, and the read-only line.
    func testPhoneNumbersCarrierAsAViewer() async throws {
        try await screen("viewer", rules: MarketplaceTabScreenTests.carrier, size: Self.size) { app in
            chooseSegment(3)
            return AnyView(MarketplaceView(container: app.container, workspaceId: app.workspaceId, role: .viewer))
        }
    }

    // MARK: - Scheduling: Developer

    func testDeveloperConnectedApps() async throws {
        try await developer(
            tab: 1,
            op: "oauth.connections.list",
            fixture: "mobile/district-scheduling-oauth-connections.json"
        )
    }

    func testDeveloperWebhooks() async throws {
        try await developer(tab: 2, op: "webhooks.list", fixture: "mobile/district-scheduling-webhooks.json")
        try await screen("viewer", size: Self.size) { app in
            chooseSegment(2)
            return AnyView(SchedulingDeveloperView(
                container: app.container,
                workspaceId: app.workspaceId,
                role: .viewer
            ))
        }
    }

    // MARK: - Scheduling: Settings

    func testSettingsAssistant() async throws {
        try await settings(tab: 1, op: "settings.llm.get")
    }

    func testSettingsProfile() async throws {
        try await settings(tab: 2, op: "me.get")
    }

    func testSettingsNotifications() async throws {
        try await settings(tab: 3, op: "me.get")
        try await screen("viewer", size: Self.size) { app in
            chooseSegment(3)
            return AnyView(SchedulingSettingsView(
                container: app.container,
                workspaceId: app.workspaceId,
                role: .viewer
            ))
        }
    }

    // MARK: - HQ

    /// HQ after a question, answered with the recorded answer, and after a request for a change,
    /// answered with the recorded proposal and its confirm card. The question is typed into the
    /// console and sent with ⌘↩ (``SchedulingSheetSnapshotCase/typeAndSubmit(_:file:line:)``).
    func testHQ() async throws {
        let answered: [FixtureTransport.Rule] = [.any("/api/district/hq", .fixture("mobile/district-hq-answer.json"))]
        for locale in [L10nLocale.en, .frCA] {
            try await screen(
                MarketplaceTabScreenTests.named("answered", locale),
                rules: answered,
                locale: locale,
                size: Self.size
            ) { app in
                typeAndSubmit("How many calls did we get this week?")
                return AnyView(HQView(container: app.container, workspaceId: app.workspaceId, role: .agency))
            }
        }
        let proposed: [FixtureTransport.Rule] = [
            .any("/api/district/hq", .fixture("mobile/district-hq-pending-write.json")),
        ]
        try await screen("proposed", rules: proposed, size: Self.size) { app in
            typeAndSubmit("Change the greeting to good afternoon.")
            return AnyView(HQView(container: app.container, workspaceId: app.workspaceId, role: .agency))
        }
        try await screen("proposed-as-a-viewer", rules: proposed, size: Self.size) { app in
            typeAndSubmit("Change the greeting to good afternoon.")
            return AnyView(HQView(container: app.container, workspaceId: app.workspaceId, role: .viewer))
        }
        try await screen("failed", rules: [.any("/api/district/hq", .status(500))], size: Self.size) { app in
            typeAndSubmit("How many calls did we get this week?")
            return AnyView(HQView(container: app.container, workspaceId: app.workspaceId, role: .agency))
        }
    }

    // MARK: - Drawing

    /// Phone numbers on segment `tab`, in English and French.
    private func phoneNumbers(
        tab: Int,
        rules: [FixtureTransport.Rule],
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await screen(
                MarketplaceTabScreenTests.named("loaded", locale),
                rules: rules,
                locale: locale,
                size: Self.size,
                file: file,
                testName: testName,
                line: line
            ) { app in
                chooseSegment(tab, file: file, line: line)
                return AnyView(MarketplaceView(container: app.container, workspaceId: app.workspaceId, role: .agency))
            }
        }
    }

    /// The Developer tab on segment `tab`: loaded in English and French, with `op` answered 500,
    /// and with `op`'s rows taken out.
    private func developer(tab: Int, op: String, fixture: String, testName: String = #function) async throws {
        try await states(tab: tab, op: op, empty: fixture, testName: testName) { app in
            AnyView(SchedulingDeveloperView(container: app.container, workspaceId: app.workspaceId, role: .agency))
        }
    }

    /// The Settings tab on segment `tab`, loaded in English and French and with `op` answered
    /// 500. No empty state: each of these reads answers one object, with no rows to take out.
    private func settings(tab: Int, op: String, testName: String = #function) async throws {
        try await states(tab: tab, op: op, empty: nil, testName: testName) { app in
            AnyView(SchedulingSettingsView(container: app.container, workspaceId: app.workspaceId, role: .agency))
        }
    }

    /// One state of a tab: its image name, the rules that answer before the recorded reads, and
    /// its language.
    private struct TabState {
        let name: String
        let rules: [FixtureTransport.Rule]
        var locale = L10nLocale.en
    }

    private func states(
        tab: Int,
        op: String,
        empty fixture: String?,
        testName: String,
        view: @escaping (SignedInApp) -> AnyView
    ) async throws {
        var cases = [
            TabState(name: "loaded-en", rules: []),
            TabState(name: "loaded-fr", rules: [], locale: .frCA),
            TabState(name: "failed", rules: [Self.failing(op)]),
        ]
        if let fixture {
            cases.append(TabState(name: "empty", rules: [.scheduling(op, .emptied(fixture))]))
        }
        for state in cases {
            try await screen(
                state.name,
                rules: state.rules,
                locale: state.locale,
                size: Self.size,
                testName: testName
            ) { app in
                chooseSegment(tab)
                return view(app)
            }
        }
    }
}
