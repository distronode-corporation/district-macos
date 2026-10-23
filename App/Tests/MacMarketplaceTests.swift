import DistrictAuthCore
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import XCTest

/// Phone numbers: the role words the caption and gates the provisioning controls, and
/// opening the screen reads only what the workspace holds.
///
/// ⚠️ MAC ONLY. iOS at `4777c40` carries no test of its own for these models beyond
/// ``StoreCopyTests``; these hold the two rules the screen's comments call load-bearing.
@MainActor
final class MacMarketplaceTests: XCTestCase {
    /// ⛔ A NIL ROLE ERRS LOW: "could not be established", never "assume client".
    func test_MAC_NUMBERS_1_theRoleWordsTheCaptionAndGatesProvisioning() async {
        let (container, _) = await Self.container()
        for (role, mutates) in [(WorkspaceRole.agency, true), (.client, true), (.viewer, false), (nil, false)] {
            let model = MarketplaceModel(container: container, workspaceId: "ws_1", role: role)
            let provisioning = NumberProvisioningModel(container: container, workspaceId: "ws_1", role: role)
            XCTAssertEqual(model.canChangeNumbers, mutates, "\(String(describing: role))")
            XCTAssertEqual(provisioning.canProvision, mutates, "\(String(describing: role))")
            // ⚠️ 3.0.2, AP-031: no second line for a role that can change numbers.
            XCTAssertEqual(model.readOnlyCaption, mutates ? nil : MarketplaceCopy.readOnlyViewer)
        }
    }

    /// ⚠️ A VIEWER IS TOLD WHO CAN CHANGE NUMBERS ONCE PER SCREEN. Registrations and Carrier
    /// say it in their own content (``MarketplaceCopy/viewerCannotProvision``), so the caption
    /// under them says nothing; a viewer there read "needs an agency or client role. Ask
    /// someone on this workspace who has one." twice.
    func test_MAC_NUMBERS_3_theViewerRefusalIsSaidOncePerTab() async {
        let (container, _) = await Self.container()
        for role in [WorkspaceRole.agency, .client, .viewer, nil] {
            let model = MarketplaceModel(container: container, workspaceId: "ws_1", role: role)
            for tab in MarketplaceTab.allCases {
                model.selectTab(tab)
                let expected = model.canChangeNumbers || tab.statesTheViewerRefusal
                    ? nil : MarketplaceCopy.readOnlyViewer
                XCTAssertEqual(model.readOnlyCaption, expected, "\(String(describing: role)) on \(tab)")
            }
        }
        XCTAssertEqual(MarketplaceTab.allCases.filter(\.statesTheViewerRefusal), [.registrations, .carrier])
    }

    /// ⛔ THE OWNED LIST LOADS ON ENTRY AND NOTHING ELSE DOES: a search is a carrier query
    /// nobody asked for, and the filing list spends a carrier call per bundle.
    func test_MAC_NUMBERS_2_openingReadsTheOwnedListOnly() async {
        let (container, transport) = await Self.container()
        let model = MarketplaceModel(container: container, workspaceId: "ws_1", role: .agency)
        await model.loadOwned()
        XCTAssertEqual(transport.paths.count, 1, "\(transport.paths)")
        XCTAssertFalse(transport.paths.contains { $0.contains("search") }, "\(transport.paths)")
    }

    private static func container() async -> (AppContainer, FailingTransport) {
        let transport = FailingTransport()
        let container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        await container.coordinator.adopt(
            NativeTokens(
                accessToken: "access",
                accessTokenExpiresAt: now + 3_600_000,
                refreshToken: "refresh",
                refreshTokenExpiresAt: now + 86_400_000
            ),
            deviceId: container.deviceId
        )
        return (container, transport)
    }
}

/// Records each path and answers 500, so a test counts requests without canned bodies.
private final class FailingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var paths: [String] {
        lock.withLock { recorded }
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request.url.path) }
        return HTTPResponse(statusCode: 500, headers: [:], body: Data(#"{"error":"down"}"#.utf8))
    }
}
