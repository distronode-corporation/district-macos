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
        XCTAssertEqual(
            all.filter { TwoStepView.covers($0, appActive: false) },
            [.password(.turnOff, needsCode: true), .scan, .recoveryCodes],
            "the password step's code field shows what was typed"
        )
    }

    /// ⛔ NOT PAST THE CODES, NOR MID-REQUEST; anything else closes (Esc included).
    func test_MAC_TWOSTEP_04_theSheetClosesExceptOverTheCodesOrMidRequest() {
        XCTAssertTrue(TwoStepView.canClose(.overview, busy: false))
        XCTAssertTrue(TwoStepView.canClose(.scan, busy: false))
        XCTAssertFalse(TwoStepView.canClose(.recoveryCodes, busy: false))
        XCTAssertFalse(TwoStepView.canClose(.overview, busy: true))
    }

    /// ⛔ THE TIMER CLEARS IT: copied with a short lifetime, it is gone once that has passed.
    func test_MAC_TWOSTEP_05_theCopyIsClearedWhenItsLifetimeEnds() async {
        TwoStepSecret.copySensitive("JBSWY3DPEHPK3PXP", to: pasteboard, lifetime: .milliseconds(30))
        XCTAssertNotNil(pasteboard.string(forType: .string))
        await waitUntil { self.pasteboard.string(forType: .string) == nil }
    }

    /// ⛔ A QUIT INSIDE THE TWO MINUTES TAKES THE COPY WITH IT (Seer and cubic on #112), and still
    /// never a newer one.
    func test_MAC_TWOSTEP_06_aQuitClearsACopyThatHasNotExpired() {
        TwoStepSecret.copySensitive("aaaa-bbbb", to: pasteboard)
        TwoStepSecret.expireOnQuit()
        XCTAssertNil(pasteboard.string(forType: .string))

        TwoStepSecret.copySensitive("cccc-dddd", to: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied since", forType: .string)
        TwoStepSecret.expireOnQuit()
        XCTAssertEqual(pasteboard.string(forType: .string), "copied since")
    }

    /// ⛔ OPEN HANDS OVER AN `otpauth://` LINK AND NOTHING ELSE (cubic on #112).
    func test_MAC_TWOSTEP_07_onlyAnOtpauthLinkIsOpened() {
        XCTAssertNotNil(TwoStepSecret.authenticatorURL("otpauth://totp/Distronode:you?secret=JBSW&issuer=Distronode"))
        XCTAssertNotNil(TwoStepSecret.authenticatorURL("OTPAUTH://totp/x?secret=JBSW"))
        for uri in ["https://example.test/otpauth", "file:///etc/passwd", "districtai://auth", "not a url", ""] {
            XCTAssertNil(TwoStepSecret.authenticatorURL(uri), uri)
        }
    }

    /// ⛔ AN ANSWER THAT LANDS AFTER THE SHEET WENT PUTS NO SECRET BACK (cubic on #112). The sheet
    /// cannot be closed mid-request, but a session that ends takes it away.
    func test_MAC_TWOSTEP_08_noSecretOutlivesASheetThatWentMidRequest() async {
        let transport = HeldTransport(responses: [
            (200, TwoStepFixtures.statusOff),
            (200, TwoStepFixtures.proof),
            (200, TwoStepFixtures.enrolled),
            (200, TwoStepFixtures.confirmed),
        ], holding: 4)
        let model = TwoStepHarness(transport).model
        await TwoStepFixtures.drive(model, toScanWith: "pw")
        model.totp = "123456"
        let confirm = Task { await model.confirm() }
        await waitUntil { transport.requestCount == 4 }
        model.leave()
        transport.release()
        await confirm.value
        XCTAssertEqual(model.recoveryCodes, [], "the codes answered after the sheet went are dropped")
        XCTAssertNil(model.enrollment)

        let enrolling = HeldTransport(responses: [
            (200, TwoStepFixtures.statusOff),
            (200, TwoStepFixtures.proof),
            (200, TwoStepFixtures.enrolled),
        ], holding: 3)
        let second = TwoStepHarness(enrolling).model
        await second.load()
        second.begin(.turnOn)
        second.usePassword()
        second.password = "pw"
        let submit = Task { await second.submitPassword() }
        await waitUntil { enrolling.requestCount == 3 }
        second.leave()
        enrolling.release()
        await submit.value
        XCTAssertNil(second.enrollment, "the secret answered after the sheet went is dropped")
    }

    /// ⛔ THE SECRETS ARE NOT SELECTABLE (cubic on #112): ⌘C would bypass the controlled copy.
    func test_MAC_TWOSTEP_09_theSecretsAreNotSelectable() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Account/TwoStepSecretCards.swift")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "sources are not beside this test")
        let code = try SourceComments.stripped(String(contentsOf: file, encoding: .utf8))
        XCTAssertFalse(code.contains(".textSelection("))
        // ⚠️ SCOPED TO `TwoStepSecretText` (cubic on #112): the QR image is privacy-sensitive too.
        let start = try XCTUnwrap(code.range(of: "struct TwoStepSecretText: View {"))
        let end = try XCTUnwrap(code.range(of: "struct TwoStepParagraph: View {"))
        XCTAssertTrue(code[start.upperBound ..< end.lowerBound].contains(".privacySensitive()"))
    }
}
