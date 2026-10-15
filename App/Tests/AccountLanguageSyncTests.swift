import DistrictAuthCore
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The language signals 3.0 sends: `Accept-Language` on every request, and the account's
/// language written through `POST /api/settings` on sign-in and on a language change
/// (``AccountLanguageSync``).
@MainActor
final class AccountLanguageSyncTests: XCTestCase {
    // MARK: - When the language is written

    /// ⛔ A SIGNED-IN SESSION WRITES THE APP'S LANGUAGE, AND REMEMBERS IT.
    func test_MAC_LANG_01_aSignedInSessionWritesTheLanguage() async {
        let harness = SyncHarness(current: .frCA)

        harness.sync.sessionChanged(.signedIn)
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.frCA])
        XCTAssertEqual(harness.sync.written, .frCA)
    }

    /// ⚠️ A SESSION FOUND AT LAUNCH, IN THE LANGUAGE ALREADY WRITTEN, SENDS NOTHING.
    func test_MAC_LANG_02_theSameLanguageIsNotWrittenTwice() async {
        let harness = SyncHarness(current: .en)
        harness.defaults.set("en", forKey: AccountLanguageSync.defaultsKey)

        harness.sync.sessionChanged(.signedIn)
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [])
    }

    /// ⛔ A LANGUAGE CHOSEN WHILE THE APP WAS CLOSED reaches the server at the next launch.
    func test_MAC_LANG_03_aLanguageChangedSinceTheLastWriteIsWrittenAtLaunch() async {
        let harness = SyncHarness(current: .frCA)
        harness.defaults.set("en", forKey: AccountLanguageSync.defaultsKey)

        harness.sync.sessionChanged(.signedIn)
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.frCA])
        XCTAssertEqual(harness.sync.written, .frCA)
    }

    /// ⛔ EVERY COMPLETED SIGN-IN WRITES, even in the language this Mac stored last: the
    /// account may be someone else's.
    func test_MAC_LANG_04_aCompletedSignInAlwaysWrites() async {
        let harness = SyncHarness(current: .en)
        harness.defaults.set("en", forKey: AccountLanguageSync.defaultsKey)

        harness.sync.signInCompleted()
        harness.sync.sessionChanged(.signedIn)
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.en])
    }

    /// A language change while signed in is written; one while signed out, or while the
    /// session cannot be checked, is not.
    func test_MAC_LANG_05_aLanguageChangeIsWrittenOnlyWhileSignedIn() async {
        let harness = SyncHarness(current: .en)
        harness.sync.languageChanged()
        harness.sync.sessionChanged(.unavailable("offline"))
        harness.sync.languageChanged()
        await harness.settle()
        XCTAssertEqual(harness.saves.values, [])

        harness.sync.sessionChanged(.signedIn)
        await harness.settle()
        harness.current.value = .frCA
        harness.sync.languageChanged()
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.en, .frCA])
        XCTAssertEqual(harness.sync.written, .frCA)
    }

    /// ⛔ ONE WRITE AT A TIME, AND THE LAST LANGUAGE WINS: a change during a write is written
    /// after it, never beside it.
    func test_MAC_LANG_06_aChangeDuringAWriteIsWrittenAfterIt() async {
        let harness = SyncHarness(current: .en)
        harness.saves.hold = true

        harness.sync.sessionChanged(.signedIn)
        await harness.saves.waitForCalls(1)
        harness.current.value = .frCA
        harness.sync.languageChanged()
        XCTAssertEqual(harness.saves.values, [.en], "nothing beside the write on its way")

        harness.saves.release()
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.en, .frCA])
        XCTAssertEqual(harness.sync.written, .frCA)
    }

    /// ⚠️ A REFUSED WRITE REMEMBERS NOTHING, so the next trigger writes again.
    func test_MAC_LANG_07_aFailedWriteIsTriedAgainOnTheNextTrigger() async {
        let harness = SyncHarness(current: .frCA)
        harness.saves.outcome = .failure(.http(status: 500, message: nil))

        harness.sync.sessionChanged(.signedIn)
        await harness.settle()
        XCTAssertNil(harness.sync.written)

        harness.saves.outcome = .success(())
        harness.sync.languageChanged()
        await harness.settle()

        XCTAssertEqual(harness.saves.values, [.frCA, .frCA])
        XCTAssertEqual(harness.sync.written, .frCA)
    }

    /// ⛔ A SIGN-OUT FORGETS THE LANGUAGE, and a write that lands after it is not recorded.
    func test_MAC_LANG_08_aSignOutForgetsAndDropsTheWriteOnItsWay() async {
        let harness = SyncHarness(current: .frCA)
        harness.saves.hold = true

        harness.sync.sessionChanged(.signedIn)
        await harness.saves.waitForCalls(1)
        harness.sync.sessionChanged(.signedOut(""))
        harness.saves.release()
        await harness.settle()

        XCTAssertNil(harness.sync.written)
        XCTAssertNil(harness.sync.writing)
    }

    // MARK: - Through the session and the core, on the wire

    /// ⛔ THE REQUEST ITSELF: `POST /api/settings` with `{"profile":{"locale":"fr"}}` (the
    /// route's `en`/`fr`, never the tag), and `Accept-Language: fr-CA` on it.
    func test_MAC_LANG_09_aFrenchSessionPostsFrWithAFrenchAcceptLanguage() async throws {
        let harness = await SessionHarness()

        await L10nRuntime.$scoped.withValue(.frCA) {
            await harness.session.refreshPhase()
            await harness.settle()
        }

        let posts = harness.transport.requests.filter { $0.url.path == "/api/settings" }
        XCTAssertEqual(posts.count, 1)
        let post = try XCTUnwrap(posts.first)
        XCTAssertEqual(post.method, .post)
        XCTAssertEqual(post.headers["Accept-Language"], "fr-CA")
        let body = try XCTUnwrap(post.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["profile"], "only the locale is sent")
        XCTAssertEqual(json["profile"] as? [String: String], ["locale": "fr"])
        XCTAssertEqual(harness.defaults.string(forKey: AccountLanguageSync.defaultsKey), "fr-CA")
    }

    /// The same in English: `"locale":"en"` and `Accept-Language: en`.
    func test_MAC_LANG_10_anEnglishSessionPostsEnWithAnEnglishAcceptLanguage() async throws {
        let harness = await SessionHarness()

        await harness.session.refreshPhase()
        await harness.settle()

        let post = try XCTUnwrap(harness.transport.requests.first { $0.url.path == "/api/settings" })
        XCTAssertEqual(post.headers["Accept-Language"], "en")
        let body = try XCTUnwrap(post.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["profile"] as? [String: String], ["locale": "en"])
    }

    /// ⛔ A SESSION THE SERVER ENDED forgets what was written, and posts nothing.
    func test_MAC_LANG_11_aSignedOutSessionPostsNothingAndForgets() async {
        let harness = await SessionHarness(signedIn: false)
        harness.defaults.set("fr-CA", forKey: AccountLanguageSync.defaultsKey)

        await harness.session.refreshPhase()
        await harness.settle()

        XCTAssertFalse(harness.transport.requests.contains { $0.url.path == "/api/settings" })
        XCTAssertNil(harness.defaults.string(forKey: AccountLanguageSync.defaultsKey))
    }

    /// ⛔ THE ONE REQUEST THE APP BUILDS ITSELF (the scheduler hand-off) says its language
    /// too, as every request through the core's client does.
    func test_MAC_LANG_12_theSchedulerHandOffSendsAcceptLanguage() async throws {
        for (locale, tag) in [(L10nLocale.en, "en"), (.frCA, "fr-CA")] {
            let transport = RecordingTransport([
                .success(HTTPResponse(statusCode: 302, headers: ["Location": "https://example.invalid/x"], body: nil)),
            ])
            let base = try XCTUnwrap(URL(string: "https://api.invalid"))
            let sso = SchedulingSSOClient(
                baseURL: base,
                transport: transport,
                accessToken: { "session-token" }
            )
            _ = await L10nRuntime.$scoped.withValue(locale) {
                await sso.handOffURL(workspaceId: "ws_1", next: "/v1/calendar")
            }
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.headers["Accept-Language"], tag)
        }
    }
}

