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

    /// This workspace's own support requests WITH DISTRONODE. Wave 5 uses it only for
    /// reporting a message or a call (`ReportContentModel`); the Support section is Wave 7.
    let support: SupportRepository
    let devices: DevicesRepository

    /// The core's push repository, registering this Mac's ALERT token with
    /// `platform: "macos"`, unregistering it and forgetting it on sign-out. Built by
    /// ``pushTokenRepository(client:memory:)``.
    let pushTokens: PushTokenRepository

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
    init(baseURL: URL = ApiClient.productionBaseURL, microphone: any MicrophoneAccess = LiveMicrophoneAccess()) {
        let transport = URLSessionHTTPTransport()
        // ⛔ THE LEDGER FIRST, BEFORE `DeviceIdentity.current()` MINTS AN ID: a missing id
        // is how a fresh install is recognised. See ``FreshInstallTokenStore``.
        let ledger = UserDefaultsInstallationLedger.begin()
        let store = FreshInstallTokenStore(base: KeychainTokenStore(), ledger: ledger)
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
        devices = DevicesRepository(client: api)
        pushTokens = Self.pushTokenRepository(client: api, memory: UserDefaultsPushTokenMemory())
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
