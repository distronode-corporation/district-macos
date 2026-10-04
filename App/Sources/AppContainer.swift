import DistrictAuthCore
import DistrictData
import DistrictNetwork
import Foundation
import OSLog

/// The object graph, wired by hand. Ported from district-ios, cut to what this wave's
/// screens use; later waves add the repositories their screens need, the same way.
///
/// ⛔ EXACTLY ONE ``TokenRefreshCoordinator`` EXISTS PER PROCESS AND IT IS HELD HERE. The
/// server's refresh rotation is single-use: a refresh token presented twice is read as a
/// stolen one being replayed and revokes the whole token family. The coordinator's
/// single-flight gate prevents that, and a second coordinator would be a second gate,
/// each unaware of the other. So there is no factory, no `static let shared` and no
/// second construction site: `DistrictMacApp` builds one and passes it down.
///
/// ⚠️ `@MainActor` because the UI owns it. Everything underneath is an actor or a
/// `Sendable` value, so ``api`` can be copied off the main actor.
@MainActor
final class AppContainer {
    let coordinator: TokenRefreshCoordinator
    let api: ApiClient
    let login: WebAuthLoginController
    let appleLogin: AppleSignInController
    let deviceId: String
    /// This Mac's name as sent on sign-in, read once at launch.
    let deviceName: String?
    /// The one origin this client talks to; web hand-offs are derived from it.
    let baseURL: URL

    // MARK: - Repositories (each wraps the one `api`, so all share one coordinator)

    let workspaces: WorkspaceRepository
    /// The native Voice Studio: one read, and a save through the persona PATCH that is
    /// always followed by that read.
    ///
    /// ⚠️ COMPUTED, NOT STORED, ON THE MAC: the repository is a stateless value over ``api``,
    /// and one more assignment would take `init` past SwiftLint's 60-line body limit.
    var voiceStudio: VoiceStudioRepository {
        VoiceStudioRepository(client: api)
    }

    /// Who answers a call, and whether THIS person can be rung for one (Account's
    /// "Calls to you" card).
    ///
    /// ⛔ NOT PART OF ``workspaces`` DESPITE THE SHARED PATH PREFIX: the seam is the SCOPE.
    /// `workspace/availability` writes the CALLER'S OWN membership row and takes no identity
    /// to do it with.
    let callHandling: CallHandlingRepository

    let overview: OverviewRepository

    let calls: CallsRepository

    /// Placing one outbound call. ⛔ Never retried; see the ⛔ on `DialerModel`.
    let dial: DialRepository

    /// The answer route for a call ringing on this Mac.
    ///
    /// ⛔ A SEPARATE REPOSITORY FROM ``dial`` EVEN THOUGH BOTH END IN A LiveKit CREDENTIAL,
    /// AND THE SPLIT IS THE SERVER'S OWN: a screen that answers cannot dial and a screen
    /// that dials cannot answer.
    let inboundCalls: InboundCallRepository

    /// The meetings archive: the workspace's rooms history and one meeting's record.
    /// ⚠️ READS ONLY; the split from ``rooms`` is that type's own ⛔.
    let meetings: MeetingsRepository

    /// The credential that joins one `meet_` room. ⛔ Every call mints a fresh twelve-hour
    /// guest invite that grants publish rights, so the surface that can hand one out is one
    /// repository rather than a method on a reader.
    let rooms: RoomsRepository

    /// The platform half of a live call: the engine, the call and room claims, and the
    /// microphone and speaker. ⛔ ONE PER PROCESS. `calls` above is the call LOG.
    let callStack: CallStack

    let contacts: ContactsRepository

    /// Who this account has blocked.
    ///
    /// ⛔ THE ONLY MUTABLE OBSERVABLE ON THIS CONTAINER, AND IT IS HERE RATHER THAN IN AN
    /// `@Environment` BECAUSE SEVERAL SCREENS IN THREE SECTIONS READ IT: the screen that
    /// performs a block (a thread) and the one that must stop showing it (the Inbox list)
    /// hold different models. ⚠️ A cache, not an authority. See the type.
    let blockedContacts: BlockedContactsStore

    let inbox: InboxRepository

