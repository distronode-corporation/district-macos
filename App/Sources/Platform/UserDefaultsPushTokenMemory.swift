import DistrictData
import Foundation

/// ``PushTokenMemory`` over `UserDefaults`, ported from district-ios. Everything decided
/// FROM the value lives in the core's `PushTokenRepository`.
///
/// ⚠️ The VoIP pair exists because the protocol requires it. PushKit's VoIP push is
/// unavailable on macOS, so the Mac never registers a VoIP token and those two keys stay
/// empty.
final class UserDefaultsPushTokenMemory: PushTokenMemory, @unchecked Sendable {
    static let defaultsKey = "com.distronode.district.pushToken"
    static let voipDefaultsKey = "com.distronode.district.voipPushToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastRegisteredToken() -> String? {
        defaults.string(forKey: Self.defaultsKey)
    }

    func rememberRegisteredToken(_ token: String) {
        defaults.set(token, forKey: Self.defaultsKey)
    }

    func forgetRegisteredToken() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func lastRegisteredVoipToken() -> String? {
        defaults.string(forKey: Self.voipDefaultsKey)
    }

    func rememberRegisteredVoipToken(_ token: String) {
        defaults.set(token, forKey: Self.voipDefaultsKey)
    }

    func forgetRegisteredVoipToken() {
        defaults.removeObject(forKey: Self.voipDefaultsKey)
    }
}
