import Observation
import SwiftUI

/// How a screen pushes a route onto the stack it is drawn in, without a `NavigationLink`.
///
/// ⚠️ MAC ONLY. On the iPad every row is a `NavigationLink(value:)`. A Mac `Table` row is
/// not a view a link can wrap: it is chosen, and opened with a double-click or Return
/// (`contextMenu(forSelectionType:primaryAction:)`), so the table needs a way to append to
/// the path itself. ``ShellView`` publishes one per stack, writing to that stack's path.
///
/// ⛔ IT APPENDS, IT NEVER REPLACES. A table opens a row the way a link does, so a back
/// press lands on the table, exactly as on the iPad.
///
/// ⚠️ nil OUTSIDE THE SHELL (a preview, a test host), where a table's rows open nothing.
@MainActor
@Observable
final class ShellNavigator {
    @ObservationIgnored private let append: (Route) -> Void

    init(append: @escaping (Route) -> Void) {
        self.append = append
    }

    func push(_ route: Route) {
        append(route)
    }
}

extension View {
    /// Publish the navigator for the stack whose path is `path`.
    func shellNavigator(_ path: Binding<[Route]>) -> some View {
        environment(ShellNavigator { path.wrappedValue.append($0) })
    }
}