    /// This workspace's own support requests WITH DISTRONODE (`district/support/*`): the
    /// Support section, and reporting a message or a call (`ReportContentModel`).
    /// ⛔ NOT ``desk``: the two share every noun and differ by one path segment, and the
    /// reply field differs too (support takes `body`, desk takes `message`).
    let support: SupportRepository

    /// District Desk: the tenant's OWN customers' ticket queue (`district/desk/*`).
    /// ⛔ NOT ``support``; the direction is reversed. ⚠️ `deskEnabled` is `Bool?` and null
    /// is not false: it means the question could not be asked.
    let desk: DeskRepository
    let devices: DevicesRepository

    /// The analytics window and the two metered-usage reads. ⚠️ Each method answers its own
    /// `Result`, so a usage failure stays inside one card while the figures stay up.
    let analytics: AnalyticsRepository

    /// District HQ. ⛔ ITS `confirm` EXECUTES AN ARBITRARY WRITE (a persona change, a
    /// deletion, a real email or SMS to a customer); nothing may retry it, and it takes only
    /// an ``HqPendingWrite`` that came out of a prompt response.
    let hq: HQRepository

    /// The plan we own, and the invoices Stripe owns: two reads that fail independently.
    /// ⛔ IT HAS NO WRITES AND MUST NOT GAIN ANY. Offering a plan change, a cancellation or
    /// a portal URL in-app breaches App Store Review Guideline 3.1.3(b), in both Mac builds
    /// (they ship under one bundle id, and the store one is reviewed).
    let billing: BillingRepository

    /// The automation monitor: the workflow list, one workflow's runs, and the always-on
    /// SDR campaign. ⚠️ Each method answers its own `Result`, so a campaign read that failed
    /// cannot blank a workflow list that answered.
    let workflows: WorkflowsRepository

    /// The workspace knowledge base: what the agent may answer FROM, and where.
    /// ⛔ ITS OWN REPOSITORY RATHER THAN MORE ``workspaces``: here the READS admit a viewer
    /// and only the writes exclude one, while every `workspace/config` call excludes one.
    let knowledge: KnowledgeRepository

    /// The workspace's outbound carrier accounts: one read, five writes, a credential probe.
    /// ⛔ Same role split as ``knowledge``. Nothing here may be retried: a save with no
    /// `accountId` mints a fresh account, and the probe calls a third party per request.
    let messaging: MessagingRepository

    /// Phone numbers: what the workspace holds, a carrier's inventory, the registrations and
    /// the carrier account. ⛔ NO PURCHASE METHOD EXISTS IN THE CORE (Guideline 3.1.1), so
    /// buying a number is unconstructible here, not merely undrawn. ⚠️ Each read answers its
    /// own `Result`, so a failed search cannot blank the owned list.
    let numbers: NumbersRepository

    /// The core's push repository, registering this Mac's ALERT token with
    /// `platform: "macos"`, unregistering it and forgetting it on sign-out. Built by
    /// ``pushTokenRepository(client:memory:)``.
    let pushTokens: PushTokenRepository

    /// The workspace's booking pages: the tenancy's state, and the one call that
    /// provisions one.
    let scheduling: SchedulingRepository

    /// The catalogued scheduling admin operations (``SchedulingAdminOp``).
    ///
    /// ⛔ A SEPARATE REPOSITORY FROM ``scheduling`` EVEN THOUGH BOTH ARE "SCHEDULING", AND
    /// THE SPLIT IS THE SERVER'S. ``scheduling`` talks to District's own `scheduling/status`
    /// and `scheduling/enable`; this one posts an `op` NAME to `scheduling/admin`, which
    /// proxies into the scheduler's own API through an allowlist. Different routes,
    /// different failure vocabularies (``ApiError`` against ``SchedulingAdminError``) and
    /// different role rules.
    ///
    /// ⚠️ AN UNKNOWN OP TRAPS IN A DEBUG BUILD (``schedulingAdmin(client:)``): a **400 `unknown_op`**
    /// means ``SchedulingAdminOp`` and the server's `ADMIN_OPS` have diverged, a programmer
    /// error nothing a user does can cause.
    let schedulingAdmin: SchedulingAdminRepository

    /// The image uploads (the profile avatar and the branding images). ⛔ Its own type
    /// because an upload is multipart rather than an `op` post.
    let schedulingAdminMedia: SchedulingAdminMediaRepository

