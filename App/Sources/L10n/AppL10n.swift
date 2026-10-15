import DistrictL10n
import Foundation

/// The language the app writes in: its own screens (the `*Copy` enums, generated from
/// `l10n/macos.toml` into `Generated/Copy.swift`) and the core's sentences and formats.
///
/// ⛔ ONE VALUE FOR BOTH, AND IT IS THE CORE'S. ``L10nRuntime/locale`` is what
/// district-core-swift writes in, and the generated accessors read the same value
/// through ``copyLocale``, so a screen's own words and the core's error sentence or
/// date under them can never disagree about the language.
///
/// ⛔ FRENCH ONLY WHEN THIS BUILD SHIPS IT. Every build since 3.0 holds fr-CA.lproj
/// (project.yml), so a Mac whose languages put any French first reads Canadian French; a
/// bundle with no French localization (2.x, a test host built without it) answers
/// English whatever the device is set to, because the core's formatters would otherwise
/// turn French (« 249,00 $ ») under English screens.
///
/// ⚠️ WHAT THIS DECIDES IS ALSO WHAT THE SERVER IS TOLD: the core sends it as
/// `Accept-Language` on every request, and ``AccountLanguageSync`` stores it as the
/// account's language, so email and the server's own text match the app.
enum AppL10n {
    /// The two languages the generated accessors know.
    ///
    /// ⚠️ THE APP'S OWN TYPE RATHER THAN ``L10nLocale``. The generated file imports
    /// nothing, so whatever it compares against has to be declared in this module.
    enum CopyLocale: Equatable {
        case en
        case frCA
    }

    /// What every generated accessor branches on.
    static var copyLocale: CopyLocale {
        L10nRuntime.locale == .frCA ? .frCA : .en
    }

    /// Called on the main thread after each language change the observer in ``bootstrap()``
    /// applies (not at launch). The app sets it once, to ``AccountLanguageSync``.
    @MainActor static var onChange: (@MainActor () -> Void)?

    /// Sets the language at launch, and again whenever the device's language changes.
    ///
    /// ⚠️ A LANGUAGE CHOSEN IN SYSTEM SETTINGS TAKES EFFECT WHEN THE APP IS NEXT OPENED
    /// (the bundle's preferred localizations are fixed for the life of the process), so the
    /// launch reading is the one that usually counts; the observer covers a locale change
    /// the process survives.
    static func bootstrap() {
        apply(bundle: .main)
        _ = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            apply(bundle: .main)
            // ⚠️ THE OBSERVER'S QUEUE IS `.main`, so this runs on the main thread.
            MainActor.assumeIsolated { onChange?() }
        }
    }

    /// The language for a bundle and a device's preferred languages.
    ///
    /// ⚠️ THE BUNDLE'S OWN ANSWER COMES FIRST. `preferredLocalizations` is the
    /// language macOS chose among the ones this build ships (the per-app language in
    /// System Settings included), and the first tag the core speaks decides
    /// (``DistrictL10n/locale(fromPreferred:)``: any French is Canadian French). The
    /// device list after it only matters when the bundle answered nothing.
    static func resolve(
        preferredLocalizations: [String],
        preferredLanguages: [String],
        bundleLocalizations: [String]
    ) -> L10nLocale {
        guard bundleLocalizations.contains(where: { $0.lowercased().hasPrefix("fr") }) else {
            return .en
        }
        return DistrictL10n.locale(fromPreferred: preferredLocalizations + preferredLanguages)
    }

    private static func apply(bundle: Bundle) {
        L10nRuntime.locale = resolve(
            preferredLocalizations: bundle.preferredLocalizations,
            preferredLanguages: Locale.preferredLanguages,
            bundleLocalizations: bundle.localizations
        )
    }
}
