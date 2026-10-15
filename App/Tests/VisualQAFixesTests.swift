import DistrictL10n
@testable import DistrictMac
import XCTest

/// The logic behind the second round of the 3.0.1 visual QA (AP-004, AP-008, AP-018).
@MainActor
final class VisualQAFixesTests: XCTestCase {
    private let stages = ["Total Dials", "Connected Calls", "Successful Leads"]

    // MARK: - AP-004, the conversion funnel

    /// ⛔ EVERY BAR'S Y IS IN THE DOMAIN, IN THE SERVER'S ORDER, in both languages. The domain
    /// was the wire names: French bars matched none of it and the funnel drew nothing.
    func test_VQA_FUNNEL_1_everyBarIsInTheDomainInBothLanguages() {
        for french in [false, true] {
            let check = {
                let domain = AnalyticsFunnelCard.domain(self.stages)
                XCTAssertEqual(domain, self.stages.map(AnalyticsFunnelCard.label))
                for stage in self.stages {
                    XCTAssertTrue(domain.contains(AnalyticsFunnelCard.label(stage)), stage)
                }
            }
            if french {
                L10nRuntime.withLocale(.frCA, check)
            } else {
                check()
            }
        }
    }

    /// ⚠️ THE FRENCH AXIS IS FRENCH, never the wire's English.
    func test_VQA_FUNNEL_2_theFrenchAxisIsFrench() {
        L10nRuntime.withLocale(.frCA) {
            let domain = AnalyticsFunnelCard.domain(stages)
            XCTAssertEqual(domain, ["Appels composés au total", "Appels connectés", "Clients potentiels obtenus"])
            XCTAssertFalse(domain.contains("Total Dials"))
        }
    }

    /// ⚠️ TWO STAGES WITH ONE LABEL (two unlisted names reading « Autre ») ARE ONE CATEGORY,
    /// so the domain does not repeat it.
    func test_VQA_FUNNEL_3_aRepeatedLabelIsOneCategory() {
        L10nRuntime.withLocale(.frCA) {
            let domain = AnalyticsFunnelCard.domain(["Mystery one", "Mystery two", "Total Dials"])
            XCTAssertEqual(domain.count, Set(domain).count)
            XCTAssertEqual(domain.last, "Appels composés au total")
        }
    }

    // MARK: - AP-008, the bookings table

    /// ⛔ THE BOOKINGS TABLE FITS THE SCHEDULING PANE AT THE WINDOW MINIMUM, in both languages,
    /// and its Status column holds every status badge.
    func test_VQA_BOOKINGS_1_theTableFitsThePane() {
        let pane = ListColumnWidth.windowMin - ListColumnWidth.sidebarAtLaunch - 2 * DistrictSpacing.gutter
        for french in [false, true] {
            let check = {
                let columns = SchedulingBookingsColumns.current
                XCTAssertLessThanOrEqual(columns.table, pane, "french \(french)")
                XCTAssertEqual(SchedulingBookingsColumns.stamps.count, 12)
                for label in SchedulingBookingsColumns.statusLabels {
                    XCTAssertGreaterThanOrEqual(columns.status, ColumnFit.badge([label]), label)
                }
            }
            if french {
                L10nRuntime.withLocale(.frCA, check)
            } else {
                check()
            }
        }
    }

    // MARK: - AP-018, the ring panel

    /// ⛔ DECLINE ON THE LEFT, ANSWER ON THE RIGHT, and nothing else on the ringing panel.
    func test_VQA_RING_1_declineLeftAnswerRight() {
        XCTAssertEqual(IncomingRingAction.order, [.decline, .answer])
    }

    /// ⛔ THE CALLER AND THE WORKSPACE ARE TWO LINES, never joined by a dot.
    func test_VQA_RING_2_theWorkspaceHasItsOwnLine() {
        let both = IncomingRingLines(caller: "Martine Gagnon", workspaceName: "Plomberie Desrosiers-Lanthier inc.")
        XCTAssertEqual(both.lead, "Martine Gagnon")
        XCTAssertEqual(both.workspace, "Plomberie Desrosiers-Lanthier inc.")
        XCTAssertFalse(both.lead.contains("\u{00B7}"))
    }

    /// ⚠️ NO CALLER YET READS "Incoming call", AND A BLANK NAME IS NO LINE, in both languages.
    func test_VQA_RING_3_blanksAreAbsent() {
        let unknown = IncomingRingLines(caller: "  ", workspaceName: " ")
        XCTAssertEqual(unknown.lead, "Incoming call")
        XCTAssertNil(unknown.workspace)
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(IncomingRingLines(caller: nil, workspaceName: nil).lead, "Appel entrant")
        }
    }
}
