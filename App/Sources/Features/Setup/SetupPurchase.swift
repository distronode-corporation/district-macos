import StoreKit

/// Whether step 2 may offer the web's setup page for buying a number.
///
/// ⛔ ONLY ON THE US STOREFRONT (Sean, 2026-11-15: "US storefront only"). Guideline 3.1.3(f)
/// lets a VoIP app sell its numbers outside the app, but a call to action to buy elsewhere is
/// allowed only on the United States storefront, so everywhere else the step says, with no
/// link and no destination, that numbers are not bought in this app
/// (``SetupCopy/numberNoneBodyNoPurchase``, the marketplace's `purchase_elsewhere` wording).
///
/// ⚠️ A DEVELOPER ID BUILD HAS NO STOREFRONT, so it reads as not US: it is the same app as the
/// store's, and the decision is one rule rather than one per channel.
enum SetupPurchase {
    /// The storefront's country is ISO 3166-1 alpha-3 (`Storefront.countryCode`), so the US is
    /// `USA`, never `US`.
    static func isOffered(storefront countryCode: String?) -> Bool {
        countryCode == "USA"
    }

    /// The App Store storefront this Mac buys from, or nil (no storefront, or none readable).
    static func liveStorefront() async -> String? {
        #if DEVELOPER_ID
            return nil
        #else
            return await Storefront.current?.countryCode
        #endif
    }
}
