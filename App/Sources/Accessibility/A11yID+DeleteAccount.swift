/// The in-app account deletion sheet (Account, Delete account).
///
/// ⚠️ EVERY IDENTIFIER HERE IS COPIED UNCHANGED FROM district-ios's `A11yID.DeleteAccount`, so
/// one test plan addresses the same controls in both apps. No Kotlin twin yet: Android still
/// hands deletion to its page. If it gains the same flow, the three apps should share these
/// strings.
extension A11yID {
    enum DeleteAccount {
        static let sheet = "district-delete-account-sheet"
        static let cancel = "district-delete-account-cancel"
        static let message = "district-delete-account-message"
        static let usePassword = "district-delete-account-use-password"
        /// One button per provider, keyed by its wire name (`google`, `azure-ad`, `apple`).
        static func provider(_ wire: String) -> String {
            "district-delete-account-provider-\(wire)"
        }

        static let password = "district-delete-account-password"
        static let code = "district-delete-account-code"
        static let passwordContinue = "district-delete-account-password-continue"
        static let back = "district-delete-account-back"
        static let email = "district-delete-account-email"
        /// ⛔ A FORBIDDEN SURFACE: deletes the signed-in account. No UI test presses it.
        static let submit = "district-delete-account-submit"
    }
}
