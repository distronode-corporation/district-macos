import SwiftUI

/// Which slot of a ``DistrictListRow`` a subview fills, for ``DistrictRowLayout``.
enum DistrictRowSlot {
    case leading
    case title
    case subtitle
    case trailing
}

struct DistrictRowSlotKey: LayoutValueKey {
    static let defaultValue = DistrictRowSlot.title
}

/// The arrangement of a ``DistrictListRow``: the leading slot, the title over the subtitle,
/// and the trailing slot (badges, a chevron) beside them or underneath.
///
/// ⚠️ MAC ONLY. The iPad (district-ios `4777c40`) always puts the trailing slot beside the
/// text, in an `HStack` where the badges are sized first and the text truncates. In a Mac
/// list column, where a row is about 400pt wide, that cut the very thing the row is for:
/// "P..." and "Sean De..." beside four channel badges in the Inbox, and "Oct 3, 2026 at
/// 12:..." beside two chips in Support (Sean's first build, 20019). So:
///
/// - **Beside** whenever the title (and the subtitle too, with `subtitleMustFit`) fits in
///   full next to the trailing slot. That is the iPad's row, and most rows.
/// - **Underneath** otherwise: the trailing slot goes on its own line under the subtitle,
///   aligned with the text, and the title gets the whole width.
///
/// The rule is ``arrangement(available:leading:mustFit:trailing:)``, a pure function that
/// `DistrictRowLayoutTests` pins. At an accessibility size every slot stacks (``Mode/vertical``),
/// as the row did before.
///
/// ⚠️ THE TRAILING SLOT IS NEVER `fixedSize`, for the reason the row's own doc gives: the
/// Inbox can emit five badges, and underneath they are proposed the text's width, so a
/// wider set compresses rather than overflowing the row.
struct DistrictRowLayout: Layout {
    enum Mode {
        /// Beside when the title fits, underneath when it does not.
        case adaptive
        /// Every slot on its own line (an accessibility text size).
        case vertical
    }

    enum Arrangement: Equatable {
        case beside
        case stacked
    }

    var mode: Mode
    var subtitleMustFit: Bool
    var spacing: CGFloat = DistrictSpacing.row
    var lineSpacing: CGFloat = 2
    var stackedSpacing: CGFloat = DistrictSpacing.hairline
    var verticalSpacing: CGFloat = DistrictSpacing.tight

