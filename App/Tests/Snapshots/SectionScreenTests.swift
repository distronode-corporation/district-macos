@testable import DistrictMac
import XCTest

/// Every sidebar section, drawn whole from the service's recorded answers: loaded in English
/// and in Canadian French, and failed (every read answered 500).
///
/// See ``ScreenSnapshotCase`` for how the images are recorded and compared.
final class SectionScreenTests: ScreenSnapshotCase {
    func testOverview() async throws {
        try await sectionStates(.overview)
    }

    func testInbox() async throws {
        try await sectionStates(.inbox)
    }

    func testCalls() async throws {
        try await sectionStates(.calls)
    }

    func testContacts() async throws {
        try await sectionStates(.contacts)
    }

    func testHQ() async throws {
        try await sectionStates(.hq)
    }

    func testAnalytics() async throws {
        try await sectionStates(.analytics)
    }

    func testPhoneNumbers() async throws {
        try await sectionStates(.marketplace)
    }

    func testBilling() async throws {
        try await sectionStates(.billing)
    }

    func testRooms() async throws {
        try await sectionStates(.rooms)
    }

    func testWorkflows() async throws {
        try await sectionStates(.workflows)
    }

    func testDesk() async throws {
        try await sectionStates(.desk)
    }

    func testDial() async throws {
        try await sectionStates(.dialer)
    }

    func testLiveCalls() async throws {
        try await sectionStates(.live)
    }

    func testScheduling() async throws {
        try await sectionStates(.scheduling)
    }

    func testSupport() async throws {
        try await sectionStates(.support)
    }

    func testWorkspaceSettings() async throws {
        try await sectionStates(.settings)
    }

    func testAccount() async throws {
        try await sectionStates(.account)
    }

    /// The smallest window the app allows, on the three-column sections, where it is tightest.
    func testListSectionsAtTheMinimumWindowSize() async throws {
        for item in [SidebarItem.inbox, .calls, .contacts, .desk, .support] {
            try await assertScreen("\(item)-compact", item: item, rules: ScreenRules.loaded, size: Self.compact)
        }
    }

    private func sectionStates(
        _ item: SidebarItem,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        try await assertScreen(
            "loaded-en",
            item: item,
            rules: ScreenRules.loaded,
            file: file,
            testName: testName,
            line: line
        )
        try await assertScreen(
            "loaded-fr",
            item: item,
            rules: ScreenRules.loaded,
            locale: .frCA,
            file: file,
            testName: testName,
            line: line
        )
        try await assertScreen(
            "failed-en",
            item: item,
            rules: ScreenRules.failing,
            file: file,
            testName: testName,
            line: line
        )
    }
}

/// The screens a row or a hub opens, drawn from the same recorded answers.
final class DetailScreenTests: ScreenSnapshotCase {
    private let workspace = ScreenSnapshotCase.workspaceId

    func testCallDetail() async throws {
        try await detail(.callDetail(workspaceId: workspace, callId: "call_contract_answered"), in: .calls)
    }

    func testContactDetail() async throws {
        try await detail(
            .contactDetail(workspaceId: workspace, role: .agency, contactId: "contact_contract_1"),
            in: .contacts
        )
    }

    func testThread() async throws {
        let route = Route.thread(
            workspaceId: workspace,
            role: .agency,
            threadKey: "contact:contact_contract_1",
            replyTargets: [],
            title: "Contract Test Caller"
        )
        try await detail(route, in: .inbox)
    }

    func testDeskTicket() async throws {
        try await detail(.deskTicket(workspaceId: workspace, role: .agency, ticketId: "desk_ticket_open"), in: .desk)
    }

    func testSupportRequest() async throws {
        try await detail(.supportRequest(workspaceId: workspace, role: .agency, key: "DA-42"), in: .support)
    }

    func testDevices() async throws {
        try await detail(.devices, in: .account)
    }

    func testEverySettingsSection() async throws {
        for section in SettingsSection.allCases {
            try await detail(
                .workspaceSettings(workspaceId: workspace, role: .agency, section: section),
                in: .settings,
                name: "\(section)"
            )
        }
    }

    func testEverySchedulingSection() async throws {
        let sections: [SchedulingSection] = [
            .hub, .overview, .eventTypes, .eventType(slug: "phone-consultation"), .hours, .bookings,
            .booking(id: "bk-contract-1"), .calendar, .team, .settings, .developer,
        ]
        for section in sections {
            try await detail(
                .scheduling(workspaceId: workspace, role: .agency, section: section),
                in: .scheduling,
                name: Self.name(of: section)
            )
        }
    }

    private static func name(of section: SchedulingSection) -> String {
        switch section {
        case .eventType: "eventType"
        case .booking: "booking"
        default: "\(section)"
        }
    }

    private func detail(
        _ route: Route,
        in item: SidebarItem,
        name: String = "",
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        let prefix = name.isEmpty ? "" : "\(name)-"
        try await assertScreen(
            "\(prefix)loaded-en",
            item: item,
            route: route,
            rules: ScreenRules.loaded,
            file: file,
            testName: testName,
            line: line
        )
        try await assertScreen(
            "\(prefix)loaded-fr",
            item: item,
            route: route,
            rules: ScreenRules.loaded,
            locale: .frCA,
            file: file,
            testName: testName,
            line: line
        )
        try await assertScreen(
            "\(prefix)failed-en",
            item: item,
            route: route,
            rules: ScreenRules.failing,
            file: file,
            testName: testName,
            line: line
        )
    }
}
