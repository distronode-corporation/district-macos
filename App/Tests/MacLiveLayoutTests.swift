import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The logic behind the layout fixes from Sean's first real use of the Developer ID build
/// (20019): the avatar's fallback, the row's arrangement, the Rooms minutes action and the
/// devices' platform names. The sidebar's visibility is ``ShellColumnsTests``.
@MainActor
final class DistrictAvatarTests: XCTestCase {
    func test_MAC_AVATAR_1_aRealNameGivesUpToTwoInitials() {
        XCTAssertEqual(DistrictAvatar.initials(for: "Maya Okafor"), "MO")
        XCTAssertEqual(DistrictAvatar.initials(for: "jordan tremblay"), "JT")
        XCTAssertEqual(DistrictAvatar.initials(for: "Distronode Corporation Canada"), "DC")
        XCTAssertEqual(DistrictAvatar.initials(for: "reviewer@example.com"), "R")
        XCTAssertEqual(DistrictAvatar.initials(for: "  Anita  "), "A")
    }

    /// ⛔ A NUMBER IS NOT A NAME: it drew "+" in build 20019. Nil means the person glyph.
    func test_MAC_AVATAR_2_aPhoneNumberOrNoNameGivesTheGlyph() {
        XCTAssertNil(DistrictAvatar.initials(for: "+18554462756"))
        XCTAssertNil(DistrictAvatar.initials(for: "+1 416 555 1234"))
        XCTAssertNil(DistrictAvatar.initials(for: ""))
        XCTAssertNil(DistrictAvatar.initials(for: "   "))
        XCTAssertNil(DistrictAvatar.initials(for: "·"))
    }

    /// ⚠️ WORDS THAT DO NOT START WITH A LETTER ARE SKIPPED, not turned into a symbol.
    func test_MAC_AVATAR_3_nonLetterWordsAreSkipped() {
        XCTAssertEqual(DistrictAvatar.initials(for: "+1 John Smith"), "JS")
        XCTAssertEqual(DistrictAvatar.initials(for: "(416) Front desk"), "FD")
    }
}

@MainActor
final class DistrictRowLayoutTests: XCTestCase {
    private func arrangement(
        _ available: CGFloat,
        leading: CGFloat = 36,
        mustFit: CGFloat,
        trailing: CGFloat
    ) -> DistrictRowLayout.Arrangement {
        DistrictRowLayout.arrangement(
            available: available,
            leading: leading,
            mustFit: mustFit,
            trailing: trailing,
            spacing: 12
        )
    }

    /// The iPad's row whenever the title fits: 36 + 12 + 100 + 12 + 80 = 240.
    func test_MAC_ROW_1_besideWhenTheTitleFitsInFull() {
        XCTAssertEqual(arrangement(240, mustFit: 100, trailing: 80), .beside)
        XCTAssertEqual(arrangement(400, mustFit: 100, trailing: 80), .beside)
    }

    /// ⛔ THE BUILD 20019 INBOX ROW: a name beside four badges in a 368pt row truncated to
    /// "P...". One point short is enough to go underneath.
    func test_MAC_ROW_2_underneathWhenTheTitleWouldTruncate() {
        XCTAssertEqual(arrangement(239, mustFit: 100, trailing: 80), .stacked)
        XCTAssertEqual(arrangement(368, mustFit: 110, trailing: 260), .stacked)
    }

    func test_MAC_ROW_3_anEmptyTrailingSlotNeverStacks() {
        XCTAssertEqual(arrangement(50, mustFit: 400, trailing: 0), .beside)
    }

    /// No leading slot means no leading gap either: 100 + 12 + 80 = 192.
    func test_MAC_ROW_4_noLeadingSlotTakesNoGap() {
        XCTAssertEqual(arrangement(192, leading: 0, mustFit: 100, trailing: 80), .beside)
        XCTAssertEqual(arrangement(191, leading: 0, mustFit: 100, trailing: 80), .stacked)
    }
}

