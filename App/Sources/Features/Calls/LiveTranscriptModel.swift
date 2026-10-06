import DistrictLive
import DistrictModel
import Foundation
import Observation

/// The live transcript of one call in progress, for the call's screen.
///
/// Ported from district-ios `Features/Calls/LiveTranscriptModel.swift` (see PORTING.md), with
/// one difference that matters: ⛔ NO SOCKET OF ITS OWN. The phone opens a socket per screen;
/// the Mac already holds one for ringing (``DesktopLive``), so a watched call is a
/// subscription on that socket, through ``TranscriptChannel``. The rules are still the
/// core's: `TranscriptReducer` for what the frames mean, `TelemetryConnection` for sending
/// the subscribe again after every reconnect and renewal.
///
/// ⚠️ WATCHED WHILE THE SCREEN IS SHOWN: ``activate()`` when it appears, ``deactivate()`` when
/// it goes. A Mac's sleep stops the shared socket; on wake it reopens with the subscription
/// and the snapshot replaces what is on screen.
@MainActor
@Observable
final class LiveTranscriptModel {
    /// Where the socket stands, for the line under the heading.
    enum Connection: Equatable {
        case idle
        case connecting
        case open
        /// The socket ended for good. The screen falls back to the transcript after the call.
        case failed
    }

    let callId: String

    private(set) var lines: [TranscriptSegment] = []
    private(set) var phase: LiveTranscriptPhase = .subscribing
    private(set) var complete = true
    private(set) var finalTranscript: FinalTranscriptState = .notRequested
    private(set) var connection: Connection = .idle

    /// Whether the screen should show the transcript after the call instead.
    var fallsBack: Bool {
        if case .unavailable = phase {
            return true
        }
        return connection == .failed
    }

    private weak var channel: (any TranscriptChannel)?
    private let clock: any LiveClock
    private let fetchTranscript: @Sendable () async -> Result<String, ApiError>
    private var reducer: TranscriptReducer
    private var watch: UUID?
    private var timers: [Timer: Task<Void, Never>] = [:]
    /// Set once the call no longer needs the socket (the full transcript is in, or the live
    /// one is unavailable), so a later activation watches nothing.
    private var finished = false

    private enum Timer: Hashable {
        case resubscribe
        case gap
        case fetch
    }

    init(
        callId: String,
        channel: any TranscriptChannel,
        clock: any LiveClock = SystemLiveClock(),
        fetchTranscript: @escaping @Sendable () async -> Result<String, ApiError>
    ) {
        self.callId = callId
        self.channel = channel
        self.clock = clock
        self.fetchTranscript = fetchTranscript
        reducer = TranscriptReducer(callId: callId)
    }

    // MARK: - The screen's lifecycle

    func activate() {
        if case .fetching = finalTranscript {
            schedule(.fetch, after: 0) { [weak self] in await self?.fetchFinal() }
            return
        }
        guard !finished, watch == nil, let channel else { return }
        connection = .connecting
        watch = channel.watchTranscript(callId: callId) { [weak self] feed in self?.handle(feed) }
    }

    func deactivate() {
        stopWatching()
        cancelTimers()
        if connection != .failed {
            connection = .idle
        }
    }

    // MARK: - The socket

    func handle(_ feed: TranscriptFeed) {
        switch feed {
        case .connected:
            connection = .open
            reducer.reconnected()
            cancel(.gap)
        case let .event(event):
            perform(reducer.apply(event, atMilliseconds: clock.nowMilliseconds()))
        case .callEnded:
            perform(reducer.callEnded())
        case .disconnected:
            connection = .connecting
        case .failed:
            connection = .failed
        }
        publish()
    }

    private func perform(_ commands: [TranscriptCommand]) {
        for command in commands {
            switch command {
            case let .resubscribe(delay):
                schedule(.resubscribe, after: delay) { [weak self] in
                    guard let self else { return }
                    channel?.resubscribeTranscript(callId: callId)
                }
            case let .checkGap(delay):
                schedule(.gap, after: delay) { [weak self] in
                    guard let self else { return }
                    perform(reducer.gapCheck(atMilliseconds: clock.nowMilliseconds()))
                    publish()
                }
            case let .fetchFinal(delay):
                schedule(.fetch, after: delay) { [weak self] in await self?.fetchFinal() }
            case .unsubscribe:
                finished = true
                stopWatching()
            }
        }
    }

    private func fetchFinal() async {
        let result = await fetchTranscript()
        perform(reducer.finalFetched(result))
        publish()
    }

    private func stopWatching() {
        guard let watch else { return }
        self.watch = nil
        channel?.stopWatchingTranscript(watch)
    }

    private func publish() {
        lines = reducer.lines
        phase = reducer.phase
        complete = reducer.complete
        finalTranscript = reducer.finalTranscript
    }

    // MARK: - Waits

    private func schedule(_ timer: Timer, after milliseconds: Int64, _ work: @escaping @MainActor () async -> Void) {
        timers[timer]?.cancel()
        let clock = clock
        timers[timer] = Task {
            guard await (try? clock.sleep(milliseconds: milliseconds)) != nil, !Task.isCancelled else { return }
            await work()
        }
    }

    private func cancel(_ timer: Timer) {
        timers.removeValue(forKey: timer)?.cancel()
    }

    private func cancelTimers() {
        timers.values.forEach { $0.cancel() }
        timers = [:]
    }
}
