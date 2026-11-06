#if DEBUG

    import DistrictCall
    import Foundation

    /// A Mac that joins every room at once, for screenshots of a supervision against a local
    /// fixture server.
    ///
    /// ⛔ THE WHOLE FILE IS INSIDE `#if DEBUG`, FOR ``UITestSession``'S REASON: every archive is a
    /// Release build, so neither the type nor the variable that arms it exists in a shipped
    /// binary (`scripts/archive.sh` refuses a binary whose strings contain `DISTRICT_UITEST`).
    ///
    /// ⛔ ARMED ONLY BY BOTH HALVES: the `-UITestSession` launch argument AND
    /// `DISTRICT_UITEST_STAGED_MEDIA=1`. What it stands in for is only the LiveKit room; the
    /// reducer, the three routes, the telemetry socket and the screens are the real ones,
    /// against whatever server the session names.
    @MainActor
    final class StagedSuperviseMedia: SuperviseMedia {
        static let variable = "DISTRICT_UITEST_STAGED_MEDIA"

        static func isArmed(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
            UITestSession.isArmed() && environment[variable] == "1"
        }

        let hasLiveCall = false
        let hasLiveRoom = false
        let microphone: any MicrophoneAccess = GrantedMicrophone()

        private var events: AsyncStream<CallEngineEvent>.Continuation?
        private var leg: SuperviseLeg?

        func claim(_: SuperviseModel) -> Bool {
            true
        }

        func release(_: SuperviseModel) {}

        func beginLeg(_ leg: SuperviseLeg) async -> AsyncStream<CallEngineEvent> {
            self.leg = leg
            events?.finish()
            let (stream, continuation) = AsyncStream<CallEngineEvent>.makeStream()
            events = continuation
            return stream
        }

        func perform(_ command: CallCommand) async {
            switch command {
            case .connect:
                // ⚠️ THE CALLER AND THE RECEPTIONIST ARE IN THE ROOM, ANNOUNCED AS JOINS: that is
                // what a supervise leg's engine does for the people present at the join.
                let events = events
                let publishes = leg == .takeover
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1500))
                    events?.yield(.participantJoined(CallParticipant(identity: "caller", name: nil, isAgent: false)))
                    events?.yield(.participantJoined(CallParticipant(identity: "agent", name: "Ava", isAgent: true)))
                    events?.yield(.connected)
                    // ⚠️ THE COACH LEG'S MICROPHONE STARTED, as the engine reports it.
                    if publishes {
                        events?.yield(.microphoneChanged(enabled: true))
                    }
                }
            case let .setMuted(muted):
                events?.yield(.microphoneChanged(enabled: !muted))
            case .disconnect, .setSpeakerphone:
                break
            }
        }

        func endLeg() {
            events?.finish()
            events = nil
        }
    }

    /// A microphone the staged Mac may always use: no system alert over a screenshot run.
    private struct GrantedMicrophone: MicrophoneAccess {
        var status: MicrophoneStatus {
            .granted
        }

        func request() async -> Bool {
            true
        }
    }

#endif
