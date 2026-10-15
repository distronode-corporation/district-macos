import DistrictL10n
import DistrictModel
import Foundation

/// Tells the server which language this app is in, so email, Voice Studio and the server's
/// own text match it: `POST /api/settings` with `{"profile":{"locale":"fr"|"en"}}`, through
/// the core's `AccountSettingsRepository/saveLocale(_:)`.
///
/// ⛔ WRITTEN ON EVERY SIGN-IN, AND WHENEVER THE LANGUAGE CHANGES. A completed sign-in (either
/// door, the authenticator step included) always writes, because the account may not be the
/// one this Mac wrote for last. A session found at launch writes only when the language
/// differs from the last one this Mac stored, which is how a language chosen in System
/// Settings (it takes effect when the app is next opened) still reaches the server; a change
/// the process survives arrives through ``AppL10n/onChange``.
///
/// ⚠️ LAST WRITER WINS against the website's language menu, by decision (v3 plan). A person
/// who picks English on the web and uses a French Mac gets French email again the next time
/// this Mac signs in or changes language, and not before.
///
/// ⚠️ A FAILED WRITE IS NOT RETRIED ON A TIMER. Nothing is remembered, so the next sign-in,
/// launch or language change writes again; the language the server falls back to meanwhile
/// is the `Accept-Language` every request already carries.
///
/// ⛔ ONE WRITE AT A TIME. A language that changes while a write is on its way is written
/// after it, so the server ends on the language the app ends on.
@MainActor
final class AccountLanguageSync {
    typealias Save = @Sendable (L10nLocale) async -> Result<Void, ApiError>

    /// ⚠️ Namespaced like ``WorkspaceSelectionStore/defaultsKey``.
    static let defaultsKey = "com.distronode.district.accountLanguage"

    private let save: Save
    private let defaults: UserDefaults
    private let current: () -> L10nLocale

    /// Whether the session is signed in right now; nothing is written otherwise.
    private var signedIn = false

    /// Bumped whenever a write on its way must not be recorded: a sign-out, a new sign-in.
    private var generation = 0

    /// The write on its way, if any. ⚠️ Exposed for the tests, which wait on it.
    private(set) var writing: Task<Void, Never>?

    init(
        save: @escaping Save,
        defaults: UserDefaults = .standard,
        current: @escaping () -> L10nLocale = { L10nRuntime.locale }
    ) {
        self.save = save
        self.defaults = defaults
        self.current = current
    }

    /// The language this Mac last stored on the server for the signed-in account, or nil.
    var written: L10nLocale? {
        defaults.string(forKey: Self.defaultsKey).flatMap(L10nLocale.init(rawValue:))
    }

    /// A sign-in completed. Called BEFORE the session reports `.signedIn`, so that report
    /// writes whatever this Mac stored before.
    func signInCompleted() {
        forget()
    }

    /// The session's phase moved (``SessionModel``).
    func sessionChanged(_ phase: AuthPhase) {
        switch phase {
        case .signedIn:
            signedIn = true
            syncIfNeeded()
        case .signedOut:
            // ⚠️ THE NEXT ACCOUNT IS NOBODY WE WROTE FOR.
            signedIn = false
            forget()
        case .checking, .unavailable:
            // The session may be intact; what was stored stays, and nothing new is sent.
            signedIn = false
        }
    }

    /// The app's language changed while it was running (``AppL10n/onChange``).
    func languageChanged() {
        syncIfNeeded()
    }

    private func syncIfNeeded() {
        guard signedIn, writing == nil else { return }
        let target = current()
        guard written != target else { return }
        let generation = generation
        let save = save
        writing = Task { [weak self] in
            let result = await save(target)
            self?.finished(target, result: result, generation: generation)
        }
    }

    private func finished(_ target: L10nLocale, result: Result<Void, ApiError>, generation: Int) {
        guard generation == self.generation else { return }
        writing = nil
        guard case .success = result else { return }
        defaults.set(target.rawValue, forKey: Self.defaultsKey)
        // ⚠️ THE LANGUAGE MAY HAVE MOVED WHILE THIS WAS ON ITS WAY.
        syncIfNeeded()
    }

    private func forget() {
        generation += 1
        writing?.cancel()
        writing = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