    /// Whether the trailing slot sits beside the text, from ideal widths.
    ///
    /// - Parameters:
    ///   - available: the row's width.
    ///   - leading: the leading slot's width, zero when there is none.
    ///   - mustFit: the width of the text that must read in full (the title, or the wider of
    ///     the title and the subtitle).
    ///   - trailing: the trailing slot's ideal width, zero when it is empty.
    static func arrangement(
        available: CGFloat,
        leading: CGFloat,
        mustFit: CGFloat,
        trailing: CGFloat,
        spacing: CGFloat = DistrictSpacing.row
    ) -> Arrangement {
        guard trailing > 0 else { return .beside }
        let lead = leading > 0 ? leading + spacing : 0
        return lead + mustFit + spacing + trailing <= available ? .beside : .stacked
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let plan = plan(width: proposal.width, subviews: subviews)
        return CGSize(width: plan.width, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        let plan = plan(width: bounds.width, subviews: subviews)
        // ⚠️ CENTRED IN WHATEVER HEIGHT THE ROW WAS GIVEN (its 56pt minimum can exceed the plan).
        let top = bounds.minY + max(0, (bounds.height - plan.height) / 2)
        for (index, frame) in plan.frames {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: top + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    // ── The plan ─────────────────────────────────────────────────────────────

    private struct Plan {
        var width: CGFloat
        var height: CGFloat
        var frames: [(Int, CGRect)]
    }

    /// The slots' subview indices and their ideal sizes.
    private struct Slots {
        let leading: Int?
        let title: Int?
        let subtitle: Int?
        let trailing: Int?
        let leadSize: CGSize
        let titleIdeal: CGSize
        let subtitleIdeal: CGSize
        let trailingIdeal: CGSize

        init(_ subviews: Subviews) {
            func index(_ slot: DistrictRowSlot) -> Int? {
                subviews.indices.first { subviews[$0][DistrictRowSlotKey.self] == slot }
            }
            func ideal(_ slot: Int?) -> CGSize {
                slot.map { subviews[$0].sizeThatFits(.unspecified) } ?? .zero
            }
            leading = index(.leading)
            title = index(.title)
            subtitle = index(.subtitle)
            trailing = index(.trailing)
            leadSize = ideal(leading)
            titleIdeal = ideal(title)
            subtitleIdeal = ideal(subtitle)
            trailingIdeal = ideal(trailing)
        }

        var textIdeal: CGFloat {
            max(titleIdeal.width, subtitleIdeal.width)
        }
    }

    private func plan(width proposed: CGFloat?, subviews: Subviews) -> Plan {
        let slots = Slots(subviews)
        let lead = slots.leadSize.width > 0 ? slots.leadSize.width + spacing : 0
        let trailingGap = slots.trailingIdeal.width > 0 ? spacing + slots.trailingIdeal.width : 0
        let width = proposed ?? (lead + slots.textIdeal + trailingGap)
        if mode == .vertical {
            let order = [slots.leading, slots.title, slots.subtitle, slots.trailing]
            return verticalPlan(width: width, slots: order, subviews: subviews)
        }
        let arrangement = Self.arrangement(
            available: width,
            leading: slots.leadSize.width,
            mustFit: subtitleMustFit ? slots.textIdeal : slots.titleIdeal.width,
            trailing: slots.trailingIdeal.width,
            spacing: spacing
        )
        return adaptivePlan(width: width, lead: lead, arrangement: arrangement, slots: slots, subviews: subviews)
    }

    private func adaptivePlan(
        width: CGFloat,
        lead: CGFloat,
        arrangement: Arrangement,
        slots: Slots,
        subviews: Subviews
    ) -> Plan {
        func size(_ slot: Int?, width: CGFloat) -> CGSize {
            slot.map { subviews[$0].sizeThatFits(ProposedViewSize(width: width, height: nil)) } ?? .zero
        }
        let beside = arrangement == .beside
        let besideTrailing = min(slots.trailingIdeal.width, max(0, width - lead))
        let textWidth = beside
            ? max(0, width - lead - (besideTrailing > 0 ? spacing + besideTrailing : 0))
            : max(0, width - lead)
        let trailingSize = size(slots.trailing, width: beside ? besideTrailing : textWidth)
        let titleSize = size(slots.title, width: textWidth)
        let subtitleSize = size(slots.subtitle, width: textWidth)
        let textHeight = titleSize.height + (slots.subtitle == nil ? 0 : lineSpacing + subtitleSize.height)
        let blockHeight = !beside && trailingSize.height > 0
            ? textHeight + stackedSpacing + trailingSize.height
            : textHeight
        let height = max(slots.leadSize.height, blockHeight, beside ? trailingSize.height : 0)

        var frames: [(Int, CGRect)] = []
        if let leading = slots.leading {
            let top = (height - slots.leadSize.height) / 2
            frames.append((leading, CGRect(origin: CGPoint(x: 0, y: top), size: slots.leadSize)))
        }
        let textTop = (height - blockHeight) / 2
        if let title = slots.title {
            frames.append((title, CGRect(x: lead, y: textTop, width: textWidth, height: titleSize.height)))
        }
        if let subtitle = slots.subtitle {
            let top = textTop + titleSize.height + lineSpacing
            frames.append((subtitle, CGRect(x: lead, y: top, width: textWidth, height: subtitleSize.height)))
        }
        if let trailing = slots.trailing {
            let origin = beside
                ? CGPoint(x: width - trailingSize.width, y: (height - trailingSize.height) / 2)
                : CGPoint(x: lead, y: textTop + textHeight + stackedSpacing)
            frames.append((trailing, CGRect(origin: origin, size: trailingSize)))
        }
        return Plan(width: width, height: height, frames: frames)
    }

    /// Every slot on its own line, the full width each, in reading order.
    private func verticalPlan(width: CGFloat, slots: [Int?], subviews: Subviews) -> Plan {
        var frames: [(Int, CGRect)] = []
        var top: CGFloat = 0
        for case let slot? in slots {
            let size = subviews[slot].sizeThatFits(ProposedViewSize(width: width, height: nil))
            guard size.height > 0 else { continue }
            if !frames.isEmpty {
                // ⚠️ THE TITLE AND THE SUBTITLE KEEP THEIR OWN TIGHTER PAIRING.
                let pair = subviews[slot][DistrictRowSlotKey.self] == .subtitle
                top += pair ? lineSpacing : verticalSpacing
            }
            frames.append((slot, CGRect(x: 0, y: top, width: min(size.width, width), height: size.height)))
            top += size.height
        }
        return Plan(width: width, height: top, frames: frames)
    }
}
