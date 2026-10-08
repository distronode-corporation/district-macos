import AppKit
import DistrictLive
import DistrictModel
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
    /// Receive `callId`'s live transcript on this session's socket, now and after every
    /// reconnect. ⚠️ Idempotent.
    func subscribeTranscript(callId: String)
    /// Stop receiving `callId`'s live transcript.
    func unsubscribeTranscript(callId: String)
    /// Ask again for `callId`'s transcript, for a fresh snapshot (a gap's heal).
    func resubscribeTranscript(callId: String)
}

/// What starting a session needs.
struct LiveSessionRequest {
    let workspaceId: String
    let workspaceName: String?
    /// Whether this session rings (the presence and the gate). ⚠️ False when it runs only
    /// because a call's live transcript is being watched with "Ring on this computer" off.
    let rings: Bool
    /// The calls whose live transcript is watched when the session starts.
    let transcriptCallIds: Set<String>
    /// Where the session reports its status.
    let onStatus: @MainActor (DesktopLiveStatus) -> Void
    /// Where the session hands every socket update, for the live transcripts.
    let onTranscript: @MainActor (TelemetryUpdate) -> Void
}

/// What a watched call's live transcript hears from the socket.
enum TranscriptFeed: Equatable, Sendable {
    /// The socket opened, and the subscription was sent on it: a snapshot is coming.
    case connected
    /// A `transcript_*` event about the call.
    case event(TranscriptEvent)
    /// `call_ended` for the call (this socket takes the workspace's events).
    case callEnded
    /// `call_started` or `call_updated` for the call, with the status its row now has: the
    /// call-status signal that may subscribe again after `not_live`.
    case callStatus(String)
    /// The socket closed and will reopen (or the session stopped, for sleep or quit).
    case disconnected
    /// The socket ended for good: the member may not stream the workspace.
    case failed
}

/// Where the call screen's live transcript gets its frames: ``DesktopLive`` in the app.
@MainActor
protocol TranscriptChannel: AnyObject {
    /// Hear about `callId` until ``stopWatchingTranscript(_:)``; unsubscribed (after
    /// `not_live`), only its status and end, with no subscription on the socket.
    func watchTranscript(
        callId: String,
        subscribed: Bool,
        onUpdate: @escaping @MainActor (TranscriptFeed) -> Void
    ) -> UUID
    func stopWatchingTranscript(_ id: UUID)
    /// Subscribe a watch, or drop its subscription and still hear the call's status: the
    /// call-status signal is what subscribes again after `not_live`.
    func setTranscriptSubscribed(_ id: UUID, _ subscribed: Bool)
    func resubscribeTranscript(callId: String)
}

/// Ringing on this Mac: the telemetry socket, the presence that makes the server ring it,
/// and the ring gate, kept running exactly while they should be.
///
/// ⛔ RUNNING IS A PURE FUNCTION OF FIVE FACTS, AND EVERY ENTRY POINT ONLY CHANGES A FACT.
/// A session runs while someone is signed in, a workspace is selected, the Mac is awake,
/// and either "Ring on this computer" is on or a call's live transcript is being watched
/// (``target``); it rings only when the setting is on (``wantsRinging``). ``reconcile()``
/// is the one place that starts or stops one, and it runs serially, so a sleep arriving
/// during a start cannot leave two sockets open or one that nothing will stop.
///
/// ⛔ THE LIVE TRANSCRIPT RIDES THE SAME SOCKET, NEVER A SECOND ONE. The ring needs the
/// workspace's events, so this socket never says `broadcast: false`; a watched call is
/// one `transcript.subscribe` on it, sent again on every open by the core. With the
/// setting off, watching a call starts a session that does not ring (no presence, no
/// gate) and stops it when the last call is no longer watched.
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
final class DesktopLive: TranscriptChannel {
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

    /// Whether the running session rings.
    private(set) var runningRings = false

    /// The call screens watching a live transcript, by the id
    /// ``watchTranscript(callId:subscribed:onUpdate:)`` returned.
    private var transcriptWatchers: [UUID: TranscriptWatcher] = [:]

    private struct TranscriptWatcher {
        let callId: String
        var subscribed: Bool
        let onUpdate: @MainActor (TranscriptFeed) -> Void
    }

    /// The calls whose live transcript is subscribed on the socket. ⚠️ A watch that is not
    /// subscribed (after `not_live`) still keeps the socket running: it is how the screen
    /// hears the call-status signal that may subscribe again.
    var watchedCallIds: Set<String> {
        Set(transcriptWatchers.values.filter(\.subscribed).map(\.callId))
    }

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

    /// The session that should run, if any: the workspace to ring for or to watch.
    var target: String? {
        guard signedIn, ringHere || !transcriptWatchers.isEmpty, awake, let workspaceId else { return nil }
        return workspaceId
    }

