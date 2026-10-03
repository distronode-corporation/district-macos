import DistrictAuthCore
import Foundation
import SystemConfiguration

/// The installation id sent as `deviceId` on token exchange.
///
/// Ported from district-ios. ⛔ `UserDefaults`, NOT THE KEYCHAIN: the id must mean "this
/// installation", and it must not become a hardware fingerprint. The server treats it as
/// opaque and uses it only to scope per-device sign-out.
///
/// ⚠️ ON macOS THE SANDBOX CONTAINER (and so these defaults) SURVIVES DRAGGING THE APP
/// TO THE BIN. A reinstall therefore keeps its id and, through ``FreshInstallTokenStore``,
/// its session. That is the platform's normal behaviour for any sandboxed app and is
/// stated rather than worked around.
enum DeviceIdentity {
    static let defaultsKey = "com.distronode.district.deviceId"

    static func current(defaults: UserDefaults = .standard) -> String {
        // The route's schema is `z.string().min(8).max(200)`; a UUID string is 36.
        if let existing = defaults.string(forKey: defaultsKey), existing.count >= 8 {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}

/// The name shown for this Mac in the account's device list. Display only, never trusted.
///
/// ⚠️ `SCDynamicStoreCopyComputerName` FIRST: it is the name the user set in System
/// Settings > General > Sharing, readable inside the sandbox without any entitlement.
/// `Host.current().localizedName` is the fallback; it can resolve through the network
/// and is slower. A nil answer omits the field rather than sending an empty row.
enum MacDeviceName {
    static func current() -> String? {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, let usable = usable(name) {
            return usable
        }
        return Host.current().localizedName.flatMap(usable)
    }

    /// Trimmed, non-empty, and inside the routes' `z.string().max(120)` for `deviceName`.
    static func usable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(120))
    }
}

/// ``InstallationLedger`` over `UserDefaults`, ported from district-ios.
///
/// ⛔ "FRESH INSTALL" IS READ OFF THE DEVICE ID'S ABSENCE, SO ``begin(defaults:)`` MUST RUN
/// BEFORE ``DeviceIdentity/current(defaults:)``, which mints one.
final class UserDefaultsInstallationLedger: InstallationLedger, @unchecked Sendable {
    static let owedKey = "com.distronode.district.previousInstallWipeOwed"

    private let defaults: UserDefaults

    private init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func begin(defaults: UserDefaults = .standard) -> UserDefaultsInstallationLedger {
        if defaults.string(forKey: DeviceIdentity.defaultsKey) == nil {
            defaults.set(true, forKey: owedKey)
        }
        return UserDefaultsInstallationLedger(defaults: defaults)
    }

    var owesPreviousInstallWipe: Bool {
        defaults.bool(forKey: Self.owedKey)
    }

    func settle() {
        defaults.removeObject(forKey: Self.owedKey)
    }
}