// MARK: - Harnesses

/// A value a test changes and the sync reads.
@MainActor
private final class Box<T> {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

/// The save, recorded, answering `outcome`, and held until released when `hold` is set.
private final class RecordedSaves: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [L10nLocale] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var _outcome: Result<Void, ApiError> = .success(())
    private var _hold = false

    var values: [L10nLocale] {
        lock.withLock { recorded }
    }

    var outcome: Result<Void, ApiError> {
        get { lock.withLock { _outcome } }
        set { lock.withLock { _outcome = newValue } }
    }

    var hold: Bool {
        get { lock.withLock { _hold } }
        set { lock.withLock { _hold = newValue } }
    }

    func save(_ locale: L10nLocale) async -> Result<Void, ApiError> {
        let held = lock.withLock {
            recorded.append(locale)
            return _hold
        }
        if held {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting.append(continuation) }
            }
        }
        return outcome
    }

    func waitForCalls(_ count: Int) async {
        while values.count < count || lock.withLock({ waiting.isEmpty }) {
            await Task.yield()
        }
    }

    func release() {
        let resumed = lock.withLock {
            _hold = false
            defer { waiting = [] }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }
}

@MainActor
private struct SyncHarness {
    let saves: RecordedSaves
    let current: Box<L10nLocale>
    let defaults: UserDefaults
    let sync: AccountLanguageSync

