import SwiftUI

// ⚠️ ONE TYPE OUT OF district-ios `Features/Settings/SettingsChrome.swift`, ported early
// because the Inbox's compose sheet uses it. When Wave 8 ports the rest of that file,
// it ports it WITHOUT this type (or deletes this file), so there is one definition.

/// One labelled text box, on the palette rather than the platform's.
///
/// ⚠️ THE LABEL IS A `Text` ABOVE THE FIELD rather than a placeholder, matching
/// ``CreateContactSheet``: a placeholder disappears the moment someone types, which
/// on a form of three similar boxes is where the wrong value gets saved into the
/// wrong field.
///
/// ⛔ "ON THE PALETTE RATHER THAN THE PLATFORM'S" IS LOAD-BEARING, because this is the
/// most reused field in the app. `.textFieldStyle(.roundedBorder)` with no background
/// lets UIKit paint its own near-black fill, which covers a large share of a form screen
/// such as the Agent persona. The treatment comes from ``View/districtField()``; see the
/// ⛔ there.
///
/// ⚠️ THE `prompt:` CARRIES THE SAME STRING AS THE TITLE, DELIBERATELY. The title is
/// what VoiceOver announces as the field's name and must not move; the prompt is the
/// only seam that can put the placeholder on ``DistrictColors/mutedForeground``
/// instead of the platform's grey. Both are `label`, so nothing on screen or in the
/// accessibility tree reads differently.
struct SettingsField: View {
    let label: String
    let text: Binding<String>
    var enabled = true
    /// ⚠️ Multi-line for prose (a greeting, a personality) and single-line for a
    /// name or a number. `axis:` rather than a separate editor so the two share one
    /// component and one disabled state.
    var multiline = false

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.hairline) {
            Text(label)
                .font(DistrictType.labelSmall)
                .foregroundStyle(colors.mutedForeground)
            box
        }
    }

    /// ⚠️ Hoisted out of the two branches below so the placeholder is written once.
    private var prompt: Text {
        Text(label).foregroundStyle(colors.mutedForeground)
    }

    @ViewBuilder
    private var box: some View {
        if multiline {
            TextField(label, text: text, prompt: prompt, axis: .vertical)
                .lineLimit(3 ... 8)
                .disabled(!enabled)
                .districtField()
        } else {
            TextField(label, text: text, prompt: prompt)
                .disabled(!enabled)
                .districtField()
        }
    }
}
