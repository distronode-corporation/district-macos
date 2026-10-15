import DistrictL10n
import DistrictModel
import SwiftUI

// One number's own actions, and the billable lookup.
//
// ⛔ THE TWO CONTROLS HERE ARE NOT PEERS. Reapplying routing is idempotent and converges, so
// it commits on a tap; releasing takes a live line out of service and generally cannot be
// reclaimed, so it goes through a confirmation that says the callers reach NOTHING. Giving
// them the same weight would be the more dangerous error: a confirmation on the harmless one
// trains the operator to dismiss the one that matters.
//
// ⛔ AND A MANAGED NUMBER OFFERS NEITHER. `managed: true` means the line is held on
// Distronode's carrier account, so it is the tenant's to USE and not to administer, and the
// caption says why rather than leaving a missing button to be read as a bug.
//
// ⛔ THE LOOKUP IS BILLABLE PER TAP AND IS THE MOST INNOCUOUS-LOOKING CONTROL ON THE SCREEN,
// which is exactly why it is confirmed at all. It must never fire on a keystroke, on appear or
// in a retry loop.
//
// ⚠️ A `//` HEADER RATHER THAN A `///` ONE: SwiftFormat's `docComments` rule rejects a doc
// comment attached to no declaration.

/// What can be done to one number the workspace holds.
struct NumberActionsSheet: View {
    let model: NumberProvisioningModel
    let number: ListedNumber

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    /// ⚠️ MAC: THE SHEET'S BUTTONS SIT IN ONE ROW AT THE BOTTOM TRAILING EDGE, Close last and
    /// on Esc, as a Mac sheet lays them out. They were stacked down the left edge with Close
    /// as plain text under them and an empty half sheet below (3.0.1 visual QA). Releasing
    /// stays apart from the routing, on the leading side of the row, because it is the one
    /// that takes the line away.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DistrictSpacing.row) {
                    Text(number.phoneNumber)
                        .font(DistrictType.titleLarge)
                        .foregroundStyle(colors.foreground)
                    Text(NumberWireText.meta(number))
                        .font(DistrictType.bodySmall)
                        .foregroundStyle(colors.mutedForeground)
                    NumberWriteNotice(state: model.numberWrite)
                    details
                }
                .padding(DistrictSpacing.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            buttonRow
                .padding(DistrictSpacing.gutter)
        }
    }

    /// ⛔ NOT NAMED `body(for:)`. `View` declares a `body` requirement and an associated `Body`
    /// type, and the family of names that become accidental witnesses is wider than it looks
    /// (`Body`, `Content`, `Label`, `ID`, `Value`, `Configuration`), see the ⛔ in
    /// `DistrictButton.swift`.
    @ViewBuilder
    private var details: some View {
        if number.managed {
            // ⛔ NOT THE TENANT'S TO ADMINISTER, AND THE CAPTION SAYS SO. See the ⛔ at the top
            // of this file.
            caption(MarketplaceCopy.managedNoRelease)
        } else if model.canProvision {
            caption(MarketplaceCopy.configureCaption)
        } else {
            caption(MarketplaceCopy.viewerCannotProvision)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DistrictType.bodySmall)
            .foregroundStyle(colors.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttonRow: some View {
        HStack(spacing: DistrictSpacing.tight) {
            if !number.managed, model.canProvision {
                release
                Spacer(minLength: DistrictSpacing.gutter)
                configure
            } else {
                Spacer(minLength: 0)
            }
            // ⚠️ MAC: A MAC SHEET HAS NO SWIPE TO DISMISS, so it gets a Close that takes Esc.
            Button(MarketplaceCopy.close) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    /// ⚠️ IDEMPOTENT, SO IT COMMITS ON A CLICK. It writes the same webhooks and restates the
    /// same trunk binding every time. ⛔ And it is not the no-op it looks like: restating that
    /// binding is what keeps an EU number answered in Europe. Its caption is the sheet's text.
    private var configure: some View {
        Button(MarketplaceCopy.configureAction) {
            Task { await model.configure(phoneNumber: number.phoneNumber) }
        }
        .disabled(!model.numberWrite.isArmed)
    }

    /// ⛔ THROUGH A CONFIRMATION, ALWAYS, AND THE CONFIRMATION NAMES THE CONSEQUENCE RATHER THAN
    /// SAYING "this cannot be undone". The number goes back to the carrier's pool and everyone
    /// dialling it reaches nothing.
    private var release: some View {
        Button(MarketplaceCopy.releaseAction, role: .destructive) {
            model.requestConfirmation(.release(phoneNumber: number.phoneNumber))
        }
        // ⚠️ THE DESTRUCTIVE INK, WHICH A MAC BUTTON'S ROLE DOES NOT DRAW ON ITS OWN: under
        // the app's accent tint it read as a peer of Reapply.
        .tint(colors.destructive)
        .disabled(!model.numberWrite.isArmed)
        // ⛔ IDENTIFIED SO A TEST CAN ASSERT IT EXISTS AND NEVER PRESS IT. It is in
        // `UITestApp.forbiddenSurfaces` and the tap helper refuses it outright:
        // releasing a number is irreversible, billed, and against the live workspace.
        .accessibilityIdentifier(A11yID.Marketplace.release)
    }
}

/// The billable number lookup.
///
/// ⛔ ONE TAP, ONE LOOKUP, AND ONLY FROM A CONFIRMATION THAT SAYS IT COSTS MONEY. The carrier
/// bills every request and line-type intelligence costs more than a basic one; the route is a
/// GET that admits `viewer`, so nothing downstream caps it and 60/minute is a runaway brake
/// rather than a budget. ⛔ There is deliberately no submit-on-return and no `.task` here: the
/// web validates numbers as an operator types, which is defensible on a desktop form and is not
/// on a phone where a scroll can re-run an effect.
///
/// ⚠️ THE RESULT IS KEPT APART FROM THE WRITE STATE, so opening a second confirmation does not
/// blank the answer the operator is reading. ⚠️ And `valid: false` is a real answer that already
/// cost money rather than an empty state.
struct NumberLookupCard: View {
    let model: NumberProvisioningModel

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        SettingsCard(eyebrow: MarketplaceCopy.lookupEyebrow) {
            SettingsField(
                label: MarketplaceCopy.lookupNumberLabel,
                text: Binding(get: { model.lookupNumber }, set: { model.lookupNumber = $0 }),
                enabled: !model.lookupWrite.isRunning
            )
            Text(MarketplaceCopy.lookupConfirmBody)
                .font(DistrictType.caption)
                .foregroundStyle(colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Button(MarketplaceCopy.lookupAction) {
                model.requestConfirmation(.lookup(phoneNumber: model.lookupNumber))
            }
            .buttonStyle(.districtSecondary)
            .disabled(model.lookupNumber.isEmpty || !model.lookupWrite.isArmed)
            NumberWriteNotice(state: model.lookupWrite)
            result
        }
    }

    @ViewBuilder
    private var result: some View {
        if let summary = model.lookupResult {
            Text(MarketplaceCopy.lookupResult(summary))
                .font(DistrictType.bodySmall)
                .foregroundStyle(colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
