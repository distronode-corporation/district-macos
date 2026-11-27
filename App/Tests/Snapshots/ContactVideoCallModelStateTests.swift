@testable import DistrictMac
import DistrictModel
import XCTest

/// Starting a video call with a contact: a room token, then an invitation sent to the
/// contact's phone or mailbox, answered by the service's recorded responses (`contracts/`).
///
/// ⚠️ THE CONTACT IS THE RECORDED ONE, read through ``ContactDetailModel`` as the screen reads
/// it, so the call starts from the same value the detail screen holds.
///
/// ⚠️ TWO WRITES, TWO RULES AFTER `ScreenRules.loaded`: the send matches the messages path, and
/// the room token, the only other request a start makes, is answered by the last rule.
@MainActor
final class ContactVideoCallModelStateTests: XCTestCase {
    /// ⚠️ A CONTACT THAT DID NOT LOAD FAILS THE TEST, never skips it.
    private struct NotLoaded: Error {
        let state: String
    }

    private static let api = "/api/district"

    private static func rules(
        token: FixtureTransport.Reply = .fixture("mobile/district-room-token.json"),
        send: FixtureTransport.Reply = .fixture("mobile/district-message-send.json"),
        contact: FixtureTransport.Rule? = nil
    ) -> [FixtureTransport.Rule] {
        (contact.map { [$0] } ?? []) + ScreenRules.loaded + [
            .any("\(api)/messages(/.*)?", send),
            .any(".*", token),
        ]
    }

    private func start(
        _ rules: [FixtureTransport.Rule],
        role: WorkspaceRole? = .agency
    ) async throws -> (ContactVideoCallModel, FixtureTransport) {
        let transport = FixtureTransport(rules: rules)
        let defaults = UserDefaults(suiteName: "video.\(UUID().uuidString)") ?? .standard
        let app = await ScreenSnapshotCase.SignedInApp(transport: transport, defaults: defaults)
        let detail = ContactDetailModel(
            container: app.container,
            workspaceId: app.workspaceId,
            contactId: "contact_contract_1",
            role: role
        )
        await detail.load()
        guard case let .content(loaded) = detail.state else {
            throw NotLoaded(state: "\(detail.state) \(transport.sentRequests)")
        }
        let model = ContactVideoCallModel(container: app.container, workspaceId: app.workspaceId, role: role)
        await model.start(with: loaded.contact)
        return (model, transport)
    }

    /// The recorded contact with `fields` blanked, for the address the invitation goes to.
    private static func contact(without fields: [String]) -> FixtureTransport.Rule {
        .get("\(api)/contacts/get", .edited("mobile/district-contact-detail.json") { body in
            var contact = body["contact"] as? [String: Any] ?? [:]
            for field in fields {
                contact[field] = NSNull()
            }
            body["contact"] = contact
        })
    }

    func testTheInvitationGoesByTextToTheContactsPhone() async throws {
        let (model, transport) = try await start(Self.rules())
        guard case .sent = model.phase else {
            return XCTFail("should be sent: \(model.phase) \(transport.sentRequests)")
        }
        model.reset()
        guard case .idle = model.phase else {
            return XCTFail("should be idle: \(model.phase)")
        }
    }

    func testWithoutAPhoneTheInvitationGoesByEmail() async throws {
        let (model, transport) = try await start(Self.rules(contact: Self.contact(without: ["phoneNumber"])))
        guard case .sent = model.phase else {
            return XCTFail("should be sent: \(model.phase) \(transport.sentRequests)")
        }
    }

    /// ⚠️ NO ADDRESS, NO CALL: nothing is requested.
    func testWithoutAnyAddressNothingIsRequested() async throws {
        let (model, transport) = try await start(Self.rules(contact: Self.contact(without: ["phoneNumber", "email"])))
        guard case let .failed(failure) = model.phase else {
            return XCTFail("should have failed: \(model.phase)")
        }
        XCTAssertEqual(failure.message, ContactVideoCopy.noAddress)
        XCTAssertFalse(transport.sentRequests.contains { !$0.hasPrefix("GET") })
    }

    func testARefusedTokenIsAFailure() async throws {
        let (model, transport) = try await start(Self.rules(token: .status(500)))
        guard case .failed = model.phase else {
            return XCTFail("should have failed: \(model.phase)")
        }
        XCTAssertFalse(transport.sentRequests.contains { $0.contains("/messages") && !$0.hasPrefix("GET") })
    }

    /// A token without a guest link cannot be turned into an invitation.
    func testATokenWithoutAGuestLinkIsNotSent() async throws {
        let token = FixtureTransport.Reply.edited("mobile/district-room-token.json") { body in
            body.removeValue(forKey: "guestPath")
        }
        let (model, _) = try await start(Self.rules(token: token))
        guard case let .failed(failure) = model.phase else {
            return XCTFail("should have failed: \(model.phase)")
        }
        XCTAssertEqual(failure.message, ContactVideoCopy.noInvite)
    }

    func testARefusedInvitationIsAFailure() async throws {
        let (model, _) = try await start(Self.rules(send: .status(500)))
        guard case .failed = model.phase else {
            return XCTFail("should have failed: \(model.phase)")
        }
    }

    func testAReadOnlyRoleStartsNothing() async throws {
        let (model, transport) = try await start(Self.rules(), role: nil)
        XCTAssertFalse(model.canStart)
        guard case .idle = model.phase else {
            return XCTFail("should be idle: \(model.phase)")
        }
        XCTAssertFalse(transport.sentRequests.contains { !$0.hasPrefix("GET") })
    }
}
