import DistrictAuthCore
import DistrictLive
import DistrictModel
import DistrictNetwork
import Foundation

/// Where the ring gate's decisions go: ``IncomingCallModel`` in the app.
@MainActor
protocol DesktopRingSink: AnyObject {
    /// Start ringing for `callId`.
    func ringStarted(workspaceId: String, callId: String, workspaceName: String?)
    /// The gate ended the ring for `callId`, for `reason`.
    func ringStopped(workspaceId: String, callId: String, reason: DesktopRingEnd)
    /// The session stopped (sleep, quit, the setting off) while `callId` rang: take the
    /// ring away without a summary, because nobody declined it.
    func ringWithdrawn(callId: String)
}

/// One running live session for one workspace: the socket, the presence and the gate.
///
/// ⛔ IT DECIDES NOTHING ABOUT THE PROTOCOL. `TelemetryConnectionRunner` (the socket),
/// `PresenceController` (the presence) and `DesktopRingGate` (when to ring) are
/// district-core-swift's, tested on Linux. This object wires them together: it reads the
/// runner's updates, feeds each event to the gate, performs the gate's commands, and keeps
/// the gate's ring timeout. ``DesktopLive`` decides when one runs.
///
/// ⛔ A RING STARTS ONLY FOR THIS MEMBER: the gate is built with the user id of THIS
/// session's bearer (`AccessClaims.userId`, the token's `sub`), and a `call_ringing` event
/// names the members it rings by that id.
///
/// ⚠️ ONE WORKSPACE AT A TIME, the selected one, as on district-linux. The presence is per
/// installation, so a call to another of the member's workspaces counts this Mac as
/// ringable while its socket hears nothing; that caller waits out the server's window.
///
/// ⛔ THE LIVE TRANSCRIPT SHARES THIS SOCKET. Every update is also handed to `onTranscript`
/// (``DesktopLive`` routes it to the call screens), and a watched call is a subscription on
/// the runner, which the core sends again on every open, renewals included. The socket keeps
/// the workspace relay (no `broadcast: false`): the ring depends on it.
///
/// ⚠️ A SESSION THAT DOES NOT RING (`rings: false`, "Ring on this computer" off while a call
/// is watched) starts no presence and feeds no gate, and reports no status.
@MainActor
final class DesktopLiveSession: LiveSessionRunning {
    /// How often the presence's status is read for the line under the setting.
    static let statusPollMilliseconds: Int64 = 10000

    private let workspaceName: String?
    private let runner: TelemetryConnectionRunner
    private let presence: PresenceController
    private let clock: any LiveClock
    private weak var ring: (any DesktopRingSink)?
    private let onStatus: @MainActor (DesktopLiveStatus) -> Void
    private let rings: Bool
    private let transcriptCallIds: Set<String>
    private let onTranscript: @MainActor (TelemetryUpdate) -> Void

    private var gate: DesktopRingGate
    private var pump: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var ringTimeout: Task<Void, Never>?
    private var socket: SocketState = .connecting
    private var presenceStatus: PresenceStatus = .registering
    private var stopped = false

    private enum SocketState: Equatable {
        case connecting
        case open
        case ended(String?)
    }

    init(
        workspaceId: String,
        workspaceName: String?,
        userId: String,
        minter: any TelemetryTokenMinter,
        presenceAPI: any PresenceAPI,
        installToken: String,
        transport: any TelemetrySocketTransport = URLSessionTelemetryTransport(),
        clock: any LiveClock = SystemLiveClock(),
        ring: any DesktopRingSink,
        rings: Bool = true,
        transcriptCallIds: Set<String> = [],
        onTranscript: @escaping @MainActor (TelemetryUpdate) -> Void = { _ in },
        onStatus: @escaping @MainActor (DesktopLiveStatus) -> Void
    ) {
        self.workspaceName = workspaceName
        self.clock = clock
        self.ring = ring
        self.onStatus = onStatus
        self.rings = rings
        self.transcriptCallIds = transcriptCallIds
        self.onTranscript = onTranscript
        gate = DesktopRingGate(userId: userId)
        runner = TelemetryConnectionRunner(
            workspaceId: workspaceId,
            minter: minter,
            transport: transport,
            clock: clock,
            jitter: TelemetryConnectionRunner.randomJitter
        )
        presence = PresenceController(api: presenceAPI, clock: clock, token: installToken)
    }

    /// Start the presence and the socket, and read the socket's updates.
    func start() {
        let runner = runner
        let presence = presence
        let rings = rings
        let watched = transcriptCallIds.sorted()
        Task {
            if rings {
                await presence.start()
            }
            // ⚠️ BEFORE `start`, so the first open already carries them.
            for callId in watched {
                await runner.subscribeTranscript(callId: callId)
            }
            await runner.start()
        }
        pump = Task { [weak self] in
            for await update in runner.updates {
                guard let self else { return }
                handle(update)
            }
        }
        guard rings else { return }
        let clock = clock
        poll = Task { [weak self] in
            repeat {
                let status = await presence.status
                guard let self, !Task.isCancelled else { return }
                presenceStatus = status
                publish()
            } while await (try? clock.sleep(milliseconds: Self.statusPollMilliseconds)) != nil
        }
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        withdrawRing()
        cancelTasks()
        await runner.stop()
        await presence.stop()
    }

