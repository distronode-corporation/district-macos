import SwiftUI

extension View {
    /// Where File > New Ticket lands: open District Desk's new-ticket form.
    ///
    /// ⚠️ MAC ONLY. The command selects Desk and sets
    /// ``ShellCommandCenter/newTicketRequested`` in one update, often before the screen has
    /// read anything, so the request WAITS for ``DeskModel/hasSettled`` instead of being
    /// refused by a model that has not loaded yet. Then it is consumed either way, like ⌘N
    /// and ⇧⌘N, and the form opens only through ``DeskModel/startTicket()``, the toolbar
    /// button's own entry: a desk that turned out to be off or unreadable opens nothing.
    func deskTicketCommandTarget(model: DeskModel, composing: Binding<Bool>) -> some View {
        modifier(DeskTicketCommandTarget(model: model, composing: composing))
    }
}

private struct DeskTicketCommandTarget: ViewModifier {
    let model: DeskModel
    @Binding var composing: Bool

    @Environment(ShellCommandCenter.self) private var center: ShellCommandCenter?

    /// The two facts the request waits on, as one value `onChange` can compare.
    private struct Pending: Equatable {
        let requested: Bool
        let settled: Bool
    }

    func body(content: Content) -> some View {
        // ⛔ `initial: true`, FOR THE REASON ``CommandTargets`` GIVES: the selection that
        // builds Desk and the request arrive in one update.
        content.onChange(
            of: Pending(requested: center?.newTicketRequested == true, settled: model.hasSettled),
            initial: true
        ) { _, pending in
            guard pending.requested, pending.settled else { return }
            center?.newTicketRequested = false
            if model.startTicket() {
                composing = true
            }
        }
    }
}
