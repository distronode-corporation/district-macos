import SwiftUI

/// The country list behind the flag button: searchable by name or code, the workspace's
/// home country and the two countries this product sells numbers in first, then every
/// country alphabetically in the app's language. Ported from district-ios's sheet (PR #95).
///
/// ⚠️ A POPOVER ON THE MAC, WHERE iOS HAS A SHEET: it opens from the button it changes and
/// closes with Escape or a click outside, so it needs no Cancel. About two hundred rows still
/// need the search field, which a `Menu` has nowhere to put.
///
/// ⛔ THE KEYBOARD DRIVES IT WITHOUT THE MOUSE. The search field has focus when it opens; the
/// up and down arrows move the highlight through the rows shown, Return picks the highlighted
/// row (the first match after a search), and Escape closes it.
///
/// ⚠️ DISMISS FIRST, THEN PICK, so the field re-reads under the new flag on a keypad that
/// is already back in front. A pick changes the country and never dials.
struct DialerCountryPicker: View {
    let home: String?
    let selected: String?
    let onPick: (String) -> Void

    @State private var query = ""
    /// The highlighted row, as a ``Row/id``: the same country can be listed twice (Suggested
    /// and All), and only one of the two rows is highlighted.
    @State private var highlighted: String?
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    /// One row of the list: a country under a section.
    struct Row: Identifiable, Equatable {
        let section: String
        let iso: String

        var id: String {
            section + ":" + iso
        }
    }

    /// The rows on screen, in order: Suggested then All with no search, else the matches.
    static func rows(query: String, home: String?, selected: String?) -> [Row] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return DialPlan.search(query).map { Row(section: "match", iso: $0) }
        }
        return DialPlan.suggested(home: home, current: selected).map { Row(section: "suggested", iso: $0) }
            + DialPlan.sortedCountries().map { Row(section: "all", iso: $0) }
    }

    /// The row the arrow keys land on from `current`, moving by `step`, clamped to the ends.
    static func move(from current: String?, by step: Int, in rows: [Row]) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(where: { $0.id == current }) else {
            return rows[step > 0 ? 0 : rows.count - 1].id
        }
        return rows[min(max(index + step, 0), rows.count - 1)].id
    }

    private var shown: [Row] {
        Self.rows(query: query, home: home, selected: selected)
    }

    var body: some View {
        VStack(spacing: 0) {
            search
            Divider()
            list
        }
        .frame(width: 320, height: 420)
        .background(colors.background)
        .onAppear {
            searching = true
            highlighted = shown.first(where: { $0.iso == selected })?.id ?? shown.first?.id
        }
    }

    private var search: some View {
        TextField(DialerCopy.countrySearch, text: $query, prompt: Text(DialerCopy.countrySearch))
            .autocorrectionDisabled()
            .focused($searching)
            .onChange(of: query) {
                highlighted = shown.first?.id
            }
            .onKeyPress(.downArrow) {
                highlighted = Self.move(from: highlighted, by: 1, in: shown)
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlighted = Self.move(from: highlighted, by: -1, in: shown)
                return .handled
            }
            .onSubmit {
                if let row = shown.first(where: { $0.id == highlighted }) ?? shown.first {
                    pick(row.iso)
                }
            }
            .onExitCommand { dismiss() }
            .districtField()
            .accessibilityLabel(DialerCopy.country)
            .padding(DistrictSpacing.tight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    rows
                }
            }
            .onChange(of: highlighted) {
                if let highlighted {
                    proxy.scrollTo(highlighted)
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let rows = shown
        if rows.isEmpty {
            Text(DialerCopy.countriesNoMatch)
                .font(DistrictType.bodySmall)
                .foregroundStyle(colors.mutedForeground)
                .padding(DistrictSpacing.gutter)
        }
        ForEach(rows) { item in
            if item.section != "match", item.id == rows.first(where: { $0.section == item.section })?.id {
                header(item.section == "suggested" ? DialerCopy.countriesSuggested : DialerCopy.countriesAll)
            }
            row(item)
        }
    }

    private func header(_ title: String) -> some View {
        DistrictEyebrow(text: title)
            .padding(.horizontal, DistrictSpacing.gutter)
            .padding(.top, DistrictSpacing.row)
            .padding(.bottom, DistrictSpacing.tight)
            .accessibilityAddTraits(.isHeader)
    }

    /// ⛔ THE CHOSEN COUNTRY IS A TRAIT, NOT ONLY A TICK, as on iOS.
    private func row(_ item: Row) -> some View {
        Button { pick(item.iso) } label: {
            DistrictListRow(
                title: DialPlan.name(item.iso),
                subtitle: DialPlan.callingCode(for: item.iso).map { "+" + $0 },
                leading: {
                    Text(DialPlan.flag(item.iso))
                        .font(DistrictType.headline)
                        .accessibilityHidden(true)
                },
                trailing: { checkmark(item.iso) }
            )
            .padding(.horizontal, DistrictSpacing.tight)
            .background {
                if item.id == highlighted {
                    RoundedRectangle(cornerRadius: DistrictRadius.control)
                        .fill(colors.district.opacity(DistrictColors.containerAlpha))
                }
            }
            .padding(.horizontal, DistrictSpacing.tight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                highlighted = item.id
            }
        }
        .id(item.id)
        .accessibilityAddTraits(item.iso == selected ? [.isSelected] : [])
        .accessibilityIdentifier(A11yID.Dialer.countryOption(item.iso))
    }

    @ViewBuilder
    private func checkmark(_ iso: String) -> some View {
        if iso == selected {
            Image(systemName: "checkmark")
                .font(DistrictType.labelLarge)
                .foregroundStyle(colors.district)
                .accessibilityHidden(true)
        }
    }

    private func pick(_ iso: String) {
        dismiss()
        onPick(iso)
    }
}