@MainActor
final class RoomsMinutesActionTests: XCTestCase {
    private func meeting(status: String, preview: String?) throws -> MeetingSummary {
        var object: [String: Any] = [
            "id": "m1",
            "roomName": "meet_ws_1_standup",
            "title": NSNull(),
            "status": status,
            "startedAt": "2026-10-03T10:00:00.000Z",
            "endedAt": NSNull(),
            "createdAt": "2026-10-03T10:00:00.000Z",
            "durationSec": 0,
            "participantCount": 2,
        ]
        object["summaryPreview"] = preview ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    func test_MAC_ROOMS_MINUTES_1_offeredWhenTheMeetingHasMinutes() throws {
        XCTAssertTrue(try MeetingRow.offersMinutes(meeting(status: "completed", preview: "We agreed the plan.")))
    }

    /// ⛔ BUILD 20019 DREW "Read the minutes" UNDER "No minutes were saved for this meeting."
    func test_MAC_ROOMS_MINUTES_2_hiddenWhenNoMinutesWereSaved() throws {
        XCTAssertFalse(try MeetingRow.offersMinutes(meeting(status: "completed", preview: nil)))
        XCTAssertFalse(try MeetingRow.offersMinutes(meeting(status: "completed", preview: "  \n")))
    }

    /// A meeting still running has no minutes yet, so nothing to read either.
    func test_MAC_ROOMS_MINUTES_3_hiddenWhileTheMeetingRuns() throws {
        XCTAssertFalse(try MeetingRow.offersMinutes(meeting(status: "in-progress", preview: nil)))
    }
}

@MainActor
final class DevicePlatformNameTests: XCTestCase {
    /// ⛔ BUILD 20019 PRINTED "macos", "ios" AND "linux" under each device's name.
    func test_MAC_DEVICES_PLATFORM_1_theKnownPlatformsGetTheirProperNames() {
        XCTAssertEqual(DevicePlatformName.display("macos"), "macOS")
        XCTAssertEqual(DevicePlatformName.display("ios"), "iOS")
        XCTAssertEqual(DevicePlatformName.display("android"), "Android")
        XCTAssertEqual(DevicePlatformName.display("linux"), "Linux")
        XCTAssertEqual(DevicePlatformName.display(" MacOS "), "macOS")
    }

    func test_MAC_DEVICES_PLATFORM_2_anUnknownPlatformIsShownAsSent() {
        // ⚠️ Windows is a known platform since the W4 pass (as on district-ios); an
        // unknown one is still shown as sent.
        XCTAssertEqual(DevicePlatformName.display("windows"), "Windows")
        XCTAssertEqual(DevicePlatformName.display("tizen"), "tizen")
        XCTAssertEqual(DevicePlatformName.display("  web "), "web")
        XCTAssertEqual(DevicePlatformName.display(""), "Unknown platform")
        XCTAssertEqual(DevicePlatformName.display("   "), "Unknown platform")
    }
}

/// The sidebar's one stored choice against the two split views (``ShellColumns``). Every
/// value here was read off a real window (build 20019's sidebar bug).
@MainActor
final class ShellColumnsTests: XCTestCase {
    /// ⛔ SHOWN BY DEFAULT IN EVERY SECTION: build 20019 opened every list section with the
    /// sidebar collapsed.
    func test_MAC_COLUMNS_1_shownIsAllInBothSplitViews() {
        XCTAssertEqual(ShellColumns.visibility(sidebarShown: true, threeColumns: true), .all)
        XCTAssertEqual(ShellColumns.visibility(sidebarShown: true, threeColumns: false), .all)
    }

    func test_MAC_COLUMNS_2_hiddenDropsOnlyTheSidebar() {
        XCTAssertEqual(ShellColumns.visibility(sidebarShown: false, threeColumns: true), .doubleColumn)
        XCTAssertEqual(ShellColumns.visibility(sidebarShown: false, threeColumns: false), .detailOnly)
    }