    func signOut() async {
        stopped = true
        withdrawRing()
        cancelTasks()
        await runner.stop()
        await presence.signOut()
    }

    func clearRing() {
        perform(gate.clear())
    }

    func subscribeTranscript(callId: String) {
        let runner = runner
        Task { await runner.subscribeTranscript(callId: callId) }
    }

    func unsubscribeTranscript(callId: String) {
        let runner = runner
        Task { await runner.unsubscribeTranscript(callId: callId) }
    }

    func resubscribeTranscript(callId: String) {
        let runner = runner
        Task { await runner.resubscribeTranscript(callId: callId) }
    }

    // MARK: - The socket's updates

    private func handle(_ update: TelemetryUpdate) {
        switch update {
        case .connected:
            socket = .open
        case let .event(envelope):
            if rings {
                perform(gate.handle(envelope, atMilliseconds: clock.nowMilliseconds()))
            }
        case .discarded:
            break
        case let .reconnecting(_, cause):
            // ⚠️ A RENEWAL IS ROUTINE (the socket is replaced on a fresh credential every
            // fifteen minutes) and is not shown.
            if cause != .renewal {
                socket = .connecting
            }
        case let .ended(error):
            socket = .ended(error.map(DesktopLiveCopy.reason(for:)))
        }
        onTranscript(update)
        publish()
    }

    private func perform(_ commands: [DesktopRingCommand]) {
        for command in commands {
            switch command {
            case let .startRinging(workspaceId, callId):
                ring?.ringStarted(workspaceId: workspaceId, callId: callId, workspaceName: workspaceName)
            case let .stopRinging(workspaceId, callId, reason):
                ringTimeout?.cancel()
                ringTimeout = nil
                ring?.ringStopped(workspaceId: workspaceId, callId: callId, reason: reason)
            case let .scheduleTimeout(milliseconds):
                let clock = clock
                ringTimeout?.cancel()
                ringTimeout = Task { [weak self] in
                    guard await (try? clock.sleep(milliseconds: milliseconds)) != nil, let self else { return }
                    perform(gate.expire(atMilliseconds: clock.nowMilliseconds()))
                }
            }
        }
    }

    /// ⚠️ THE GATE IS CLEARED WITHOUT TELLING THE SINK THE ORDINARY WAY: a cleared ring is
    /// echoed as `.cleared`, which the model rightly ignores, so it is told to withdraw.
    private func withdrawRing() {
        guard let callId = gate.ring?.callId else { return }
        _ = gate.clear()
        ringTimeout?.cancel()
        ringTimeout = nil
        ring?.ringWithdrawn(callId: callId)
    }

    private func cancelTasks() {
        pump?.cancel()
        pump = nil
        poll?.cancel()
        poll = nil
        ringTimeout?.cancel()
        ringTimeout = nil
    }

    private func publish() {
        guard !stopped, rings else { return }
        onStatus(DesktopLiveCopy.status(
            socketOpen: socket == .open,
            socketEnded: endedReason,
            presence: presenceStatus
        ))
    }

    private var endedReason: String?? {
        if case let .ended(reason) = socket {
            return .some(reason)
        }
        return .none
    }
}

extension DesktopLiveSession {
    /// The factory ``DesktopLive`` runs in the app.
    ///
    /// ⛔ THE USER ID IS READ FROM THE BEARER AT START, not stored at sign-in: a session
    /// started after a refresh reads the same `sub` from the new token, and a session that
    /// cannot read one does not start (and is retried) rather than ringing for nobody.
    static func factory(
        container: AppContainer,
        ring: any DesktopRingSink,
        installToken: String = UUID().uuidString
    ) -> DesktopLive.Factory {
        { request in
            let coordinator = container.coordinator
            guard case let .available(token) = await coordinator.accessToken(),
                  let claims = AccessClaims(jwt: token)
            else {
                // ⚠️ A session that would not ring reports nothing: the line under the setting
                // is about ringing.
                if request.rings {
                    request.onStatus(.unavailable(DesktopLiveCopy.noSession))
                }
                return nil
            }
            let session = DesktopLiveSession(
                workspaceId: request.workspaceId,
                workspaceName: request.workspaceName,
                userId: claims.userId,
                minter: container.api,
                presenceAPI: container.api,
                installToken: installToken,
                ring: ring,
                rings: request.rings,
                transcriptCallIds: request.transcriptCallIds,
                onTranscript: request.onTranscript,
                onStatus: request.onStatus
            )
            session.start()
            return session
        }
    }
}
