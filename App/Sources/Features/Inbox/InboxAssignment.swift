import DistrictModel
import SwiftUI

/// The Inbox's thread assignment controls (DistrictCore 8.2.0): the Assigned to me filter
/// and Assign… in the toolbar, Assign… in a row's context menu, and the assign sheet.
///
/// ⚠️ THE MAC'S TWO WAYS IN, WHERE district-ios HAS A SWIPE. A Mac list has no swipe
/// actions an operator would find, so the toolbar's Assign… acts on the open conversation
/// (the list's selection) and a secondary click on any row offers the same item for that
/// row. Both open one sheet, through ``InboxModel/beginAssigning(_:)``.
///
/// ⚠️ A FILE OF ITS OWN BECAUSE `InboxView.swift` SITS AT THE 500-LINE `file_length`
/// CEILING `swiftlint --strict` ENFORCES. The screen attaches this with one modifier and
/// each row with another.
private struct InboxAssignmentLayer: ViewModifier {
    @Bindable var model: InboxModel
    let selection: Binding<Route?>?
    let path: Binding<[Route]>

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    filterMenu
                }
                if model.canReply {
                    ToolbarItem {
                        assignButton
                    }
                }
            }
            // ⚠️ THE FILTER CLOSES A CONVERSATION IT HIDES. Beside the list, the open thread
            // would stay in the detail with no row selected, and the toolbar's Assign… would
            // act on a conversation the list no longer shows. ⛔ THROUGH THE PATH, NOT THE
            // SELECTION: ``ListDetailPath`` ignores a nil selection on purpose, so the
            // stored stack (the open row and anything pushed beside it) is what is emptied.
            .onChange(of: model.assignedToMeOnly) { closeIfHidden() }
            // ⛔ AND SO DOES THIS SHEET'S OWN ASSIGNMENT (Seer, #95), once the re-read says the row
            // has left Assigned to me. ⛔ NOT A REFRESH (xhigh review): a push re-read closed the
            // thread the operator was typing in (``InboxModel/hidesOpenConversation(_:assignedToMeOnly:)``).
            .sheet(item: $model.assigning) { assign in
                ThreadAssignSheet(model: assign) {
                    Task {
                        await model.load(refreshing: true)
                        closeIfHidden()
                    }
                }
            }
    }

    /// ⚠️ THE ICON FILLS WHILE THE FILTER IS ON, so a narrowed list is never mistaken
    /// for an Inbox with nothing else in it.
    private var filterMenu: some View {
        Menu {
            Picker(InboxCopy.filter, selection: $model.assignedToMeOnly) {
                Text(InboxCopy.allConversations).tag(false)
                Text(InboxCopy.assignedToMe).tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                InboxCopy.filter,
                systemImage: model.assignedToMeOnly
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help(model.assignedToMeOnly ? InboxCopy.assignedToMe : InboxCopy.filter)
        .accessibilityValue(model.assignedToMeOnly ? InboxCopy.assignedToMe : InboxCopy.allConversations)
        .accessibilityIdentifier(A11yID.Inbox.filter)
    }

    private func closeIfHidden() {
        guard selection != nil else { return }
        guard InboxModel.hidesOpenConversation(selectedConversation, assignedToMeOnly: model.assignedToMeOnly) else {
            return
        }
        path.wrappedValue = []
    }

    /// ⚠️ DISABLED, NOT HIDDEN, WITH NO CONVERSATION OPEN: the control is the role's to
    /// use, and only the target is missing. A role that cannot write gets none at all.
    /// ⛔ NOR ONE THE FILTER HIDES (``InboxModel/assignTarget(_:assignedToMeOnly:)``).
    private var assignButton: some View {
        let open = InboxModel.assignTarget(selectedConversation, assignedToMeOnly: model.assignedToMeOnly)
        return Button(InboxCopy.assignMenu, systemImage: "person.crop.circle.badge.plus") {
            if let open {
                model.beginAssigning(open)
            }
        }
        .help(InboxCopy.assignMenu)
        .disabled(open == nil)
        .accessibilityIdentifier(A11yID.Inbox.assign)
    }

    /// The loaded row of the open conversation, or nil with none open (or none in the list).
    private var selectedConversation: ConversationSummary? {
        guard case let .thread(_, _, threadKey, _, _) = selection?.wrappedValue else { return nil }
        return model.conversation(forThreadKey: threadKey)
    }
}

/// A row's context menu: the copy the row always offered, then Assign… for a role that
/// may write.
///
/// ⚠️ ASSIGN… IS THE ONE ROW-MENU ITEM THAT IS NOT A COPY. ``RowContextAction``'s rule (a
/// row menu offers only what the row's data allows without a new request) holds for the
/// copies; this item opens the same sheet as the toolbar's Assign…, the row's own
/// version of the swipe action district-ios draws.
private struct InboxRowMenu: ViewModifier {
    let conversation: ConversationSummary
    let model: InboxModel

    func body(content: Content) -> some View {
        let copies = RowContextActions.thread(counterpart: conversation.counterpart)
        if model.canReply {
            content.contextMenu {
                RowContextCopyItems(actions: copies)
                if !copies.isEmpty {
                    Divider()
                }
                Button(InboxCopy.assignMenu, systemImage: "person.crop.circle.badge.plus") {
                    model.beginAssigning(conversation)
                }
            }
        } else {
            content.rowContextMenu(copies)
        }
    }
}

extension ThreadAssignModel: Identifiable {
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}

extension View {
    /// The filter menu, Assign… and the assign sheet, on the Inbox screen.
    func inboxAssignment(_ model: InboxModel, selection: Binding<Route?>?, path: Binding<[Route]>) -> some View {
        modifier(InboxAssignmentLayer(model: model, selection: selection, path: path))
    }

    /// One Inbox row's context menu: its copy items and Assign….
    func inboxRowMenu(_ conversation: ConversationSummary, model: InboxModel) -> some View {
        modifier(InboxRowMenu(conversation: conversation, model: model))
    }
}

/// The Inbox's empty state, which says which of the two lists is empty.
struct InboxEmptyState: View {
    let assignedToMeOnly: Bool

    var body: some View {
        if assignedToMeOnly {
            EmptyStateView(
                systemImage: "person.crop.circle",
                title: InboxCopy.nothingAssignedTitle,
                message: InboxCopy.nothingAssignedMessage
            )
        } else {
            EmptyStateView(
                systemImage: "tray",
                title: InboxCopy.noConversationsYet,
                message: InboxCopy.textsEmailsCustomersWill
            )
        }
    }
}
