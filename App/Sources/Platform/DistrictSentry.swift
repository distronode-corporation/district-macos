import Foundation
import Sentry

/// Crash reporting, started only when a build carries a DSN. Ported from district-ios.
///
/// ⛔ THE DSN COMES FROM `Info.plist` (`DistrictSentryDSN`, expanded from the
/// `SENTRY_DSN` build setting), WHICH project.yml SHIPS BLANK. Every CI, local and fork
/// build therefore runs with the SDK inert; only the release lane supplies a value.
///
/// ⛔ PRIVACY BY CONFIGURATION: no user, no request, no screenshots, no breadcrumbs, no
/// network tracking and no performance traces. What is sent is a crash and its stack.
enum DistrictSentry {
    static let dsnInfoKey = "DistrictSentryDSN"
    static let environmentInfoKey = "DistrictSentryEnvironment"

    static func startIfConfigured(bundle: Bundle = .main) {
        guard let dsn = configuredValue(bundle, forKey: dsnInfoKey) else { return }
        let environment = configuredValue(bundle, forKey: environmentInfoKey)?.lowercased()
        let release = releaseName(bundle)

        SentrySDK.start { options in
            options.dsn = dsn
            if let environment {
                options.environment = environment
            }
            if let release {
                options.releaseName = release
            }

            options.enableCrashHandler = true
            options.enableAppHangTracking = true

            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0
            options.enableAutoBreadcrumbTracking = false
            options.sendDefaultPii = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false

            options.beforeSend = { event in
                event.user = nil
                event.request = nil
                return event
            }
        }
    }

    /// ⚠️ A value still containing `$(` is an UNSUBSTITUTED build-setting reference, which
    /// is treated as absent rather than sent as a DSN.
    static func configuredValue(_ bundle: Bundle, forKey key: String) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        return usable(raw)
    }

    static func usable(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    /// `com.distronode.district@<version>+<build>`, the iOS app's scheme, so a Mac crash
    /// maps to a commit the same way.
    private static func releaseName(_ bundle: Bundle) -> String? {
        guard let identifier = bundle.bundleIdentifier,
              let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { return nil }
        return "\(identifier)@\(short)+\(build)"
    }
}
