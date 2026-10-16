import DistrictModel
import SwiftUI

/// The workspace switcher.
///
/// ⛔ IT CAPTIONS A PARTIAL LIST, AND THAT IS THE WHOLE REASON IT IS NOT A PLAIN
/// MENU. Android used a `DropdownMenu`, which has nowhere to put a sentence, so a
/// list short by one unreachable region looked exactly like a complete one, and the
/// user's own workspace appearing to have vanished is indistinguishable from
/// account loss. A sheet has room to say so.
///
/// ⚠️ THE ROWS ARE THE SERVER'S OWN ORDER. It has already applied owned-first
/// ordering and index 0 is what the browser would consider active; re-sorting here
/// would make the app and the browser disagree about which tenant is in view.
struct WorkspacePickerSheet: View {
    let workspaceSession: WorkspaceSessionModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var colors: DistrictColors {
        .resolve(colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // ⚠️ KEPT BESIDE `macSheetBackground()` BELOW: that paints the sheet, which
                // is BEHIND this `NavigationStack`, and a stack can draw a container
                // background of its own over it (see `ShellBackground.swift`). This fill
                // is inside the stack, so the rows sit on the palette either way.
                colors.background.ignoresSafeArea()
                rows
            }
            .navigationTitle(WorkspacesCopy.workspaces)
            // ⚠️ A MAC SHEET HAS NO SWIPE TO DISMISS, so it carries the Cancel that
            // takes Esc; and no size of its own, so it states one.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WorkspacesCopy.cancel) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 420)
        .macSheetBackground()
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                caption
                ForEach(workspaceSession.workspaces, id: \.id) { entry in
                    // ⛔ WHICH WORKSPACE IS CURRENT IS A TRAIT, NOT A TICK. See the
                    // ⛔ on `CallHandlingView.modeRow`: announced as a glyph name the
                    // state is unreadable, and every other row says nothing to
                    // distinguish itself. On this sheet that matters more than most,
                    // picking the wrong workspace is picking the wrong company's data.
                    Button { select(entry.id) } label: { row(for: entry) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            entry.id == workspaceSession.workspaceId ? [.isSelected] : []
                        )
                    DistrictRowDivider()
                }
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if case let .partial(_, _, regions) = workspaceSession.state {
            PartialWorkspacesCaption(regions: regions)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DistrictSpacing.gutter)
                .padding(.vertical, DistrictSpacing.row)
        }
    }

    private func row(for entry: WorkspaceEntry) -> some View {
        DistrictListRow(
            title: entry.name,
            subtitle: Self.subtitle(for: entry),
            // ⛔ LABELLED SLOTS. A bare trailing closure here is `ambiguous use of
            // 'init'`, see the ⛔ above the constrained initialisers in
            // `DistrictListRow.swift`.
            leading: { DistrictAvatar(name: entry.name) },
            trailing: { checkmark(for: entry) }
        )
    }

    @ViewBuilder
    private func checkmark(for entry: WorkspaceEntry) -> some View {
        if entry.id == workspaceSession.workspaceId {
            Image(systemName: "checkmark")
                .font(DistrictType.labelLarge)
                .foregroundStyle(colors.district)
                .accessibilityHidden(true)
        }
    }

    /// ⚠️ DISMISS FIRST, THEN SWITCH, which is what Android's menu does. ``select``
    /// re-reads the list, so ``WorkspaceSessionModel/state`` returns to `.loading`
    /// and the shell's gate replaces the whole tab bar for the duration; leaving the
    /// sheet up over that would show a picker floating above a spinner.
    ///
    /// ⚠️ AN UNSTRUCTURED `Task` DELIBERATELY. It must outlive this view, which is
    /// being dismissed on the line above; the work belongs to the session model.
    private func select(_ workspaceId: String) {
        dismiss()
        Task { await workspaceSession.select(workspaceId) }
    }

    /// ⚠️ THE ROLE IS OMITTED WHEN IT DID NOT PARSE rather than guessed at. This is
    /// the LIST's membership role, which the overview's effective role may override
    /// upward, so it is a label here and never a gate.
    private static func subtitle(for entry: WorkspaceEntry) -> String {
        let region = WorkspacesCopy.regionLine(RegionCopy.label(entry.region))
        guard let role = WorkspaceRole.fromWire(entry.role) else { return region }
        return WorkspacesCopy.regionAndRole(region, role.displayLabel)
    }
}