    init(current language: L10nLocale) {
        let current = Box(language)
        let saves = RecordedSaves()
        self.saves = saves
        self.current = current
        defaults = UserDefaults(suiteName: "AccountLanguageSyncTests-\(UUID().uuidString)") ?? .standard
        sync = AccountLanguageSync(
            save: { await saves.save($0) },
            defaults: defaults,
            current: { current.value }
        )
    }

    /// Until no write is on its way, including one a finished write started.
    func settle() async {
        while let writing = sync.writing {
            await writing.value
        }
    }
}

/// A whole session over an in-memory sign-in: `workspace/list` and `POST /api/settings`
/// answered, everything recorded.
@MainActor
private struct SessionHarness {
    let transport = LocaleSaveTransport()
    let defaults: UserDefaults
    let language: AccountLanguageSync
    let session: SessionModel

    init(signedIn: Bool = true) async {
        let container = AppContainer(
            baseURL: URL(string: "https://api.invalid")!,
            microphone: FakeMicrophoneAccess(status: .denied),
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )
        if signedIn {
            let hour: Int64 = 3_600_000
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            await container.coordinator.adopt(
                NativeTokens(
                    accessToken: "access",
                    accessTokenExpiresAt: now + hour,
                    refreshToken: "refresh",
                    refreshTokenExpiresAt: now + 24 * hour
                ),
                deviceId: container.deviceId
            )
        }
        defaults = UserDefaults(suiteName: "AccountLanguageSyncTests-\(UUID().uuidString)") ?? .standard
        let settings = container.accountSettings
        language = AccountLanguageSync(save: { await settings.saveLocale($0) }, defaults: defaults)
        session = SessionModel(
            container: container,
            push: PushRegistrar(container: container, system: .silent),
            language: language,
            selection: WorkspaceSelectionStore(defaults: defaults)
        )
    }

    func settle() async {
        while let writing = language.writing {
            await writing.value
        }
    }
}

/// Answers `POST /api/settings` as the route does, and 404 to anything else.
private final class LocaleSaveTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        guard request.url.path == "/api/settings" else {
            return HTTPResponse(statusCode: 404, headers: [:], body: Data(#"{"error":"not_found"}"#.utf8))
        }
        let body = #"{"success":true,"message":"Settings updated successfully"}"#
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}
