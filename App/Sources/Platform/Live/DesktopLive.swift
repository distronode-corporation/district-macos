import AppKit
import DistrictLive
import Foundation
import Observation

/// Where ringing on this Mac stands, for the line under "Ring on this computer".
enum DesktopLiveStatus: Equatable, Sendable {
    /// Not running: the setting is off, nobody is signed in, or the Mac is asleep.
    case off
    /// Starting, or reconnecting after a gap.
    case connecting
    /// The socket is open and the presence registered: a call can ring here.
    case live
    /// Calls cannot ring here right now, for this reason (already worded).
    case unavailable(String)
}

/// What a running live session can be asked to do. ``DesktopLiveSession`` in the app, a
/// recording fake in the tests.
@MainActor
protocol LiveSessionRunning: AnyObject {
    /// Stop the socket and the presence renewals, and withdraw a ring. ⚠️ Sends nothing to
    /// the server: a stopped presence lapses there within ten minutes. See
    /// `DistrictLive.PresenceController.stop()`.
    func stop() async
    /// Stop, then withdraw every registration this installation holds. Before the revoke.
    func signOut() async
    /// The ring this session started has been answered, declined or has ended, so the
    /// gate may take the next one.
    func clearRing()
}

/// What starting a session needs.
struct LiveSessionRequest {
    let workspaceId: String
    let workspaceName: String?
    /// Where the session reports its status.
    let onStatus: @MainActor (DesktopLiveStatus) -> Void
}

/// Ringing on this Mac: the telemetry socket, the presence that makes the server ring it,
/// and the ring gate, kept running exactly while they should be.
///
/// ⛔ RUNNING IS A PURE FUNCTION OF FOUR FACTS, AND EVERY ENTRY POINT ONLY CHANGES A FACT.
/// A session runs while someone is signed in, a workspace is selected, "Ring on this
/// computer" is on, and the Mac is awake (``target``); ``reconcile()`` is the one place
/// that starts or stops one, and it runs serially, so a sleep arriving during a start
/// cannot leave two sockets open or one that nothing will stop.
///
/// ⛔ WHAT STOPS IT, AND WHY EACH ONE MATTERS:
///   * **Sleep** (`NSWorkspace.willSleepNotification`): a sleeping Mac must stop holding
///     callers on a ring nobody hears. The presence stops renewing, a ring is withdrawn,
///     and a live call or meeting is ended (its network is about to vanish anyway). On
///     wake it starts again. ⚠️ THE PRESENCE IS NOT WITHDRAWN, UNLIKE district-linux:
///     the core's unregister deletes every row this installation holds, the Mac's APNs
///     alert row included, so a sleep would also cost the alerts. The row lapses on the
///     server within ten minutes instead.
///   * **Quit** (``terminate()``, from the app delegate): the same, and the app waits
///     briefly for a placed call's carrier hang-up.
///   * **Sign-out** (``signOut()``): BEFORE the revoke, because both the carrier hang-up
///     and the unregister authenticate with the session that is about to end.
///   * **"Ring on this computer" off**: stops the session; nothing else changes.
///
/// ⛔ APP NAP IS HELD OFF WHILE A SESSION RUNS (`ProcessInfo.beginActivity`). A napping app
/// has its timers coalesced and deferred, which would stretch the core's socket renewal,
/// its reconnect backoff and the presence's five-minute renewal past the server's
/// ten-minute freshness window: the Mac would silently stop ringing whenever it was not in
/// front. ⚠️ HELD FOR THE WHOLE SESSION, NOT ONLY WHILE CONNECTED, because the backoff and
/// the renewal are exactly the timers that run while the socket is down.
/// `.userInitiatedAllowingIdleSystemSleep` keeps the Mac free to sleep on its own schedule.
@MainActor
@Observable
final class DesktopLive {
    /// The setting's UserDefaults key. ⛔ PER INSTALLATION, NOT PER ACCOUNT, as on
    /// district-linux (its settings file): whether a computer rings is a fact about the
    /// computer, and it survives a sign-out.
    nonisolated static let ringHereKey = "ringOnThisComputer"

    /// How long a failed start waits before trying again.
    static let retrySeconds: Double = 60

    /// Whether calls handed to this member ring here. ⚠️ ON BY DEFAULT.
    private(set) var ringHere: Bool

    private(set) var status: DesktopLiveStatus = .off

    /// The four facts. See the ⛔ on the type.
    private(set) var signedIn = false
    private(set) var workspaceId: String?
    private(set) var workspaceName: String?
    private(set) var awake = true

    /// The workspace the running session is for, or nil.
    private(set) var runningWorkspaceId: String?

    typealias Factory = @MainActor (LiveSessionRequest) async -> (any LiveSessionRunning)?

