import DistrictL10n
import DistrictModel
import Foundation

/// One API instant, as a person reads it: `Sep 12, 2026 at 2:30 PM`.
///
/// ⚠️ THE STYLE IS A `static let`, NOT BUILT PER ROW. `Date.FormatStyle` is a `Sendable`
/// value, and its default locale, calendar and zone are the AUTOUPDATING ones, so a
/// shared instance still follows a device that changes zone or language mid-session.
///
/// ⚠️ FALLS BACK TO THE RAW STRING. An unparseable instant is still true, and a blank
/// line where a date should be reads as missing data.
enum WireDate {
    private static let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    private static let dayStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

    /// - Parameter zone: the zone to read the instant in. nil is the device's; a
    ///   scheduling surface passes the operator's profile zone instead.
    static func display(_ raw: String, in zone: TimeZone? = nil) -> String {
        guard let date = WireInstant.parse(raw) else { return raw }
        // ⛔ FRENCH IS THE CORE'S, NOT THE DEVICE'S: « 12 sept. 2026, 15 h 04 », as the
        // website writes it, on an fr-FR or fr-BE device too, which the system's own
        // French would write differently. English keeps the system style below.
        if AppL10n.copyLocale == .frCA {
            return L10nFormat.dateTime(date, timezone: (zone ?? .current).identifier)
        }
        guard let zone else { return date.formatted(style) }
        var zoned = style
        zoned.timeZone = zone
        return date.formatted(zoned)
    }

    /// The day alone (`Sep 12, 2026`), in the device's zone, for a column too narrow for the
    /// minute. ⚠️ Falls back to the raw string, as ``display(_:in:)`` does.
    static func displayDay(_ raw: String) -> String {
        guard let date = WireInstant.parse(raw) else { return raw }
        // ⚠️ French through the core (« 15 août 2026 », « 1er août 2026 »), as ``display(_:in:)``.
        if AppL10n.copyLocale == .frCA {
            return L10nFormat.date(date, timezone: TimeZone.current.identifier)
        }
        return date.formatted(dayStyle)
    }
}
