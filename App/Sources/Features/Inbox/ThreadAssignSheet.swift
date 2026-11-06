import SwiftUI

/// The members a conversation can be assigned to, Unassigned first, the current owner
/// ticked. One click writes; the sheet closes when the server affirms it.
///
/// ⚠️ THE WEB'S PICKER, AS A LIST. The website's thread header holds a select with the
/// same options (`ThreadAssignee.tsx`): Unassigned, then each member's address. On the Mac
/// the Inbox toolbar's Assign… and a row's context menu open this; district-ios opens it
/// from a row's swipe action.
///
/// ⚠️ DRAWN IN ``MacSheetChrome``, AS ``WorkspacePickerSheet`` IS: rows that are buttons, a
/// tick on the current one (a trait as well as a glyph), and a Cancel that takes Esc.
struct ThreadAssignSheet: View {
    let model: ThreadAssignModel
    let onAssigned: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        MacSheetChrome(title: InboxCopy.assignLabel) {
            content
        } buttons: {
            Button(InboxCopy.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 420)
        .task { await model.load() }
        .accessibilityIdentifier(A11yID.Inbox.assignSheet)
    }

    @ViewBuilder
    private var content: some View {
        switch model.members {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(failure):
            FailureView(failure: failure) { Task { await model.load() } }
        case let .ready(emails):
            VStack(spacing: 0) {
                // ⛔ PINNED ABOVE THE ROSTER, NOT AT ITS END (Seer, #95): a long member list
                // scrolled the refusal out of sight, so a failed write looked like nothing happened.
                if let failure = model.failure {
                    Text(failure.message)
                        .font(DistrictType.caption)
                        .foregroundStyle(colors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DistrictSpacing.gutter)
                        .padding(.vertical, DistrictSpacing.row)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        row(InboxCopy.unassigned, email: nil)
                        ForEach(emails, id: \.self) { email in
                            row(email, email: email)
                        }
                    }
                }
            }
            .disabled(model.saving)
        }
    }

    private func row(_ title: String, email: String?) -> some View {
        VStack(spacing: 0) {
            Button {
                Task { await choose(email) }
            } label: {
                // ⛔ THE SLOT LABELLED: a bare trailing closure is `ambiguous use of 'init'`.
                DistrictListRow(title: title, trailing: { checkmark(email) })
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent(email) ? .isSelected : [])
            DistrictRowDivider()
        }
    }

    @ViewBuilder
    private func checkmark(_ email: String?) -> some View {
        if isCurrent(email) {
            Image(systemName: "checkmark")
                .font(DistrictType.labelLarge)
                .foregroundStyle(colors.district)
                .accessibilityHidden(true)
        }
    }

    private func isCurrent(_ email: String?) -> Bool {
        guard let email else { return model.current == nil }
        return model.current?.caseInsensitiveCompare(email) == .orderedSame
    }

    /// ⚠️ CHOOSING THE CURRENT OWNER CLOSES WITHOUT A WRITE: the server would answer the
    /// same assignment and push the assignee again.
    private func choose(_ email: String?) async {
        guard !isCurrent(email) else {
            dismiss()
            return
        }
        guard await model.assign(email) else { return }
        onAssigned()
        dismiss()
    }
}
