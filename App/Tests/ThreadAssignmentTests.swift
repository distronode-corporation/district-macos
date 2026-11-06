import DistrictData
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// App parity (3), DistrictCore 8.2.0: the assignee badge, the Assigned to me filter,
/// the assign sheet's members, the write and its refusals.
@MainActor
final class ThreadAssignmentTests: XCTestCase {
    private func french<T>(_ body: () -> T) -> T {
        L10nRuntime.withLocale(.frCA, body)
    }

    private static let roster = #"""
    {"success":true,"members":[
     {"email":"owner@contract.test","role":"agency","createdAt":"2026-08-01T00:00:00.000Z"},
     {"email":"teammate@contract.test","role":"client","createdAt":"2026-08-02T00:00:00.000Z"},
     {"email":"reader@contract.test","role":"viewer","createdAt":"2026-08-03T00:00:00.000Z"}]}
    """#

    private static let assigned = #"""
    {"success":true,"assignment":{"threadKey":"contact:c_1","assigneeEmail":"teammate@contract.test",
     "assignedAt":"2026-10-29T12:00:00.000Z"}}
    """#

    private func model(_ transport: ParityTransport, current: String? = nil) -> ThreadAssignModel {
        ThreadAssignModel(
            inbox: ParityFixtures.inbox(transport),
            workspaces: WorkspaceRepository(client: ParityFixtures.client(transport)),
            workspaceId: "ws_1",
            threadKey: "contact:c_1",
            current: current
        )
    }

    // MARK: - The list

    func testTheBadgeSaysYouOrTheAssigneeAndVoiceOverHearsTheAddress() async {
        let rows = [
            ParityFixtures.row(
                threadKey: "a", counterpart: "+1", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "me@contract.test", assignedToMe: true
            ),
            ParityFixtures.row(
                threadKey: "b", counterpart: "+2", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "teammate@contract.test"
            ),
            ParityFixtures.row(threadKey: "c", counterpart: "+3", channels: ["sms"], replyOptions: "[]"),
        ]
        let displays = await ParityFixtures.summaries(rows).map(ConversationDisplay.init)

        XCTAssertEqual(displays.map(\.assigneeLabel), ["You", "teammate", nil])
        XCTAssertEqual(displays[1].assigneeEmail, "teammate@contract.test")
        XCTAssertEqual(InboxCopy.assignedTo("teammate@contract.test"), "Assigned to teammate@contract.test")
        XCTAssertEqual(french { InboxCopy.assignedTo("teammate@contract.test") }, "Assignée à teammate@contract.test")
        XCTAssertEqual(french { InboxCopy.assigneeYou }, "Vous")
    }

    /// ⛔ THE FILTER READS THE SERVER'S `assignedToMe`, never an address comparison.
    func testAssignedToMeKeepsOnlyTheRowsTheServerSaysAreMine() async {
        let rows = [
            ParityFixtures.row(
                threadKey: "mine", counterpart: "+1", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "Me@Contract.test", assignedToMe: true
            ),
            ParityFixtures.row(
                threadKey: "theirs", counterpart: "+2", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "me@contract.test", assignedToMe: false
            ),
            ParityFixtures.row(threadKey: "nobody", counterpart: "+3", channels: ["sms"], replyOptions: "[]"),
        ]
        let conversations = await ParityFixtures.summaries(rows)

        XCTAssertEqual(InboxModel.visible(conversations, assignedToMeOnly: true).map(\.threadKey), ["mine"])
        XCTAssertEqual(InboxModel.visible(conversations, assignedToMeOnly: false).count, 3)
    }

    /// ⛔ THE TOOLBAR'S ASSIGN… NEVER ACTS ON A ROW THE FILTER HIDES (Seer, #95): an open
    /// conversation reassigned away from this person, with Assigned to me on, is no target.
    func testAssignTargetsOnlyAnOpenConversationTheListStillShows() async throws {
        let conversations = await ParityFixtures.summaries([
            ParityFixtures.row(
                threadKey: "mine", counterpart: "+1", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "me@contract.test", assignedToMe: true
            ),
            ParityFixtures.row(
                threadKey: "reassigned", counterpart: "+2", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "alex@contract.test", assignedToMe: false
            ),
        ])
        let mine = try XCTUnwrap(conversations.first)
        let reassigned = try XCTUnwrap(conversations.last)

        XCTAssertEqual(InboxModel.assignTarget(mine, assignedToMeOnly: true)?.threadKey, "mine")
        XCTAssertNil(InboxModel.assignTarget(reassigned, assignedToMeOnly: true), "hidden by the filter")
        XCTAssertEqual(InboxModel.assignTarget(reassigned, assignedToMeOnly: false)?.threadKey, "reassigned")
        XCTAssertNil(InboxModel.assignTarget(nil, assignedToMeOnly: false), "nothing open")
    }

    /// ⛔ THE OPEN CONVERSATION CLOSES ONLY WHEN THE LIST HIDES IT, and only the operator's own
    /// act asks (xhigh review): the filter toggled, or this sheet's assignment. A refresh never
    /// asks, so a push re-read cannot close the thread the operator is typing in; the rule here
    /// is what the filter and the sheet apply.
    func testTheOpenConversationClosesOnlyWhenTheListHidesIt() async throws {
        let conversations = await ParityFixtures.summaries([
            ParityFixtures.row(
                threadKey: "mine", counterpart: "+1", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "me@contract.test", assignedToMe: true
            ),
            ParityFixtures.row(
                threadKey: "reassigned", counterpart: "+2", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "alex@contract.test", assignedToMe: false
            ),
        ])
        let mine = try XCTUnwrap(conversations.first)
        let reassigned = try XCTUnwrap(conversations.last)

        XCTAssertTrue(InboxModel.hidesOpenConversation(reassigned, assignedToMeOnly: true))
        XCTAssertFalse(InboxModel.hidesOpenConversation(mine, assignedToMeOnly: true))
        XCTAssertFalse(InboxModel.hidesOpenConversation(reassigned, assignedToMeOnly: false), "the filter is off")
        XCTAssertFalse(InboxModel.hidesOpenConversation(nil, assignedToMeOnly: true), "nothing open")
    }

    // MARK: - The sheet

    /// ⛔ NO VIEWER IS OFFERED, and the current owner keeps a row even when the roster no
    /// longer lists them.
    func testTheSheetOffersEveryoneButViewersAndKeepsTheCurrentOwner() async {
        let transport = ParityTransport()
        transport.on(.get, "/workspace/members", 200, Self.roster)
        let sheet = model(transport, current: "former@contract.test")

        await sheet.load()

        guard case let .ready(emails) = sheet.members else { return XCTFail("\(sheet.members)") }
        XCTAssertEqual(emails, ["owner@contract.test", "teammate@contract.test", "former@contract.test"])
    }

    func testAssigningPostsTheAddressAndUnassigningPostsNull() async {
        let transport = ParityTransport()
        transport.on(.post, "/conversations/assign", 200, Self.assigned)
        let sheet = model(transport)

        let assigned = await sheet.assign("teammate@contract.test")
        let unassigned = await sheet.assign(nil)

        XCTAssertTrue(assigned)
        XCTAssertTrue(unassigned)
        let writes = transport.requests(to: "/conversations/assign")
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].json["assigneeEmail"] as? String, "teammate@contract.test")
        XCTAssertEqual(writes[0].json["threadKey"] as? String, "contact:c_1")
        XCTAssertTrue(writes[1].json["assigneeEmail"] is NSNull, "unassign sends an explicit null")
    }

    /// ⛔ TWO TAPS WRITE ONE ASSIGNMENT: the second, made while the first is in flight, writes
    /// nothing.
    func testASecondTapWhileAnAssignmentIsInFlightWritesNothing() async {
        let transport = ParityTransport()
        transport.on(.post, "/conversations/assign", 200, Self.assigned)
        let gate = transport.hold(.post, "/conversations/assign")
        let sheet = model(transport)

        let first = Task { await sheet.assign("teammate@contract.test") }
        await waitUntil { transport.requests(to: "/conversations/assign").count == 1 }
        let second = await sheet.assign("owner@contract.test")
        XCTAssertTrue(sheet.saving)
        gate.open()
        let firstAssigned = await first.value

        XCTAssertFalse(second)
        XCTAssertTrue(firstAssigned)
        XCTAssertEqual(transport.requests(to: "/conversations/assign").count, 1)
        XCTAssertFalse(sheet.saving)
    }

    /// ⛔ AN OLDER LIST READ THAT ANSWERS LAST IS DROPPED (Seer, #99): a refresh begun before an
    /// assignment, answering after the re-read that followed it, must not put the old assignee
    /// back on screen.
    func testAnOlderListReadThatAnswersLastIsDropped() async throws {
        let before = ParityFixtures.row(
            threadKey: "contact:c_1", counterpart: "+14165550177", channels: ["sms"], replyOptions: "[]",
            assigneeEmail: nil
        )
        let after = ParityFixtures.row(
            threadKey: "contact:c_1", counterpart: "+14165550177", channels: ["sms"], replyOptions: "[]",
            assigneeEmail: "teammate@contract.test"
        )
        let transport = ParityTransport()
        transport.on(.get, "/conversations", 200, ParityFixtures.conversations([before]))
        transport.on(.get, "/conversations", 200, ParityFixtures.conversations([after]))
        let gate = transport.hold(.get, "/conversations")
        let unreachable = try XCTUnwrap(URL(string: "https://inbox.invalid"))
        let inbox = InboxModel(
            container: AppContainer(baseURL: unreachable),
            workspaceId: "ws_1",
            role: .client,
            inbox: ParityFixtures.inbox(transport)
        )

        let older = Task { await inbox.load(refreshing: true) }
        await waitUntil { transport.requests(to: "/conversations").count == 1 }
        await inbox.load(refreshing: true)
        gate.open()
        await older.value

        guard case let .content(conversations, _, _, _) = inbox.state else {
            return XCTFail("no list: \(inbox.state)")
        }
        XCTAssertEqual(conversations.map(\.assigneeEmail), ["teammate@contract.test"], "the newer answer stands")
    }

    /// ⛔ BOTH REFUSALS ARE SAID, in French from the catalog.
    func testTheViewerAndNonMemberRefusalsAreSaidInFrench() async {
        let cases = [
            (
                "assignee_is_viewer",
                "Un Lecteur peut consulter les conversations, mais aucune ne peut lui être assignée. "
                    + "Choisissez un membre qui a un autre rôle."
            ),
            (
                "assignee_not_member",
                "Cette personne n'est pas membre de cet espace de travail. Ajoutez-la d'abord à l'équipe."
            ),
        ]
        for (code, french) in cases {
            let transport = ParityTransport()
            transport.on(.post, "/conversations/assign", 400, #"{"error":"Refused.","code":"\#(code)"}"#)
            let sheet = model(transport)

            L10nRuntime.locale = .frCA
            let assigned = await sheet.assign("reader@contract.test")
            L10nRuntime.locale = .en

            XCTAssertFalse(assigned)
            XCTAssertEqual(sheet.failure?.message, french, code)
            XCTAssertFalse(sheet.saving)
        }
    }

    // MARK: - The max review (#99 and #95)

    /// ⛔ THE SHEET CANNOT BE DISMISSED WHILE A WRITE IS IN FLIGHT (Cancel, a swipe down, Esc): the
    /// refusal is said in the sheet, and one closed mid-save said nothing.
    func testTheSheetCannotBeDismissedMidWriteAndTheRefusalStaysInSight() async {
        let transport = ParityTransport()
        transport.on(
            .post, "/conversations/assign", 400,
            #"{"success":false,"error":"Not a member.","code":"assignee_not_member"}"#
        )
        let gate = transport.hold(.post, "/conversations/assign")
        let sheet = model(transport)
        XCTAssertTrue(sheet.canDismiss)

        let write = Task { await sheet.assign("former@contract.test") }
        await waitUntil { transport.requests(to: "/conversations/assign").count == 1 }
        XCTAssertFalse(sheet.canDismiss, "blocked while saving")
        gate.open()
        let assigned = await write.value

        XCTAssertFalse(assigned)
        XCTAssertTrue(sheet.canDismiss)
        XCTAssertNotNil(sheet.failure, "the refusal is there to read")
    }

    /// ⛔ THE SHEET RE-READS THE OWNER WHEN IT OPENS: the row it was opened from can be minutes old,
    /// and a colleague's assignment since would tick the wrong member.
    func testTheSheetRereadsTheCurrentOwnerWhenItOpens() async {
        let row = ParityFixtures.row(
            threadKey: "contact:c_1", counterpart: "+14165550177", channels: ["sms"], replyOptions: "[]",
            assigneeEmail: "teammate@contract.test"
        )
        let transport = ParityTransport()
        transport.on(.get, "/workspace/members", 200, Self.roster)
        transport.on(.get, "/conversations", 200, ParityFixtures.conversations([row]))
        let sheet = model(transport, current: "owner@contract.test")

        await sheet.load()

        XCTAssertEqual(sheet.current, "teammate@contract.test")
        XCTAssertEqual(transport.requests(to: "/conversations").count, 1)
    }

    /// ⚠️ A FAILED RE-READ, OR A ROW OUTSIDE THE LIST'S SCAN, KEEPS THE OWNER THE SHEET OPENED WITH.
    func testAFailedOwnerRereadKeepsTheRowsOwner() async {
        let transport = ParityTransport()
        transport.on(.get, "/workspace/members", 200, Self.roster)
        let failed = model(transport, current: "owner@contract.test")
        await failed.load()
        XCTAssertEqual(failed.current, "owner@contract.test", "the list read failed")

        let other = ParityFixtures.row(
            threadKey: "contact:c_2",
            counterpart: "+2",
            channels: ["sms"],
            replyOptions: "[]"
        )
        transport.on(.get, "/conversations", 200, ParityFixtures.conversations([other]))
        let missing = model(transport, current: "owner@contract.test")
        await missing.load()
        XCTAssertEqual(missing.current, "owner@contract.test", "the row is not in the list")
    }
}

/// The max review of #95, Mac only: after the assign sheet's write, which conversation closes,
/// when, and that its reply is written first.
@MainActor
final class InboxAssignCloseTests: XCTestCase {
    private func inboxModel(_ transport: ParityTransport) throws -> InboxModel {
        let unreachable = try XCTUnwrap(URL(string: "https://inbox.invalid"))
        return InboxModel(
            container: AppContainer(baseURL: unreachable),
            workspaceId: "ws_1",
            role: .client,
            inbox: ParityFixtures.inbox(transport)
        )
    }

    private static func listed(_ assignedToMe: Bool) -> String {
        ParityFixtures.conversations([
            ParityFixtures.row(
                threadKey: "contact:c_1", counterpart: "+14165550177", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: assignedToMe ? "me@contract.test" : "alex@contract.test", assignedToMe: assignedToMe
            ),
            ParityFixtures.row(
                threadKey: "contact:c_2", counterpart: "+14165550188", channels: ["sms"], replyOptions: "[]",
                assigneeEmail: "me@contract.test", assignedToMe: true
            ),
        ])
    }

    /// ⛔ THE CLOSE WAITS FOR A READ THAT APPLIES (Seer 4488553051): a push read begun after the
    /// assignment overtakes its re-read, whose answer is dropped, and the check used to run on the
    /// list from before. Now the newer read carries the close.
    func testAfterAnAssignTheCloseWaitsForTheReadThatApplies() async throws {
        let transport = ParityTransport()
        transport.on(.get, "/conversations", 200, Self.listed(true))
        transport.on(.get, "/conversations", 200, Self.listed(false))
        let inbox = try inboxModel(transport)
        inbox.assignedToMeOnly = true
        let gate = transport.hold(.get, "/conversations")

        let reRead = Task { await inbox.assigned("contact:c_1") }
        await waitUntil { transport.requests(to: "/conversations").count == 1 }
        XCTAssertNil(inbox.assignClose, "nothing applied yet")
        await inbox.load(refreshing: true)
        let check = try XCTUnwrap(inbox.assignClose, "the newer read carries the close")
        gate.open()
        await reRead.value

        XCTAssertEqual(inbox.assignClose, check, "the dropped answer changes nothing")
        XCTAssertEqual(check.threadKey, "contact:c_1")
        XCTAssertTrue(inbox.closes(check, open: "contact:c_1"), "the newer list hides it")
    }

    /// ⛔ ONLY THE ASSIGNED CONVERSATION CLOSES (max review M4): a row's menu can assign another
    /// conversation than the open one, and the open one used to close. ⚠️ A refresh with no
    /// assignment behind it asks for no close at all.
    func testOnlyTheAssignedConversationCloses() async throws {
        let transport = ParityTransport()
        transport.on(.get, "/conversations", 200, Self.listed(false))
        let inbox = try inboxModel(transport)
        inbox.assignedToMeOnly = true

        await inbox.load(refreshing: true)
        XCTAssertNil(inbox.assignClose, "a refresh asks nothing")

        await inbox.assigned("contact:c_1")
        let check = try XCTUnwrap(inbox.assignClose)
        XCTAssertTrue(inbox.closes(check, open: "contact:c_1"))
        XCTAssertFalse(inbox.closes(check, open: "contact:c_2"), "another conversation is open")
        XCTAssertFalse(inbox.closes(check, open: nil), "nothing is open")
        inbox.assignedToMeOnly = false
        XCTAssertFalse(inbox.closes(check, open: "contact:c_1"), "the list still shows it")
    }

    /// ⛔ THE CLOSE WRITES THE OPEN REPLY FIRST (max review M4): the thread's model goes with its
    /// screen, and an edit inside the autosave's two seconds went with it.
    func testClosingAThreadFlushesItsDraft() async {
        let transport = ParityTransport()
        transport.on(.get, "/timeline", 200, ParityFixtures.timeline)
        transport.on(.put, "/messages/drafts", 200, #"{"success":true,"draft":null}"#)
        let thread = ParityFixtures.thread(
            transport,
            threadKey: "contact:c_1",
            targets: [ReplyTarget(to: "+14165550177", channel: MessageChannel.sms)]
        )
        await thread.load()
        OpenThreadDrafts.opened(thread)
        defer { OpenThreadDrafts.closed(thread) }
        thread.composerTextChanged("Half a reply")

        OpenThreadDrafts.flush(workspaceId: "ws_1", threadKey: "contact:c_2")
        OpenThreadDrafts.flush(workspaceId: "ws_1", threadKey: "contact:c_1")

        await waitUntil(timeout: 1) { !transport.requests(to: "/messages/drafts").isEmpty }
        let saves = transport.requests(to: "/messages/drafts")
        XCTAssertEqual(saves.count, 1, "only the open thread, once")
        XCTAssertEqual(saves.first?.json["body"] as? String, "Half a reply")
        XCTAssertNil(thread.autosaveTask, "the debounce is spent")
    }
}

/// App parity (2): the push declaration that goes with the Meta reads.
final class PushCapabilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PushCapabilityTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testTheMemoryStoresAndForgetsTheDeclaration() {
        let memory = UserDefaultsPushTokenMemory(defaults: defaults)
        XCTAssertNil(memory.lastRegisteredCapabilities())

        memory.rememberRegisteredCapabilities("metaChannels")
        XCTAssertEqual(memory.lastRegisteredCapabilities(), "metaChannels")

        memory.forgetRegisteredCapabilities()
        XCTAssertNil(memory.lastRegisteredCapabilities())
    }

    /// ⛔ THE ALERT REGISTER DECLARES `metaChannels`, ONCE: an unchanged token with the
    /// same declaration is not sent again, and an install that registered before 8.2.0
    /// (token remembered, no declaration) registers exactly once more.
    func testTheRegisterDeclaresMetaChannelsOnce() async throws {
        let memory = UserDefaultsPushTokenMemory(defaults: defaults)
        memory.rememberRegisteredToken("apns-token")
        let transport = ParityTransport()
        transport.on(.post, "/devices/register", 200, #"{"success":true}"#)
        let pushTokens = AppContainer.pushTokenRepository(client: ParityFixtures.client(transport), memory: memory)

        let first = await pushTokens.register(token: "apns-token")
        let second = await pushTokens.register(token: "apns-token")

        XCTAssertEqual(try first.get(), .registered)
        XCTAssertEqual(try second.get(), .alreadyRegistered)
        let registers = transport.requests(to: "/devices/register")
        XCTAssertEqual(registers.count, 1)
        XCTAssertEqual(registers.first?.json["capabilities"] as? [String], ["metaChannels"])
        XCTAssertEqual(registers.first?.json["platform"] as? String, "macos")
    }
}

/// The Inbox's guard against overlapping list reads (Seer, #99).
final class LatestReadTests: XCTestCase {
    /// ⛔ ONLY THE LATEST READ BEGUN MAY APPLY ITS ANSWER: a refresh begun before an
    /// assignment, answering after the re-read that followed it, is dropped.
    func testOnlyTheLatestReadAppliesItsAnswer() {
        var reads = LatestRead()
        let beforeAssigning = reads.begin()
        let afterAssigning = reads.begin()

        XCTAssertFalse(reads.isLatest(beforeAssigning))
        XCTAssertTrue(reads.isLatest(afterAssigning))
        let next = reads.begin()
        XCTAssertTrue(reads.isLatest(next), "each new read is the latest")
        XCTAssertFalse(reads.isLatest(afterAssigning))
    }
}