    private let factory: Factory
    private let calls: CallStack
    private let setting: RingSetting
    private let beginActivity: @MainActor () -> any NSObjectProtocol
    private let endActivity: @MainActor (any NSObjectProtocol) -> Void
    private var session: (any LiveSessionRunning)?
    private var activity: (any NSObjectProtocol)?
    private var chain: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    init(
        calls: CallStack,
        setting: RingSetting = .standard,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        beginActivity: @escaping @MainActor () -> any NSObjectProtocol = DesktopLive.beginNoNapActivity,
        endActivity: @escaping @MainActor (any NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) },
        factory: @escaping Factory
    ) {
        self.calls = calls
        self.setting = setting
        self.beginActivity = beginActivity
        self.endActivity = endActivity
        self.factory = factory
        ringHere = setting.load() ?? true
        observers = [
            workspaceCenter
                .addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.willSleep() }
                },
            workspaceCenter
                .addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.didWake() }
                },
        ]
    }

    /// The session that should run, if any: the workspace to ring for.
    var target: String? {
        guard signedIn, ringHere, awake, let workspaceId else { return nil }
        return workspaceId
    }

    // MARK: - The facts

    /// The shell has a workspace selected (or none).
    func signedIn(workspaceId: String?, workspaceName: String?) {
        signedIn = true
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        reconcile()
    }

    /// The session ended without this app's sign-out (the server ended it, or it could not
    /// be checked). ⚠️ Nothing is withdrawn: there is no session left to do it with.
    func sessionEnded() {
        signedIn = false
        workspaceId = nil
        reconcile()
    }

    /// "Ring on this computer" was switched.
    func setRingHere(_ on: Bool) {
        ringHere = on
        setting.save(on)
        reconcile()
    }

    func willSleep() {
        awake = false
        reconcile()
        // ⚠️ AFTER THE PRESENCE HAS STOPPED RENEWING (queued first, above), as on
        // district-linux: the presence goes first, then any call (a placed one ended at
        // the carrier) and any meeting.
        let calls = calls
        enqueue { await calls.endEverything(.sleep) }
    }

    func didWake() {
        awake = true
        reconcile()
    }

    /// The local sign-out, BEFORE the revoke. See the ⛔ on the type.
    func signOut() async {
        let calls = calls
        await calls.endEverything(.sessionEnded)
        await calls.drainServerHangUps(within: 3)
        signedIn = false
        workspaceId = nil
        let leaving = session
        session = nil
        runningWorkspaceId = nil
        await settled()
        await leaving?.signOut()
        releaseActivity()
        status = .off
    }

    /// The app is quitting. ⚠️ Bounded: a quit must not hang on a network that has gone.
    func terminate() async {
        awake = false
        reconcile()
        await settled()
        await calls.endEverything(.sleep)
        await calls.drainServerHangUps(within: 3)
    }

    /// The ring the session started is settled (see ``LiveSessionRunning/clearRing()``).
    func ringSettled() {
        session?.clearRing()
    }

    // MARK: - Reconciling

    /// Bring the running session in line with ``target``. ⛔ SERIAL: each pass waits for
    /// the one before it, so the facts are read when a pass starts, not when it was asked.
    func reconcile() {
        enqueue { [weak self] in await self?.reconcileNow() }
    }

    /// Wait for every queued pass. ⚠️ For the sign-out, the quit and the tests.
    func settled() async {
        while let current = chain {
            await current.value
            if chain == current {
                return
            }
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task {
            await previous?.value
            await work()
        }
    }

    private func reconcileNow() async {
        let want = target
        guard want != runningWorkspaceId || (want != nil && session == nil) else { return }
        retry?.cancel()
        retry = nil
        if let running = session {
            session = nil
            runningWorkspaceId = nil
            await running.stop()
        }
        guard let want else {
            releaseActivity()
            status = .off
            return
        }
        status = .connecting
        holdActivity()
        let request = LiveSessionRequest(workspaceId: want, workspaceName: workspaceName) { [weak self] next in
            self?.status = next
        }
        guard let started = await factory(request) else {
            releaseActivity()
            scheduleRetry()
            return
        }
        // ⛔ THE FACTS MAY HAVE MOVED DURING THE START (a sleep, a toggle). The session is
        // kept only if it is still the one wanted; otherwise it is stopped at once.
        guard target == want else {
            await started.stop()
            releaseActivity()
            status = .off
            reconcile()
            return
        }
        session = started
        runningWorkspaceId = want
    }

    private func scheduleRetry() {
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.retrySeconds))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    // MARK: - App Nap

    private func holdActivity() {
        guard activity == nil else { return }
        activity = beginActivity()
    }

    private func releaseActivity() {
        guard let held = activity else { return }
        activity = nil
        endActivity(held)
    }

    static func beginNoNapActivity() -> any NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Ringing this Mac for calls"
        )
    }
}

/// Where "Ring on this computer" is kept.
///
/// ⚠️ TWO CLOSURES RATHER THAN A `UserDefaults`, SO A TEST WRITES NOTHING TO DISK. The test
/// host is this app, sandboxed under this app's bundle id, so a test's defaults suite
/// would land in the container the installed app uses.
struct RingSetting {
    let load: () -> Bool?
    let save: (Bool) -> Void

    /// The app's own: the standard defaults, under ``DesktopLive/ringHereKey``.
    static var standard: RingSetting {
        RingSetting(
            load: { UserDefaults.standard.object(forKey: DesktopLive.ringHereKey) as? Bool },
            save: { UserDefaults.standard.set($0, forKey: DesktopLive.ringHereKey) }
        )
    }
}
