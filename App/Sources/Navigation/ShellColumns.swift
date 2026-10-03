import SwiftUI

/// The sidebar's one stored choice, shown or hidden, translated to and from what each of the
/// shell's two split views reads (``ShellView``).
///
/// ⛔ THE SAME ``NavigationSplitViewVisibility`` MEANS DIFFERENT COLUMNS IN THE TWO SPLIT
/// VIEWS, which is why the shell stores a `Bool`:
///
/// | value           | two columns          | three columns                  |
/// |-----------------|----------------------|--------------------------------|
/// | `.all`          | sidebar, detail      | sidebar, content, detail       |
/// | `.doubleColumn` | sidebar, detail      | content, detail (no sidebar)   |
/// | `.detailOnly`   | detail               | detail                         |
///
/// ⛔ AND ON macOS `.automatic` IS `.doubleColumn`: it prints as `kind: doubleColumn,
/// isAutomatic: true`, and the type's `==` compares the kind alone, so the two cannot be
/// told apart. Build 20019 reset to `.automatic` on every change of column count, which in
/// three columns hid the sidebar. A first draft of this type that read `.automatic` as
/// "shown" turned hiding the sidebar in a list section into a no-op, because SwiftUI writes
/// `.doubleColumn` there. All of it was measured in a real window (PORTING.md).
///
/// So "shown" is `.all` in both, and "hidden" is the value that drops only the sidebar:
/// `.detailOnly` in two columns and `.doubleColumn` in three. `ShellColumnsTests` pins both
/// directions.
enum ShellColumns {
    static func visibility(sidebarShown: Bool, threeColumns: Bool) -> NavigationSplitViewVisibility {
        guard !sidebarShown else { return .all }
        return threeColumns ? .doubleColumn : .detailOnly
    }

    /// Whether a visibility SwiftUI wrote (the sidebar's divider dragged shut or open) shows
    /// the sidebar, in the split view that wrote it.
    static func sidebarShown(after visibility: NavigationSplitViewVisibility, threeColumns: Bool) -> Bool {
        if visibility == .all {
            return true
        }
        if visibility == .detailOnly {
            return false
        }
        // `.doubleColumn` (and `.automatic`, which is it): sidebar and detail in two columns,
        // content and detail in three.
        return !threeColumns
    }

    /// The menu command's and the toolbar button's words, the system's own.
    static func commandTitle(sidebarShown: Bool) -> String {
        sidebarShown ? "Hide Sidebar" : "Show Sidebar"
    }
}

/// The width of a list section's list column.
///
/// ⛔ A TABLE'S MINIMUM IS ITS COLUMNS' MINIMUMS, PLUS 17pt OF CELL SPACING EACH AND 15pt OF
/// ROW INSET (both read off the real `NSTableView`), with each column's ideal at its
/// minimum. The table does not shrink its columns to fit the frame it is first drawn in:
/// past that sum it scrolls sideways, which hid Duration and Status in Sean's first build
/// (20019). Wider than the sum, the columns share the room. So Calls is 508 + 85 + 15
/// (``CallLogTable``) and Contacts 500 + 68 + 15 (``ContactsTable``), and at the 1000pt
/// window minimum with the sidebar showing it is the open row that gives way, down to
/// ``detailMin``.
///
/// ⚠️ THE INBOX, DESK AND SUPPORT KEEP THE iPad's ROWS, whose badges go under the text when
/// the column is narrow (``DistrictRowLayout``), so they need no table's width.
struct ListColumnWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat

    /// The open row's narrowest: "Select a call" still reads on two lines.
    static let detailMin: CGFloat = 160

    static func of(_ item: SidebarItem) -> ListColumnWidth {
        switch item {
        case .calls: ListColumnWidth(min: 610, ideal: 640)
        case .contacts: ListColumnWidth(min: 590, ideal: 640)
        case .desk, .support: ListColumnWidth(min: 340, ideal: 420)
        default: ListColumnWidth(min: 300, ideal: 400)
        }
    }
}