    /// ⛔ WHAT SwiftUI WRITES WHEN THE SIDEBAR IS DRAGGED SHUT: `.doubleColumn` in three
    /// columns, `.detailOnly` in two. Both are "hidden".
    func test_MAC_COLUMNS_3_aWriteThatHidesTheSidebarReadsAsHidden() {
        XCTAssertFalse(ShellColumns.sidebarShown(after: .doubleColumn, threeColumns: true))
        XCTAssertFalse(ShellColumns.sidebarShown(after: .detailOnly, threeColumns: true))
        XCTAssertFalse(ShellColumns.sidebarShown(after: .detailOnly, threeColumns: false))
    }

    func test_MAC_COLUMNS_4_aWriteThatShowsTheSidebarReadsAsShown() {
        XCTAssertTrue(ShellColumns.sidebarShown(after: .all, threeColumns: true))
        XCTAssertTrue(ShellColumns.sidebarShown(after: .all, threeColumns: false))
        XCTAssertTrue(ShellColumns.sidebarShown(after: .doubleColumn, threeColumns: false))
    }

    /// ⛔ THE TRAP BEHIND THE BUG: `.automatic` IS `.doubleColumn` to the type's `==`, so in
    /// three columns it hides the sidebar. Pinned so nobody "restores" a reset to it.
    func test_MAC_COLUMNS_5_automaticIsDoubleColumnAndHidesTheSidebarInThreeColumns() {
        XCTAssertEqual(NavigationSplitViewVisibility.automatic, .doubleColumn)
        XCTAssertFalse(ShellColumns.sidebarShown(after: .automatic, threeColumns: true))
    }

    /// ⛔ THE CHOICE SURVIVES EVERY CHANGE OF SECTION: hidden in a list section stays hidden
    /// in a whole-column one, and back.
    func test_MAC_COLUMNS_6_theChoiceRoundTripsThroughBothSplitViews() {
        for shown in [true, false] {
            for three in [true, false] {
                let written = ShellColumns.visibility(sidebarShown: shown, threeColumns: three)
                XCTAssertEqual(
                    ShellColumns.sidebarShown(after: written, threeColumns: three),
                    shown,
                    "\(shown) \(three)"
                )
            }
        }
    }

    func test_MAC_COLUMNS_7_theCommandSaysWhatItWillDo() {
        XCTAssertEqual(ShellColumns.commandTitle(sidebarShown: true), "Hide Sidebar")
        XCTAssertEqual(ShellColumns.commandTitle(sidebarShown: false), "Show Sidebar")
    }
}

/// The list column's width against the tables' columns (``ListColumnWidth``).
@MainActor
final class ListColumnWidthTests: XCTestCase {
    private func inBothLanguages(_ body: (String) -> Void) {
        body("en")
        L10nRuntime.withLocale(.frCA) { body("fr") }
    }

    /// ⛔ A TABLE SCROLLS SIDEWAYS BELOW ITS COLUMNS' SUM (+17 per column, +15 inset, read off
    /// the real `NSTableView`), which hid Duration and Status in build 20019, and clipped
    /// « Sans réponse » in 3.0.0.
    func test_MAC_LISTWIDTH_1_theTablesFitTheirColumnsMinimum() {
        inBothLanguages { language in
            let calls = CallLogColumns.current
            let contacts = ContactsColumns.current
            XCTAssertEqual(calls.table, calls.all.reduce(0, +) + 17 * 4 + 15, language)
            XCTAssertGreaterThanOrEqual(ListColumnWidth.of(.calls).min, calls.table, language)
            XCTAssertGreaterThanOrEqual(ListColumnWidth.of(.contacts).min, contacts.table, language)
        }
    }