    /// Whether the session that should run rings.
    var wantsRinging: Bool {
        ringHere
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
        let rings = wantsRinging
        let changed = want != runningWorkspaceId || (want != nil && (session == nil || rings != runningRings))
        guard changed else { return }
        retry?.cancel()
        retry = nil
        if let running = session {
            session = nil
            runningWorkspaceId = nil
            await running.stop()
            deliver(.disconnected)
        }
        guard let want else {
            releaseActivity()
            status = .off
            return
        }
        // ⚠️ A SESSION THAT ONLY CARRIES TRANSCRIPTS IS NOT RINGING, so the line under the
        // setting says off.
        status = rings ? .connecting : .off
        holdActivity()
        let request = LiveSessionRequest(
            workspaceId: want,
            workspaceName: workspaceName,
            rings: rings,
            transcriptCallIds: watchedCallIds,
            onStatus: { [weak self] next in self?.status = next },
            onTranscript: { [weak self] update in self?.transcriptUpdate(update) }
        )
        guard let started = await factory(request) else {
            releaseActivity()
            scheduleRetry()
            return
        }
        // ⛔ THE FACTS MAY HAVE MOVED DURING THE START (a sleep, a toggle). The session is
        // kept only if it is still the one wanted; otherwise it is stopped at once.
        guard target == want, wantsRinging == rings else {
            await started.stop()
            releaseActivity()
            status = .off
            reconcile()
            return
        }
        session = started
        runningWorkspaceId = want
        runningRings = rings
        // ⚠️ A CALL WATCHED WHILE THE SESSION WAS STARTING was not in the request; the
        // subscribe is idempotent, so every watched call is subscribed again here.
        for callId in watchedCallIds.sorted() {
            started.subscribeTranscript(callId: callId)
        }
    }

    private func scheduleRetry() {
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.retrySeconds))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    // MARK: - Live transcripts

    func watchTranscript(
        callId: String,
        subscribed: Bool,
        onUpdate: @escaping @MainActor (TranscriptFeed) -> Void
    ) -> UUID {
        let id = UUID()
        transcriptWatchers[id] = TranscriptWatcher(callId: callId, subscribed: false, onUpdate: onUpdate)
        setTranscriptSubscribed(id, subscribed)
        reconcile()
        return id
    }

    func stopWatchingTranscript(_ id: UUID) {
        guard transcriptWatchers[id] != nil else { return }
        setTranscriptSubscribed(id, false)
        transcriptWatchers[id] = nil
        reconcile()
    }

    /// ⚠️ A SECOND SCREEN ON A CALL ALREADY SUBSCRIBED SENDS THE SUBSCRIBE AGAIN: the server
    /// answers a duplicate with a fresh snapshot (contract §4.12 Q5), which that screen needs
    /// and the first applies as a heal. The last subscribed screen to leave unsubscribes.
    func setTranscriptSubscribed(_ id: UUID, _ subscribed: Bool) {
        guard let watcher = transcriptWatchers[id], watcher.subscribed != subscribed else { return }
        let others = transcriptWatchers
            .contains { $0.key != id && $0.value.subscribed && $0.value.callId == watcher.callId }
        transcriptWatchers[id]?.subscribed = subscribed
        switch (subscribed, others) {
        case (true, false): session?.subscribeTranscript(callId: watcher.callId)
        case (true, true): session?.resubscribeTranscript(callId: watcher.callId)
        case (false, false): session?.unsubscribeTranscript(callId: watcher.callId)
        case (false, true): break
        }
    }

    func resubscribeTranscript(callId: String) {
        session?.resubscribeTranscript(callId: callId)
    }

    /// Route one socket update to the screens it concerns. ⚠️ The open and the
    /// `transcript_*` frames reach subscribed screens only; the rest reach every one.
    func transcriptUpdate(_ update: TelemetryUpdate) {
        switch update {
        case .connected:
            deliver(.connected, subscribedOnly: true)
        case let .event(envelope):
            if let event = envelope.transcriptEvent {
                // ⚠️ AN ERROR THAT NAMES NO CALL CONCERNS NO SCREEN (its envelope `callId` is
                // "", which names none).
                guard let callId = event.callId else { return }
                deliver(.event(event), to: callId, subscribedOnly: true)
            } else if envelope.eventType == .callEnded {
                deliver(.callEnded, to: envelope.callId)
            } else if let status = Self.statusSignal(envelope) {
                deliver(.callStatus(status), to: envelope.callId)
            }
        case .discarded:
            break
        case .reconnecting:
            deliver(.disconnected)
        case let .ended(error):
            deliver(error == nil ? .disconnected : .failed)
        }
    }

    /// The status a `call_started` or `call_updated` carries: the call-status signal.
    private static func statusSignal(_ envelope: TelemetryEnvelope) -> String? {
        guard envelope.eventType == .callUpdated || envelope.eventType == .callStarted else { return nil }
        return envelope.callStatus
    }

    private func deliver(_ feed: TranscriptFeed, to callId: String? = nil, subscribedOnly: Bool = false) {
        let reached = transcriptWatchers.values.filter { watcher in
            (callId == nil || watcher.callId == callId) && (watcher.subscribed || !subscribedOnly)
        }
        for watcher in reached {
            watcher.onUpdate(feed)
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