    /// The scheduler hand-off whose 302 is read rather than followed, for the calendar
    /// connect round trip (``SchedulingCalendarConnectModel``).
    ///
    /// ⚠️ IT SHARES THE ONE TRANSPORT AND THE ONE ``TokenRefreshCoordinator`` with ``api``:
    /// a second transport would be a second redirect policy and a second coordinator a
    /// second single-flight gate.
    let schedulingSSO: SchedulingSSOClient

    /// Minting the scheduling hand-off URL.
    let schedulingHandoff: SchedulingHandoffClient

    /// The bound hand-off (S33): leg 1 in the browser, the `districtai://handoff`
    /// callback, then the mint. ⛔ ONE PER PROCESS, which is what lets the callback that
    /// `.onOpenURL` delivers find the hand-off the Scheduling section started.
    let schedulingHandoffFlow: SchedulingHandoffFlow

    /// The single sign-out orchestrator: unregister, revoke (with its outbox), wipe.
    let signOutCoordinator: SignOutCoordinator

    /// - Parameter microphone: the permission both call models ask. ⚠️ The live one everywhere
    ///   but a test, which passes a fake so no system alert can stop the run.
    /// - Parameter transport: the HTTP layer every client shares. ⚠️ URLSession everywhere but
    ///   a test that drives a whole screen against canned replies (`MacListSectionLoadTests`).
    /// - Parameter tokenStore: where the session persists. nil is the keychain, the only
    ///   correct store for the app; ⛔ a test passes an in-memory one, which in the app would
    ///   sign the user out on every cold start (see `InMemoryTokenStore`).
    init(
        baseURL: URL = ApiClient.productionBaseURL,
        microphone: any MicrophoneAccess = LiveMicrophoneAccess(),
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        tokenStore: (any TokenStore)? = nil
    ) {
        // ⛔ THE LEDGER FIRST, BEFORE `DeviceIdentity.current()` MINTS AN ID: a missing id
        // is how a fresh install is recognised. See ``FreshInstallTokenStore``.
        let ledger = UserDefaultsInstallationLedger.begin()
        let store = FreshInstallTokenStore(base: tokenStore ?? KeychainTokenStore(), ledger: ledger)
        let deviceId = DeviceIdentity.current()
        let deviceName = MacDeviceName.current()
        let auth = AppNativeAuthClient(baseURL: baseURL, transport: transport)
        // ⚠️ `auth` AS THE REVOKE CLIENT TOO, so a successor that lands after a sign-out is
        // revoked at once rather than waiting in the outbox.
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: auth, revokeClient: auth)
        let bearer = Self.bearer(coordinator)

        self.coordinator = coordinator
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.baseURL = baseURL
        signOutCoordinator = SignOutCoordinator(coordinator: coordinator, store: store, revokeClient: auth)

        // ⛔ THE BEARER IS AN ASYNC CLOSURE, NOT AN INTERCEPTOR: acquiring a token may mean
        // waiting behind the coordinator's single-flight refresh.
        api = ApiClient(
            baseURL: baseURL,
            transport: transport,
            accessToken: bearer,
            rejectedToken: Self.rejected(coordinator)
        )

        workspaces = WorkspaceRepository(client: api)
        callHandling = CallHandlingRepository(client: api)
        overview = OverviewRepository(client: api)
        calls = CallsRepository(client: api)
        dial = DialRepository(client: api)
        inboundCalls = InboundCallRepository(client: api)
        meetings = MeetingsRepository(client: api)
        rooms = RoomsRepository(client: api)
        callStack = CallStack(microphone: microphone)
        contacts = ContactsRepository(client: api)
        // ⚠️ FROM THE ONE `contacts` ABOVE, never a fresh repository.
        blockedContacts = BlockedContactsStore(contacts: contacts)
        inbox = InboxRepository(client: api)
        support = SupportRepository(client: api)
        desk = DeskRepository(client: api)
        devices = DevicesRepository(client: api)
        analytics = AnalyticsRepository(client: api)
        hq = HQRepository(client: api)
        billing = BillingRepository(client: api)
        workflows = WorkflowsRepository(client: api)
        knowledge = KnowledgeRepository(client: api)
        messaging = MessagingRepository(client: api)
        numbers = NumbersRepository(client: api)
        pushTokens = Self.pushTokenRepository(client: api, memory: UserDefaultsPushTokenMemory())
        scheduling = SchedulingRepository(client: api)
        schedulingAdmin = Self.schedulingAdmin(client: api)
        schedulingAdminMedia = SchedulingAdminMediaRepository(client: api)
        schedulingSSO = SchedulingSSOClient(baseURL: baseURL, transport: transport, accessToken: bearer)
        schedulingHandoff = SchedulingHandoffClient(client: api)
        schedulingHandoffFlow = Self.handoffFlow(schedulingHandoff)

