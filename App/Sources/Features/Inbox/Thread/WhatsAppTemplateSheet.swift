import DistrictModel
import SwiftUI

/// What the composer shows in place of the reply box when the WhatsApp window has
/// closed: the website's sentence, and the button that opens the template sheet.
struct WhatsAppClosedWindow: View {
    let model: ThreadModel

    @State private var choosing = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
            Text(InboxCopy.whatsappWindowClosed)
                .font(DistrictType.caption)
                .foregroundStyle(DistrictColors.resolve(colorScheme).mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(InboxCopy.whatsappTemplatePlaceholder) { choosing = true }
                .buttonStyle(.districtPrimary)
                .accessibilityIdentifier(A11yID.Inbox.whatsAppTemplates)
        }
        .sheet(isPresented: $choosing) {
            WhatsAppTemplateSheet(model: model)
        }
    }
}

/// The sender's approved templates; one chosen, its variables, a preview and Send.
///
/// ⛔ ONLY APPROVED TEMPLATES ARE LISTED (``WhatsAppTemplate/isSendable``): Meta refuses
/// any other, and the website's picker offers the same set.
///
/// ⚠️ TWO STEPS IN ONE ``MacSheetChrome``, NOT A `NavigationStack`: a stack draws the
/// system's grey title bar over a Mac sheet (`MacSheetFitTests`). The list is the first
/// step; a chosen template replaces it with its form, and Back returns to the list.
struct WhatsAppTemplateSheet: View {
    let model: ThreadModel

    /// The chosen template's id, or nil while the list is on screen.
    @State private var chosen: String?
    /// One value per variable of the chosen template, reset on each choice.
    @State private var values: [String] = []

    @Environment(\.dismiss) private var dismiss

    private var template: WhatsAppTemplate? {
        guard let chosen, case let .ready(templates) = model.whatsApp.templates else { return nil }
        return templates.first { $0.id == chosen }
    }

    var body: some View {
        MacSheetChrome(title: template?.name ?? InboxCopy.whatsappTemplateLabel) {
            if let template {
                WhatsAppTemplateForm(model: model, template: template, values: $values)
            } else {
                list
            }
        } buttons: {
            buttons
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 360, idealHeight: 440)
        .task { await model.loadWhatsAppTemplates() }
        .accessibilityIdentifier(A11yID.Inbox.whatsAppTemplates)
    }

    @ViewBuilder
    private var buttons: some View {
        if let template {
            Button(InboxCopy.back) { chosen = nil }
                .disabled(model.whatsApp.sendingTemplate)
            Button(InboxCopy.cancel) { dismiss() }
                .disabled(model.whatsApp.sendingTemplate)
                .keyboardShortcut(.cancelAction)
            Button(model.whatsApp.sendingTemplate ? InboxCopy.sending : InboxCopy.whatsappTemplateSend) {
                Task {
                    if await model.sendWhatsAppTemplate(template, variables: values) {
                        dismiss()
                    }
                }
            }
            // ⛔ DISABLED FOR THE WHOLE ROUND TRIP: a template is billed by Meta, and a
            // second click must not send it twice (``WhatsAppComposer/sendingTemplate``).
            .disabled(!ThreadModel.templateComplete(template, values) || model.whatsApp.sendingTemplate)
            .keyboardShortcut(.districtSubmit)
            .macSheetDefaultButton()
            .accessibilityIdentifier(A11yID.Inbox.whatsAppTemplateSend)
        } else {
            Button(InboxCopy.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var list: some View {
        switch model.whatsApp.templates {
        case .idle, .loading:
            VStack(spacing: DistrictSpacing.tight) {
                ProgressView()
                Text(InboxCopy.whatsappTemplatesLoading)
                    .font(DistrictType.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(failure):
            FailureView(failure: FailureText(message: InboxCopy.whatsappTemplatesFailed, action: failure.action)) {
                Task { await model.loadWhatsAppTemplates() }
            }
        case let .ready(templates) where templates.isEmpty:
            EmptyStateView(
                systemImage: "text.bubble",
                title: InboxCopy.whatsappTemplateLabel,
                message: InboxCopy.whatsappTemplatesNone
            )
        case let .ready(templates):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(templates, id: \.id) { template in
                        Button { choose(template) } label: { row(template) }
                            .buttonStyle(.plain)
                        DistrictRowDivider()
                    }
                }
            }
        }
    }

    private func row(_ template: WhatsAppTemplate) -> some View {
        DistrictListRow(
            title: template.name,
            subtitle: template.body,
            trailing: { DistrictBadge(text: template.language, tone: .neutral) }
        )
    }

    private func choose(_ template: WhatsAppTemplate) {
        model.clearTemplateFailure()
        values = Array(repeating: "", count: ThreadModel.templateVariableCount(template))
        chosen = template.id
    }
}

/// One template: a field per variable, the filled text, and the refusal of the last send.
private struct WhatsAppTemplateForm: View {
    let model: ThreadModel
    let template: WhatsAppTemplate
    @Binding var values: [String]

    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    private var count: Int {
        ThreadModel.templateVariableCount(template)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DistrictSpacing.section) {
                if count > 0 {
                    VStack(alignment: .leading, spacing: DistrictSpacing.tight) {
                        ForEach(0 ..< count, id: \.self) { index in
                            VStack(alignment: .leading, spacing: DistrictSpacing.hairline) {
                                DistrictEyebrow(text: InboxCopy.whatsappTemplateVariable(index + 1))
                                TextField(
                                    InboxCopy.whatsappTemplateVariable(index + 1),
                                    text: binding(index),
                                    prompt: .noPlaceholder
                                )
                                .disabled(model.whatsApp.sendingTemplate)
                                .districtField()
                            }
                        }
                        if !ThreadModel.templateComplete(template, values) {
                            Text(InboxCopy.whatsappTemplateVariableRequired)
                                .font(DistrictType.caption)
                                .foregroundStyle(colors.mutedForeground)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: DistrictSpacing.hairline) {
                    DistrictEyebrow(text: InboxCopy.whatsappTemplatePreview)
                    Text(preview)
                        .font(DistrictType.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let failure = model.whatsApp.templateFailure {
                    Text(failure.message)
                        .font(DistrictType.caption)
                        .foregroundStyle(colors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DistrictSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// ⚠️ A BLANK VARIABLE STAYS `{{n}}` IN THE PREVIEW, so the operator sees where it
    /// goes; ``WhatsAppTemplate/filled(with:)`` would print nothing there.
    private var preview: String {
        let shown = (0 ..< count).map { index in
            let value = index < values.count ? values[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return value.isEmpty ? "{{\(index + 1)}}" : value
        }
        return template.filled(with: shown)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < values.count ? values[index] : "" },
            set: { value in
                if index < values.count {
                    values[index] = value
                }
            }
        )
    }
}
