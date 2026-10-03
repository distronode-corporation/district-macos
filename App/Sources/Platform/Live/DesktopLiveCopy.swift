import DistrictLive
import Foundation

/// Every sentence "Ring on this computer" says, and the status it shows.
///
/// ⚠️ THE WORDS ARE district-linux's (`PresenceState` and `FailureText` in its core), the
/// one desktop client that rang before this one; the iOS app has no such setting (a phone
/// is rung by VoIP push). Where a sentence differs, the line says why.
enum DesktopLiveCopy {
    static let settingLabel = "Ring on this computer"

    /// ⚠️ ADAPTED: district-linux names its "Call handling" page; on this Mac the member's
    /// availability is the "Calls to you" card in Account.
    static let settingBody = "Calls handed to you ring here while District AI is running and you are "
        + "signed in. Your availability for calls is set under Calls to you, in Account."

    /// The line before any reason.
    static let cannotRing = "Calls cannot ring here right now."

    /// ⚠️ ADAPTED from district-linux's live-updates sentences, which promise a refresh:
    /// on this Mac the socket exists only to ring, so they say what it means for calls.
    static let forbidden = "Live updates are not available to you in this workspace."
    static let unusable = "Live updates could not be started. Updating the app may fix it."
    static let noSession = "Your session could not be checked. It is tried again in a minute."

    /// The line under the setting, or nil when there is nothing to add.
    static func message(_ status: DesktopLiveStatus) -> String? {
        guard case let .unavailable(reason) = status else { return nil }
        return reason.isEmpty ? cannotRing : "\(cannotRing) \(reason)"
    }

    /// The status, from the socket and the presence.
    ///
    /// ⛔ BOTH MUST HOLD FOR `.live`: the server rings this Mac only while its presence is
    /// fresh, and the ring arrives only over an open socket.
    ///
    /// - Parameter socketEnded: `.none` while the socket runs; `.some(reason)` once it has
    ///   ended for good, with the reason when there is one.
    static func status(socketOpen: Bool, socketEnded: String??, presence: PresenceStatus) -> DesktopLiveStatus {
        if case let .some(reason) = socketEnded {
            return .unavailable(reason ?? "")
        }
        if case let .failed(error) = presence {
            return .unavailable(FailureText.from(error).message)
        }
        guard socketOpen, presence == .registered else { return .connecting }
        return .live
    }

    /// Why the socket ended for good.
    static func reason(for error: TelemetryLiveError) -> String {
        switch error {
        case let .mint(apiError):
            FailureText.from(apiError).message
        case .forbidden:
            forbidden
        case .invalidGrant, .endpoint, .protocolMismatch:
            unusable
        }
    }
}
