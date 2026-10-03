@testable import DistrictMac
import DistrictModel
import XCTest

/// The list/detail split of a list section's stack. (The iPad's tests 09 and 10 hold the
/// split against the phone's compact stacks, which the Mac does not have; the Mac's own
/// stacks are `ShellPathsTests`.)
///
/// ⛔ THE WRITE-BACK TESTS ARE THE POINT OF THIS FILE. A `List` may write its selection
/// back while a column rebuilds; a mapping that answered that write with `[route]` would
/// drop whatever the detail column had pushed, and a dialler or a room is exactly the kind
/// of thing that gets pushed there.
final class ListDetailPathTests: ShellPathsTestCase {
    private var otherCall: Route {
        .callDetail(workspaceId: workspaceId, callId: "call_2")
    }

    private var ticket: Route {
        .deskTicket(workspaceId: workspaceId, role: role, ticketId: "t_1")
    }

    // MARK: - The mapping

    func test_IOS_LISTDETAIL_01_theSelectionIsTheFirstPushAndNothingWhenEmpty() {
        XCTAssertNil(ListDetailPath.selection(in: []))
        XCTAssertEqual(ListDetailPath.selection(in: [call, dialer]), call)
    }

    func test_IOS_LISTDETAIL_02_selectingAnotherRowReplacesTheWholeStack() {
        XCTAssertEqual(ListDetailPath.selecting(otherCall, in: [call, contact, dialer]), [otherCall])
        XCTAssertEqual(ListDetailPath.selecting(call, in: []), [call])
    }

    /// ⛔ WRITING BACK THE ROW THAT IS OPEN KEEPS WHAT IS PUSHED BESIDE IT.
    func test_IOS_LISTDETAIL_03_reselectingTheOpenRowIsANoOp() {
        let path = [call, contact, dialer]
        XCTAssertEqual(ListDetailPath.selecting(call, in: path), path)
    }

    /// ⚠️ AND A nil WRITE IS SwiftUI's, NEVER A PERSON'S, so it leaves the stack alone.
    func test_IOS_LISTDETAIL_04_aNilSelectionLeavesThePathAlone() {
        XCTAssertEqual(ListDetailPath.selecting(nil, in: [call, room]), [call, room])
        XCTAssertEqual(ListDetailPath.selecting(nil, in: []), [])
    }

    func test_IOS_LISTDETAIL_05_theTailRoundTripsUnderTheSelectedRow() {
        let path = [call, contact, room]
        let tail = ListDetailPath.tail(of: path)
        XCTAssertEqual(tail, [contact, room])
        XCTAssertEqual(ListDetailPath.replacingTail(tail, in: path), path)
        XCTAssertEqual(ListDetailPath.replacingTail([dialer], in: path), [call, dialer])
        XCTAssertEqual(ListDetailPath.replacingTail([], in: path), [call])
    }

    /// ⚠️ A TAIL WRITTEN WITH NOTHING SELECTED CANNOT RESURRECT SCREENS.
    func test_IOS_LISTDETAIL_06_aTailWithNoSelectionIsDropped() {
        XCTAssertEqual(ListDetailPath.replacingTail([dialer], in: []), [])
    }

    func test_IOS_LISTDETAIL_07_leavingARowIsANewFirstPushAndNotAPopOrAPush() {
        XCTAssertTrue(ListDetailPath.leftSelection(from: [call], to: [otherCall]))
        XCTAssertTrue(ListDetailPath.leftSelection(from: [call, contact], to: [otherCall]))
        XCTAssertFalse(ListDetailPath.leftSelection(from: [], to: [call]))
        XCTAssertFalse(ListDetailPath.leftSelection(from: [call], to: [call, contact]))
        XCTAssertFalse(ListDetailPath.leftSelection(from: [call, contact], to: [call]))
    }

    func test_IOS_LISTDETAIL_08_exactlyTheFiveListSectionsAreThreeColumns() {
        XCTAssertEqual(
            SidebarItem.allCases.filter(\.isListSection),
            [.inbox, .calls, .contacts, .desk, .support]
        )
    }
}
