import Foundation

/// The words of the authenticator-code step after Sign in with Apple.
///
/// ⚠️ ONE HOME, AS ``SessionCopy`` AND ``SignInCopy`` HAVE: its sentences are the catalog's
/// (`l10n/macos.toml`), in English or Canadian French.
///
/// ⛔ ``expired`` TELLS THE PERSON WHAT TO DO, because it is the one refusal no amount
/// of typing can fix: the ticket is gone and only a fresh Apple sign-in mints another.
/// It is shown as the sign-in screen's reason.
///
/// ⚠️ WORD FOR WORD THE iOS APP'S `MfaCopy`, so the two Apple apps say the same thing.
enum MfaCopy {}
