import DistrictCall
import DistrictModel
import DistrictNetwork
import Foundation

/// How ``SuperviseModel`` performs the reducer's commands.
///
/// ⚠️ SPLIT OUT OF `SuperviseModel.swift` FOR `type_body_length`, AND THAT IS THE WHOLE REASON.
/// ⛔ IT WRITES NO `private(set)` STATE: the session is written in the model's own file
/// (``apply(_:)``, ``release()``), and the members this file writes are the module-visible ones
/// the model lists.
extension SuperviseModel {
    /// The platform the listen seat is asked for. ⛔ `.macos`, NEVER THE CORE'S `.ios` DEFAULT
    /// (CONTRIBUTING.md): `MacClientPlatformTests` pins the monitor request's bytes.
    static let platform: ClientPlatform = .macos

    private func isCurrent(_ leg: SuperviseLeg, _ generation: Int) -> Bool {
        claimed && state.leg == leg && state.generation == generation
    }

    func perform(_ command: SuperviseCommand) async {
        switch command {
        case .requestListen:
            await requestListen()
        case .requestTakeover:
            await requestTakeover()
        case let .join(leg, generation, url, token):
            await join(leg, generation: generation, url: url, token: token)
        case let .engine(leg, engineCommand):
            // ⛔ A COMMAND FOR A LEG WHOSE ENGINE IS GONE IS DROPPED: there is one slot, and it
            // may already hold the other leg's engine.
            guard leg == engineLeg else { return }
            await media.perform(engineCommand)
        case .reportCallEnded:
            // ⚠️ NOTHING TO TELL: a Mac has no system call. ``settle()`` releases the claim.
            break
        }
    }

    /// ⛔ ONCE PER PRESS, NEVER RETRIED: a seat that arrives after the person gave up would join
    /// them to a customer's call they had walked away from. The reducer absorbs a late answer.
    private func requestListen() async {
        guard let id = SupervisedCallID(callId) else {
            // ⚠️ UNREACHABLE FOR A CALL-LOG ROW (a `Call.id` carries no `_`); refused all the
            // same, as `calls/token` would read such a value as a room.
            await apply(.listenRefused(.decoding("call id is not a call")))
            return
        }
        // ⛔ AN ANSWER FOR AN ATTEMPT THE PERSON ABANDONED IS DROPPED (district-ios #101, max review
        // item 7): after Stop and Listen again, the first attempt's refusal is not the second one's.
        let pressed = attempt
        let answer = await server.monitor(callId: id, platform: Self.platform)
        guard attempt == pressed, claimed else { return }
        switch answer {
        case let .success(seat):
            await apply(.listenGranted(seat))
        case let .failure(error):
            await apply(.listenRefused(error))
        }
    }

    private func requestTakeover() async {
        let pressed = attempt
        let answer = await server.takeOver(workspaceId: workspaceId, callId: callId)
        guard attempt == pressed, claimed else { return }
        switch answer {
        case let .success(seat):
            await apply(.takeoverGranted(seat))
        case let .failure(error):
            await apply(.takeoverRefused(error))
        }
    }

    /// Build the leg's engine, read its events, then connect it.
    ///
    /// ⛔ THE ENGINE EXISTS BEFORE THE CONNECT, because ``SuperviseMedia/perform(_:)`` drops a
    /// command that arrives with none. ⛔ EACH ENGINE'S STREAM IS READ ONCE, AND EVERY EVENT
    /// CARRIES THE LEG AND THE GENERATION ITS JOIN WAS GIVEN, so the session drops what a left
    /// engine says late: the listen engine's `disconnected` after a takeover, or a stopped
    /// listen's after Listen was pressed again.
    private func join(_ leg: SuperviseLeg, generation: Int, url: String, token: String) async {
        // ⛔ ONLY FOR THE JOIN THE SESSION STILL WANTS (district-ios #101, max review item 2): an
        // end during the takeover's room swap (Stop, the call ending, sleep) must not build a
        // coach engine with a published microphone that nothing will ever end.
        guard isCurrent(leg, generation) else { return }
        legTask?.cancel()
        let events = await media.beginLeg(leg)
        guard isCurrent(leg, generation) else {
            // ⚠️ THE ENGINE ALREADY EXISTS: end it, connected to nothing.
            media.endLeg()
            return
        }
        engineLeg = leg
        legTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                await apply(.engine(leg, generation: generation, event))
            }
        }
        await media.perform(.connect(url: url, token: token))
    }

    /// React to the phase the reducer has just reached.
    func settle() async {
        switch state.phase {
        case .idle, .over:
            await release()
        case .requestingListen, .joiningListen, .listening, .requestingTakeover, .joiningTakeover, .takenOver:
            break
        }
    }
}
