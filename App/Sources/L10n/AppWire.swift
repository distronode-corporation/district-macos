import DistrictL10n
import Foundation

/// The words a screen shows for what the API sends as data: an enumerated value (a call's
/// status, a carrier, a role), a call length the server wrote, a count.
///
/// ⛔ BOTH LANGUAGES READ THE VOCABULARY (`contracts/i18n/wire-vocabulary.json`), WHICH HOLDS
/// THE PORTAL'S OWN WORDS. Until 3.0.1 English drew the value as sent, so the Overview showed
/// `completed` beside "Transferred" where the portal says "Completed". English now shows the
/// vocabulary's label and keeps a value the vocabulary does not list as sent
/// (``WireLabel/knownLabel(_:_:)``); a French screen must never show an English wire word, so
/// it takes ``WireLabel/label(_:_:)``, where an unlisted value reads as the category's
/// fallback or « Autre ».
///
/// ⚠️ WIRE VALUES NEVER LOCALIZE: a screen keeps branching on the raw value and only shows
/// this beside it.
enum AppWire {
    /// The label of `value` in `category`: the vocabulary's, in either language. ⚠️ English
    /// keeps a value the vocabulary does not list as sent; French reads it as the fallback.
    static func label(_ category: WireCategory, _ value: String) -> String {
        AppL10n.copyLocale == .frCA ? WireLabel.label(category, value) : WireLabel.knownLabel(category, value) ?? value
    }

    /// ``label(_:_:)`` of a value that may be absent: nil when there is no value or only
    /// blanks, so a screen's own blank guard still hides the field instead of showing
    /// « Autre » for nothing.
    static func label(_ category: WireCategory, ifAny value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return label(category, value)
    }

    /// Text the service writes in English in place of a value (`You`, `Distronode Support`):
    /// as sent in English, the vocabulary's label in French; any other text is data and is
    /// shown as it is.
    static func placeholder(_ text: String) -> String {
        guard AppL10n.copyLocale == .frCA else { return text }
        return WireLabel.placeholder(text) ?? text
    }

    /// A call's length: the server's own `duration` text in English (`1m 5s`), and in French
    /// written from the seconds (« 1 min 5 s »), since the server writes English only.
    static func duration(sent: String, seconds: Int?) -> String {
        AppL10n.copyLocale == .frCA ? minutesSeconds(seconds) : sent
    }

    /// The core's French call length (« 3 min 4 s ») held on one line.
    ///
    /// ⚠️ EVERY SPACE A NO-BREAK ONE (3.0.2). The core puts a no-break space between each
    /// number and its unit but a plain one between the minutes and the seconds, so a narrow
    /// cell broke « 3 min » from « 4 s ». A length is one value and never wraps.
    static func minutesSeconds(_ seconds: Int?) -> String {
        L10nFormat.minutesSeconds(seconds).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// A whole number shown on its own: plain digits in English, as every count has always
    /// been printed, and grouped in French (« 1 204 »).
    static func count(_ value: Int) -> String {
        L10nFormat.count(value)
    }
}
