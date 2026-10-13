import DistrictLive
import Foundation

/// Every sentence "Ring on this computer" says, and the status it shows.
///
/// ⚠️ THE WORDS ARE district-linux's (`PresenceState` and `FailureText` in its core), the
/// one desktop client that rang before this one; the iOS app has no such setting (a phone
/// is rung by VoIP push). Where a sentence differs, the line says why.
enum DesktopLiveCopy {
    /// The line under the setting, or nil when there is nothing to add.
    static func message(_ status: DesktopLiveStatus) -> String? {
        guard case let .unavailable(reason) = status else { return nil }
        return reason.isEmpty ? cannotRing : cannotRingBecause(reason)
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