        login = WebAuthLoginController(
            baseURL: baseURL,
            exchange: auth,
            coordinator: coordinator,
            deviceId: deviceId,
            deviceName: deviceName
        )
        appleLogin = AppleSignInController(
            exchange: auth,
            coordinator: coordinator,
            deviceId: deviceId,
            deviceName: deviceName
        )
    }

    /// The push repository, as this app registers with it.
    ///
    /// ⛔ `platform: .macos`, STATED HERE AND NOWHERE ELSE. The core defaults it to `.ios`,
    /// which would route this Mac's pushes as an iOS device. `MacClientPlatformTests` pins
    /// the register body as `{"token", "platform":"macos"}`, with no `kind`: the alert
    /// token is the only push this Mac registers here (presence, `kind: "desktop"`, is
    /// `DistrictLive`'s), and the server refuses `voip` from a Mac, so
    /// ``PushTokenRepository/registerVoip(token:)`` is never called.
    nonisolated static func pushTokenRepository(client: ApiClient, memory: any PushTokenMemory) -> PushTokenRepository {
        PushTokenRepository(client: client, memory: memory, platform: .macos)
    }

    /// Sign out, on the server and locally.
    ///
    /// ⛔ THE ORDER IS UNREGISTER, THEN REVOKE, THEN FORGET, and only the first two are
    /// here. `beforeRevoke` (the push unregister) authenticates with the ACCESS token, so
    /// it must run before the revoke ends the session. A failed unregister must not stop
    /// the revoke, which is why the hook returns nothing.
    func signOut(beforeRevoke: () async -> Void = {}) async {
        await beforeRevoke()
        await signOutCoordinator.signOut()
    }

    /// Finish any sign-out whose revoke never reached the server. Called on every launch.
    func drainPendingRevoke() async {
        await signOutCoordinator.drainPendingRevoke()
    }

    // MARK: - Credential closures

    /// ⛔ Only `.available` carries a token; every other outcome sends NO Authorization
    /// header, and `ApiClient` turns nil into a local 401.
    static func bearer(_ coordinator: TokenRefreshCoordinator) -> @Sendable () async -> String? {
        { [coordinator] in
            guard case let .available(token) = await coordinator.accessToken() else { return nil }
            return token
        }
    }

    /// ⛔ INVALIDATE, NEVER RESEND: drop the refused token so the next call refreshes.
    static func rejected(_ coordinator: TokenRefreshCoordinator) -> @Sendable (String) async -> Void {
        { [coordinator] token in
            _ = await coordinator.invalidateAccessToken(token)
        }
    }

    /// ⛔ AN UNKNOWN OP IS A PROGRAMMER ERROR: THE CLIENT'S CATALOGUE AND THE SERVER'S HAVE
    /// DIVERGED. It traps in a debug build so whoever caused it finds it, and does nothing
    /// in release, where the screen shows the generic sentence instead.
    static func schedulingAdmin(client: ApiClient) -> SchedulingAdminRepository {
        SchedulingAdminRepository(client: client) { op in
            assertionFailure("The server does not know the scheduling admin op '\(op.rawValue)'.")
        }
    }

    /// ⛔ THE LOG LINE NAMES THE PATH AND NOTHING ELSE; the flow never hands it a nonce or
    /// a state, which is why `.public` is safe. `PKCE.newState` supplies the state (32
    /// random bytes, base64url, which the hand-off route accepts).
    static func handoffFlow(_ client: SchedulingHandoffClient) -> SchedulingHandoffFlow {
        let log = Logger(subsystem: "com.distronode.district", category: "SchedulingHandoff")
        return SchedulingHandoffFlow(
            client: client,
            newState: { PKCE.newState() },
            log: { line in log.info("\(line, privacy: .public)") }
        )
    }
}
