import Foundation

/// The conversations on screen, so the Inbox can write one's reply before it closes it.
///
/// ⛔ THE INBOX CLOSES A THREAD IT DOES NOT OWN (max review, #95). The Assigned to me filter and
/// the assign sheet empty the detail column's path, and the thread's ``ThreadModel`` lives in
/// that column's ``ThreadView``, out of the Inbox's reach. An edit inside the autosave's two
/// seconds was lost with the screen; the close now flushes it first through this.
///
/// ⚠️ WEAK REFERENCES, AND A LIST RATHER THAN ONE PER KEY: a closed screen must not be kept
/// alive by this, and two windows can hold the same conversation.
@MainActor
enum OpenThreadDrafts {
    private final class Entry {
        weak var model: ThreadModel?

        init(_ model: ThreadModel) {
            self.model = model
        }
    }

    private static var entries: [Entry] = []

    /// ``ThreadView`` appeared.
    static func opened(_ model: ThreadModel) {
        entries.removeAll { $0.model == nil || $0.model === model }
        entries.append(Entry(model))
    }

    /// ``ThreadView`` disappeared.
    static func closed(_ model: ThreadModel) {
        entries.removeAll { $0.model == nil || $0.model === model }
    }

    /// Write the composer of every open screen on this thread now (``ThreadModel/flushDraft()``).
    ///
    /// ⚠️ STARTED, NOT AWAITED: the task holds the model until the write is done, so the screen
    /// can close at once. A thread nobody typed in writes nothing.
    static func flush(workspaceId: String, threadKey: String) {
        for entry in entries {
            guard let model = entry.model, model.target.workspaceId == workspaceId,
                  model.target.threadKey == threadKey else { continue }
            Task { await model.flushDraft() }
        }
    }
}
