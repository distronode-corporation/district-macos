import Foundation

/// The microphone question an inbound call asks at Answer.
///
/// ⛔ ITS OWN FILE FOR THE REASON `IncomingCallTasks.swift` IS ONE, the 500-line `file_length`
/// ceiling. It widens nothing: ``calls`` was already module-visible.
extension IncomingCallModel {
    /// Ask before the answer round trip, when nobody has asked yet.
    ///
    /// ⛔ A REFUSAL STILL ANSWERS. The person pressed Answer, the agent's transfer is blocked on the
    /// rendezvous that round trip writes, and dropping a caller the platform has already put through
    /// is the worse outcome. ⚠️ Whether the join then succeeds is the engine's decision, not this
    /// one's: with no grant it refuses to record and the call ends as failed.
    func prepareMicrophoneForAnswer() async {
        _ = await Self.askAtAnswer(calls.microphone)
    }

    /// Whether to ask, and the asking. ⚠️ Static so it is testable without a ring.
    ///
    /// ⚠️ NO "ONLY IN THE FOREGROUND" CONDITION, UNLIKE iOS. Every Mac answer is a press with the
    /// app running (the ring panel, or the notification's Answer, which brings the app forward), and
    /// macOS shows the permission alert either way. An answered question needs no trip to the OS.
    ///
    /// - Returns: whether the question was put to the OS.
    static func askAtAnswer(_ microphone: any MicrophoneAccess) async -> Bool {
        guard microphone.status == .notDetermined else { return false }
        _ = await microphone.request()
        return true
    }
}
