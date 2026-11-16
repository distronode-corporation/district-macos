import DistrictData
@testable import DistrictMac
import XCTest

/// The Mac half of the setup wizard: its bottom row, where the pages it hands to the web open,
/// and the words a pointer reads rather than a finger.
final class MacSetupWizardTests: XCTestCase {
    /// ⛔ EVERY BUTTON IN THE SHEET'S BOTTOM ROW HAS THE PALETTE'S LARGE TREATMENT (visual QA,
    /// #111 and #112): Done, Back, Skip and Finish later, and no ghost Skip as on iOS.
    func test_MAC_SETUP_01_theButtonRowIsOneHeightAndTreatment() throws {
        try FooterButtons.assertStyled(
            "SetupWizardView.swift",
            in: "Setup",
            until: "struct SetupProgressHeader",
            expected: 4
        )
    }

    /// ⛔ A PAGE THE WIZARD HANDS TO THE WEB OPENS IN THE NAMED BROWSER, NEVER THROUGH `openURL`:
    /// every one is under a path this app claims (``SetupFlowTests``), so the system could route
    /// it straight back here. And the wizard reads its state again when the app is active again.
    func test_MAC_SETUP_02_aHandOffOpensTheNamedBrowserAndIsReadAgainOnReturn() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Setup")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path), "sources are not beside this test")
        var opens = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".swift") {
            let code = try SourceComments.stripped(
                String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            )
            XCTAssertFalse(code.contains("openURL"), "\(name): openURL")
            XCTAssertFalse(code.contains("NSWorkspace.shared.open"), "\(name): Launch Services' own choice")
            opens += code.components(separatedBy: "BrowserHandOff.open(").count - 1
        }
        XCTAssertEqual(opens, 1, "one place opens a page: the wizard's hand-off")
        let wizard = try SourceComments.stripped(
            String(contentsOf: folder.appendingPathComponent("SetupWizardView.swift"), encoding: .utf8)
        )
        XCTAssertTrue(wizard.contains("NSApplication.didBecomeActiveNotification"))
        XCTAssertTrue(wizard.contains("await model.refreshAfterHandOff()"))
    }

    /// ⛔ A MAC IS CLICKED, NOT TAPPED OR TOUCHED: the three iOS sentences that named a tap (the
    /// test call's consent heading among them) and the one that closed a sheet say what a Mac does.
    func test_MAC_SETUP_03_noSetupSentenceAsksForATap() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("l10n/macos.toml")
        let entries = try CatalogScan.entries(of: catalog).filter { $0.key.hasPrefix("setup.") }
        XCTAssertGreaterThan(entries.count, 200, "the scan found the wizard's strings")
        for entry in entries {
            for english in entry.english {
                XCTAssertNil(english.range(of: #"\btap"#, options: [.regularExpression, .caseInsensitive]), entry.key)
            }
            for french in entry.french {
                XCTAssertNil(french.range(of: #"\btouch"#, options: [.regularExpression, .caseInsensitive]), entry.key)
            }
        }
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        XCTAssertEqual(byKey["setup.golive_consent_heading"]?.english, ["By clicking the button you agree to this"])
        XCTAssertEqual(byKey["setup.golive_consent_heading"]?.french, ["En cliquant sur le bouton, vous acceptez ceci"])
        XCTAssertEqual(
            byKey["setup.number_none_body"]?.english.first?.hasSuffix("then come back here to carry on."),
            true
        )
    }

    // MARK: - Buying a number: the US storefront only

    /// ⛔ ONLY THE US STOREFRONT IS OFFERED THE SETUP PAGE (Guideline 3.1.3(f), Sean 2026-11-15).
    /// `Storefront.countryCode` is alpha-3, so `US` is not the US storefront.
    func test_MAC_SETUP_04_onlyTheUSStorefrontIsOfferedThePage() {
        XCTAssertTrue(SetupPurchase.isOffered(storefront: "USA"))
        for other in ["CAN", "FRA", "GBR", "US", "usa", ""] {
            XCTAssertFalse(SetupPurchase.isOffered(storefront: other), other)
        }
        XCTAssertFalse(SetupPurchase.isOffered(storefront: nil), "no storefront: not US")
    }

    /// The wizard reads the storefront when it opens: the US offers the page, anywhere else and
    /// no storefront at all (the default, as in a Developer ID build) do not.
    @MainActor
    func test_MAC_SETUP_05_theWizardOffersThePageOnTheUSStorefrontOnly() async {
        for (storefront, offered) in [("USA", true), ("CAN", false), (nil, false)] as [(String?, Bool)] {
            let transport = SetupTransport([:])
            transport.add(SetupFixture.setupRoute, SetupFixture.setup(numbersHeld: 0))
            let model = SetupWizardModel(
                repository: SetupWizardRepository(client: transport.client),
                workspaceId: "ws_1",
                workspaceName: "Northside Dental",
                store: SetupDraftStore(defaults: SetupDefaults.fresh()),
                storefront: { storefront }
            )
            XCTAssertFalse(model.offersPurchase, "nothing is offered before the read")
            await model.load()
            XCTAssertEqual(model.offersPurchase, offered, storefront ?? "no storefront")
        }
        let defaulted = SetupWizardModel.test(SetupTransport([SetupFixture.setupRoute: [(200, SetupFixture.setup())]]))
        await defaulted.load()
        XCTAssertFalse(defaulted.offersPurchase, "a wizard told of no storefront offers nothing")
    }

    /// ⛔ THE DEVELOPER ID BUILD READS NO STOREFRONT, and the step's link is drawn only when the
    /// page is offered, where the other sentence names no destination at all.
    func test_MAC_SETUP_06_theDirectBuildHasNoStorefrontAndTheLinkIsGated() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Setup")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path), "sources are not beside this test")
        let purchase = try SourceComments.stripped(
            String(contentsOf: folder.appendingPathComponent("SetupPurchase.swift"), encoding: .utf8)
        )
        let direct = try XCTUnwrap(purchase.range(of: "#if DEVELOPER_ID"))
        let other = try XCTUnwrap(purchase.range(of: "#else", range: direct.upperBound ..< purchase.endIndex))
        XCTAssertEqual(
            purchase[direct.upperBound ..< other.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines),
            "return nil"
        )
        let step = try SourceComments.stripped(
            String(contentsOf: folder.appendingPathComponent("SetupNumberStep.swift"), encoding: .utf8)
        )
        XCTAssertNotNil(
            step.range(of: #"if wizard\.offersPurchase \{\s*SetupHandOffButton\("#, options: .regularExpression),
            "the setup page's button is inside the storefront gate"
        )
        XCTAssertEqual(step.components(separatedBy: "SetupHandOffButton(").count - 1, 1, "and nowhere else")
        XCTAssertNotEqual(SetupCopy.numberNoneBodyNoPurchase, SetupCopy.numberNoneBody)
    }
}
