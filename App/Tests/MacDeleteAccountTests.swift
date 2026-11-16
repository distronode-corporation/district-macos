import DistrictAuthCore
@testable import DistrictMac
import DistrictNetwork
import Foundation
import XCTest

/// The Mac half of account deletion: what this Mac forgets after the service deleted the
/// account, and how the re-authentication window is built.
@MainActor
final class MacDeleteAccountTests: XCTestCase {
    /// ⛔ AFTER A DELETION THE MAC FORGETS THE SESSION AND SENDS NOTHING. No revoke, no push
    /// unregister and no presence unregister: each would authenticate as an account that no
    /// longer exists. The sign-in screen says the account was deleted.
    func test_MAC_DELETE_01_aDeletedAccountIsForgottenWithNoRequest() async throws {
        let harness = await DeletedHarness()
        harness.selection.setSelectedWorkspaceId("ws-1")

        await harness.session.finishDeletedAccount(externalErasurePending: false)

        XCTAssertEqual(harness.session.phase, .signedOut(DeleteAccountCopy.deleted))
        XCTAssertTrue(harness.transport.requests.isEmpty, "\(harness.transport.paths)")
        let stored = try await harness.store.read()
        XCTAssertNil(stored, "the keychain session is gone")
        let outbox = try await harness.store.pendingRevokeToken()
        XCTAssertNil(outbox, "no revoke is queued for a credential that no longer exists")
        XCTAssertNil(harness.selection.selectedWorkspaceId(), "the next person lands in no workspace")
    }

    /// ⚠️ THE SERVICE'S `externalErasurePending`: deleted either way, and said so first.
    func test_MAC_DELETE_02_vendorErasureStillPendingIsSaid() async {
        let harness = await DeletedHarness()
        await harness.session.finishDeletedAccount(externalErasurePending: true)
        XCTAssertEqual(harness.session.phase, .signedOut(DeleteAccountCopy.deletedErasurePending))
        XCTAssertTrue(DeleteAccountCopy.deletedErasurePending.hasPrefix(DeleteAccountCopy.deleted))
    }

    /// ⛔ THE RE-AUTHENTICATION WINDOW IS BUILT BY ``WebAuthLoginController/makeSession(url:resumer:)``,
    /// whose completion handler is not main-actor isolated (`MacWebAuthIsolationTests`). A
    /// session built inline in the `@MainActor` file would trap the moment the window closed,
    /// as every sign-in did in build 20012.
    func test_MAC_DELETE_03_theReauthWindowUsesTheIsolationSafeSession() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .appendingPathComponent("Sources/Features/Account/ReauthSheetController.swift")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "sources are not beside this test")
        let code = try SourceComments.stripped(String(contentsOf: file, encoding: .utf8))
        XCTAssertTrue(code.contains("WebAuthLoginController.makeSession(url: url, resumer: resumer)"))
        XCTAssertFalse(code.contains("ASWebAuthenticationSession("), "no session built in this file")
        XCTAssertTrue(code.contains("prefersEphemeralWebBrowserSession = false"), "the browser's own cookie")
    }

    /// ⚠️ THE ROW OPENS THE SHEET, NOT THE PAGE: the deletion page's address stays only as the
    /// store listings' data-deletion URL.
    func test_MAC_DELETE_04_theAccountRowNoLongerOpensTheDeletionPage() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Account/AccountView.swift")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "sources are not beside this test")
        let code = try SourceComments.stripped(String(contentsOf: file, encoding: .utf8))
        XCTAssertTrue(code.contains("DeleteAccountView(container: container, session: session)"))
        XCTAssertFalse(code.contains("openURL"), "no hand-off to the browser from Account")
        XCTAssertEqual(code.components(separatedBy: "accountDeletionURL").count - 1, 1, "declared, never opened")
    }

    /// ⛔ EVERY BUTTON IN THE SHEET'S BOTTOM ROW HAS THE PALETTE'S LARGE TREATMENT (visual QA,
    /// #111): no bare system button (a small grey pill in dark mode) and no ghost text button.
    func test_MAC_DELETE_05_theButtonRowIsOneHeightAndTreatment() throws {
        try FooterButtons.assertStyled("DeleteAccountView.swift", until: "private var failureLine", expected: 4)
    }
}

/// The bottom row of a sheet drawn in ``MacSheetChrome``: each `Button(` from its `buttons`
/// property to `endMarker` (the first declaration after the row, in comment-stripped source)
/// takes a palette style, and none is a ghost.
enum FooterButtons {
    static func assertStyled(
        _ name: String,
        in folder: String = "Account",
        until endMarker: String,
        expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/\(folder)/\(name)")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sources are not beside this test")
        let code = try SourceComments.stripped(String(contentsOf: url, encoding: .utf8))
        let start = try XCTUnwrap(code.range(of: "private var buttons: some View {"), file: file, line: line)
        let end = try XCTUnwrap(
            code.range(of: endMarker, range: start.upperBound ..< code.endIndex),
            file: file,
            line: line
        )
        // ⚠️ The default style's modifier name ends in `Button(` too: renamed before splitting.
        let block = String(code[start.upperBound ..< end.lowerBound])
            .replacingOccurrences(of: ".macSheetDefaultButton()", with: ".macSheetDefaultStyle")
        let buttons = block.components(separatedBy: "Button(").dropFirst()
        XCTAssertEqual(buttons.count, expected, "\(name): the row's buttons", file: file, line: line)
        let styles = [
            ".buttonStyle(.districtSecondary)",
            ".buttonStyle(.districtDestructive)",
            ".macSheetDefaultStyle",
        ]
        for button in buttons {
            let head = String(button.prefix(400))
            XCTAssertTrue(
                styles.contains { head.contains($0) },
                "\(name): an unstyled button: \(head.prefix(80))",
                file: file,
                line: line
            )
        }
        XCTAssertFalse(block.contains(".districtGhost"), "\(name): a ghost button in the row", file: file, line: line)
    }
}

/// Comment-stripped source, so a test reads the code and not what the comments say about it.
enum SourceComments {
    static func stripped(_ code: String) -> String {
        code.components(separatedBy: "\n")
            .map { line in
                guard let range = line.range(of: "//") else { return line }
                return String(line[..<range.lowerBound])
            }
            .joined(separator: "\n")
    }
}

// MARK: - Harness

/// A signed-in session over a transport that records every request and answers none.
@MainActor
private struct DeletedHarness {
    let transport = SettingsTransport([])
    let store = InMemoryTokenStore()
    let selection: WorkspaceSelectionStore
    let container: AppContainer
    let session: SessionModel

    init() async {
        let defaults = UserDefaults(suiteName: "MacDeleteAccountTests-\(UUID().uuidString)")!
        selection = WorkspaceSelectionStore(defaults: defaults)
        container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: store,
            pushTokenMemory: InMemoryPushTokenMemory()
        )
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        await container.coordinator.adopt(
            NativeTokens(
                accessToken: "access-1",
                accessTokenExpiresAt: now + 3_600_000,
                refreshToken: "refresh-1",
                refreshTokenExpiresAt: now + 86_400_000
            ),
            deviceId: container.deviceId
        )
        session = SessionModel(
            container: container,
            push: PushRegistrar(container: container, system: .silent),
            selection: selection
        )
    }
}
