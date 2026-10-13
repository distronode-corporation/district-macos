import Foundation

/// Every sentence the billing screen says.
///
/// ⚠️ ITS OWN FILE RATHER THAN AN EXTENSION AT THE BOTTOM OF A SCREEN, the same call
/// ``DialerCopy`` and ``WorkflowsCopy`` make: `swiftlint --strict` promotes the
/// `file_length` WARNING at 500 lines to an error, and the copy for a screen with six
/// cards and four degraded states is most of a file on its own.
///
/// ⛔ THERE IS NO "UPGRADE", NO "MANAGE BILLING" AND NO "OPEN INVOICE" STRING IN HERE,
/// AND THE ABSENCE IS THE POINT. App Store Review Guideline 3.1.3(b) keeps subscription
/// purchase and management out of the app entirely, so this screen states what is being
/// billed and states the limitation. ⛔ IT NAMES NO DESTINATION EITHER:
/// 3.1.1 anti-steering makes "on the web dashboard at distronode.com" the rejection just
/// as surely as a button would be, so every sentence here says what cannot be done in
/// this app and stops. `StoreCopyTests` fails the build if one names a place.
/// Android's screen hands a Stripe hosted invoice URL out to be opened
/// (`onOpenInvoice`, `billing_invoice_open`); that is the one place where matching
/// Android would fail review, so it is deliberately not ported. A string added here that
/// reads as a control is the rejection.
///
/// ⛔ THE COPY IS THE ANDROID CLIENT'S WHERE ANDROID HAS A STRING, so the two apps say
/// the same thing about the same bill. Three are load bearing:
/// "No plan on this workspace" rather than "Free", "Calls are being declined" rather than
/// a generic over-limit note, and the unavailable body rather than an empty invoice list.
///
/// ⚠️ ANDROID'S EM DASHES ARE COMMAS HERE. The repo's house style avoids em dashes, and
/// VoiceOver reads one as nothing at all, so a sentence hinging on one loses its hinge.
enum BillingCopy {
    // MARK: - The plan card

    /// The plan names a customer reads, keyed by the stored tier
    /// (``WorkspaceBilling/subscriptionTier``) lowercased.
    ///
    /// ⛔ THE SERVER'S `PLAN_TIER_LABELS` (distronode-website
    /// `src/lib/payments/plan-urls.ts`), WORD FOR WORD: the names the pricing page and
    /// checkout show. The column holds the internal key ("VoicePro"), and printing it
    /// raw put a name on screen that no page of ours uses. Product marks, so never
    /// translated.
    static var planTierLabels: [String: String] {
        [
            "voicesolo": planNameVoiceSolo,
            "voicestarter": planNameVoiceStarter,
            "voicepro": planNameVoicePro,
            "voicestudio": planNameVoiceStudio,
        ]
    }

    /// The plan card's headline: the plan's name for a known tier, any other tier
    /// exactly as the server sent it, and ``planNone`` when there is none.
    ///
    /// ⚠️ LOOKED UP TRIMMED AND LOWERCASED, because nothing normalises the column on
    /// write (see ``BillingFormat/normalisedStatus(_:)``). ⚠️ AN UNKNOWN TIER IS SHOWN AS
    /// SENT, not hidden and not guessed at: a plan added on the server after this build
    /// still names itself, just in its stored spelling. A blank one names no plan.
    static func planName(_ tier: String?) -> String {
        guard let tier, !tier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return planNone }
        return planTierLabels[BillingFormat.normalisedStatus(tier)] ?? tier
    }
}
