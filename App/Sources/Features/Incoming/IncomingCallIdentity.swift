import DistrictCall
import DistrictData
import DistrictModel
import Foundation

// The impure half of ``IncomingCallIdentity``: the one round trip that turns a
// ring's two identifiers into a caller.
//
// ⛔ THE TYPE ITSELF AND EVERY RULE IT APPLIES LIVE IN `DistrictCall`, AND THE
// SPLIT IS THE POINT. `resolve(from:)` is a pure function of a ``CallSummary``: no
// UIKit, no CallKit, no SwiftUI, so it belongs on the tier `swift test` can reach
// on Linux, which is where the two sentinel rules that decide what this client
// hands the operating system as a phone number are pinned by tests. What is
// here is the part that genuinely cannot move: it needs a repository, a
// bearer, and the App's own notion of when a ring is still worth updating.

extension IncomingCallIdentity {
    /// Ask the workspace who is calling. nil for every unusable answer.
    ///
    /// ⛔ THE FETCH IS SECOND AND IT MAY NEVER BECOME FIRST. The ring is shown the
    /// moment the gate says so; this is a round trip that may take a second, may
    /// fail, and may never answer at all, and a ring that waited on it would spend
    /// the caller's thirty seconds on a name.
    ///
    /// ⛔ ONE REQUEST, NEVER RETRIED. A ring is bounded at thirty seconds and the
    /// server's rendezvous at about twenty-five, so a second attempt would be
    /// spending a caller's remaining silence on a cosmetic field. Every failure
    /// collapses to nil: a 404, a 401, an offline network and a malformed body are
    /// all the same thing here, which is "no name to show".
    ///
    /// ⚠️ nil ALSO FOR A SUCCESSFUL READ THAT RESOLVED NOTHING, so a caller with
    /// no number and no contact leaves the ring exactly as it was rather than
    /// reporting an update that says nothing. See ``IncomingCallIdentity/isKnown``.
    ///
    /// ⛔ NOTHING HERE IS LOGGED. A caller's number is the most sensitive thing this
    /// screen will ever hold, and a log line outlives the call.
    static func lookUp(
        _ calls: CallsRepository,
        workspace: WorkspaceID,
        call: CallID
    ) async -> IncomingCallIdentity? {
        let outcome = await calls.detail(workspaceId: workspace.rawValue, callId: call.rawValue)
        guard case let .success(summary) = outcome else { return nil }
        let identity = resolve(from: summary)
        return identity.isKnown ? identity : nil
    }
}
