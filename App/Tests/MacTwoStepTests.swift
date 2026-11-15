import AppKit
@testable import DistrictMac
import XCTest

/// The Mac half of the two-step sheet: where a copied secret goes, when the sheet covers it,
/// and when it may close.
@MainActor
final class MacTwoStepTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTwoStepTests-\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
    }

    /// ⛔ A COPIED SECRET IS FOR THIS MAC AND NO CLIPBOARD HISTORY: the concealed and transient
    /// markers ride with it, and nothing an earlier copy left stays beside it.
    func test_MAC_TWOSTEP_01_aCopiedSecretIsMarkedConcealedAndReplacesWhatWasThere() {
        pasteboard.clearContents()
        pasteboard.setString("an older copy", forType: .string)
        pasteboard.setData(Data([1]), forType: .png)

        TwoStepSecret.copySensitive("JBSWY3DPEHPK3PXP", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "JBSWY3DPEHPK3PXP")
        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(TwoStepSecret.concealedType), "\(types)")
        XCTAssertTrue(types.contains(TwoStepSecret.transientType), "\(types)")
        XCTAssertFalse(types.contains(.png), "the older copy's image is gone")
    }

    /// ⛔ IT EXPIRES, AS ON iOS, BUT NEVER TAKES A NEWER COPY WITH IT.
    func test_MAC_TWOSTEP_02_theSecretIsClearedLaterUnlessSomethingElseWasCopied() {
        let written = TwoStepSecret.copySensitive("aaaa-bbbb", to: pasteboard)
        TwoStepSecret.expire(pasteboard, written: written)
        XCTAssertNil(pasteboard.string(forType: .string), "cleared once its time is up")

        let again = TwoStepSecret.copySensitive("cccc-dddd", to: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("something the person copied since", forType: .string)
        TwoStepSecret.expire(pasteboard, written: again)
        XCTAssertEqual(pasteboard.string(forType: .string), "something the person copied since")
        XCTAssertEqual(TwoStepSecret.pasteboardLifetime, .seconds(120))
    }

    /// ⛔ THE SECRET AND THE CODES ARE COVERED WHILE THE APP IS NOT ACTIVE, and only they are.
    func test_MAC_TWOSTEP_03_onlyTheStepsHoldingASecretAreCoveredWhenTheAppIsNotActive() {
        let all: [TwoStepModel.Step] = [
            .loading, .loadFailed, .overview, .reauth(.turnOn), .password(.turnOff, needsCode: true),
            .scan, .recoveryCodes,
        ]
        for step in all {
            XCTAssertFalse(TwoStepView.covers(step, appActive: true), "\(step) while active")
        }
        XCTAssertEqual(all.filter { TwoStepView.covers($0, appActive: false) }, [.scan, .recoveryCodes])
    }

    /// ⛔ NOT PAST THE CODES, NOR MID-REQUEST; anything else closes (Esc included).
    func test_MAC_TWOSTEP_04_theSheetClosesExceptOverTheCodesOrMidRequest() {
        XCTAssertTrue(TwoStepView.canClose(.overview, busy: false))
        XCTAssertTrue(TwoStepView.canClose(.scan, busy: false))
        XCTAssertFalse(TwoStepView.canClose(.recoveryCodes, busy: false))
        XCTAssertFalse(TwoStepView.canClose(.overview, busy: true))
    }
}