    /// ⛔ AND THE OPEN ROW KEEPS ITS MINIMUM AT THE 1000pt WINDOW MINIMUM WITH THE SIDEBAR
    /// SHOWING AS IT OPENS, in both languages: it was 160pt, where a call's summary broke
    /// inside words (3.0.1 visual QA).
    func test_MAC_LISTWIDTH_2_everyListSectionFitsTheWindowMinimum() {
        XCTAssertGreaterThanOrEqual(ListColumnWidth.detailMin, 270)
        inBothLanguages { language in
            for item in SidebarItem.allCases where item.isListSection {
                let width = ListColumnWidth.of(item)
                let used = ListColumnWidth.sidebarAtLaunch + 1 + width.min + 1 + ListColumnWidth.detailMin
                XCTAssertLessThanOrEqual(used, ListColumnWidth.windowMin, "\(item) \(language)")
                XCTAssertGreaterThanOrEqual(width.ideal, width.min, "\(item) \(language)")
            }
        }
    }

    /// ⛔ THE STATUS COLUMN HOLDS THE LONGEST BADGE IN EACH LANGUAGE, the transfer outcome
    /// stacked over a status included.
    func test_MAC_LISTWIDTH_3_theStatusColumnHoldsEveryBadge() {
        XCTAssertTrue(CallLogColumns.statusLabels.contains("No answer"))
        XCTAssertTrue(CallLogColumns.statusLabels.contains("Transfer failed"))
        L10nRuntime.withLocale(.frCA) {
            let labels = CallLogColumns.statusLabels
            XCTAssertTrue(labels.contains("Sans réponse"), "\(labels)")
            XCTAssertTrue(labels.contains("Échec du transfert"), "\(labels)")
            XCTAssertTrue(labels.contains("Autre"), "an unlisted status reads as « Autre » in French")
            let status = CallLogColumns.current.status
            for label in labels {
                XCTAssertGreaterThanOrEqual(status, ColumnFit.badge([label]), label)
            }
            XCTAssertGreaterThan(status, 92, "the 3.0.0 width that clipped « Sans réponse »")
        }
    }

    /// ⚠️ THE MEASUREMENT IS THE SYSTEM FONT'S: wider text is wider, a badge adds its padding,
    /// and a header leaves room for the sort arrow.
    func test_MAC_LISTWIDTH_4_theMeasureIsTheSystemFonts() {
        let short = ColumnFit.text(["Busy"])
        let long = ColumnFit.text(["Busy", "Transfer failed"])
        XCTAssertGreaterThan(long, short)
        XCTAssertEqual(ColumnFit.text([]), 0)
        XCTAssertEqual(long, long.rounded(.up), "whole points")
        XCTAssertGreaterThanOrEqual(
            ColumnFit.badge(["Busy"]),
            ColumnFit.text(["Busy"], size: 12, weight: .semibold) + 16
        )
        XCTAssertGreaterThanOrEqual(ColumnFit.header("Status"), ColumnFit.headerArrow)
        XCTAssertEqual(ColumnFit.table([10, 20]), 30 + 34 + 15)
    }

    /// ⚠️ THE NARROW WHEN COLUMN DRAWS THE DAY: each month's, in the language showing.
    func test_MAC_LISTWIDTH_5_theDayStampsAreEachMonths() {
        XCTAssertEqual(CallLogColumns.dayStamps.count, 12)
        XCTAssertTrue(CallLogColumns.dayStamps.allSatisfy { !$0.contains(":") })
        L10nRuntime.withLocale(.frCA) {
            XCTAssertTrue(CallLogColumns.dayStamps.contains { $0.contains("sept.") }, "\(CallLogColumns.dayStamps)")
            XCTAssertEqual(CallLogColumns.durations, ["59\u{00A0}min\u{00A0}59\u{00A0}s"])
        }
        XCTAssertEqual(CallLogColumns.durations, ["59m 59s"])
    }
}

@MainActor
final class WireDateDayTests: XCTestCase {
    func test_MAC_WIREDATE_DAY_1_theDayAloneAndTheRawStringWhenUnparseable() {
        let day = WireDate.displayDay("2026-08-15T14:30:00.000Z")
        XCTAssertFalse(day.contains(":"), day)
        XCTAssertTrue(day.contains("2026"), day)
        XCTAssertEqual(WireDate.displayDay("soon"), "soon")
    }
}
