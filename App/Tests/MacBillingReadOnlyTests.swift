@testable import DistrictMac
import XCTest

/// Billing and Phone numbers open nothing outside the app, in both Mac builds.
///
/// ⛔ MAC ONLY, AND A SECOND HOLD BESIDE ``StoreCopyTests``. That gate reads the SENTENCES;
/// this one reads the CONTROLS. iOS keeps every purchase path out of its billing screen
/// (App Store Review Guideline 3.1.3(b)) and out of its phone-number screens (buying a
/// number is a recurring charge for a service used in the app, 3.1.1, so it is absent rather
/// than linked), and a Mac adds ways to leave the app that iOS does not have:
/// `NSWorkspace.open`, ``BrowserHandOff`` and `Link` all hand a URL to the default browser in
/// one line. The Developer ID build compiles the same files under the same bundle id as the
/// store build, so a hand-off added "for the .dmg only" ships to App Review too. Nothing under
/// `Features/Billing` or `Features/Marketplace` may open anything.
///
/// ⚠️ COMMENTS ARE SKIPPED, as in ``StoreCopyTests``: the reasons in those files name the
/// very calls they forbid.
final class MacBillingReadOnlyTests: XCTestCase {
    private static let forbiddenCalls = [
        "openURL",
        "NSWorkspace",
        "BrowserHandOff",
        "Link(",
        "ShareLink",
        "SafariView",
        "URL(string",
    ]

    func test_MAC_BILLING_1_noBillingFileOpensAnything() throws {
        // ⛔ A WALK THAT FOUND NOTHING PROVES NOTHING: the screen is seven files.
        try assertNothingOpens(in: "Billing", atLeast: 7, "billing is read-only: nothing on it may leave the app")
    }

    /// The caption a reviewer reads, per role. Neither names a place.
    func test_MAC_BILLING_2_bothCaptionsStateTheLimitOnly() {
        for caption in [BillingCopy.readOnly, BillingCopy.readOnlyViewer] {
            let lowered = caption.lowercased()
            for word in ["upgrade", "purchase", "buy", "on sale", "website", "browser", "distronode.com"] {
                XCTAssertFalse(lowered.contains(word), "\"\(caption)\" says \(word)")
            }
        }
    }

    /// ⛔ THE WHOLE MARKETPLACE, NOT ONLY ITS READ-ONLY TABS. iOS offers no purchase anywhere
    /// on it and links to none, and the paperwork and release flows it does offer happen in
    /// the app; a Mac hand-off from any tab would be the purchase path iOS left out.
    func test_MAC_BILLING_3_noMarketplaceFileOpensAnything() throws {
        // ⛔ The section is fifteen files.
        try assertNothingOpens(in: "Marketplace", atLeast: 15, "buying a number is absent: nothing may leave the app")
    }

    /// The marketplace's read-only and purchase sentences, per role. None names a place or
    /// offers a purchase.
    func test_MAC_BILLING_4_theMarketplaceCaptionsStateTheLimitOnly() {
        let captions = [MarketplaceCopy.purchaseElsewhere, MarketplaceCopy.readOnly, MarketplaceCopy.readOnlyViewer]
        for caption in captions {
            let lowered = caption.lowercased()
            for word in ["upgrade", "buy", "on sale", "website", "browser", "distronode.com", "dashboard"] {
                XCTAssertFalse(lowered.contains(word), "\"\(caption)\" says \(word)")
            }
        }
    }

    private func assertNothingOpens(in feature: String, atLeast minimum: Int, _ message: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/\(feature)")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        XCTAssertGreaterThanOrEqual(files.count, minimum, "the walk reached almost nothing")

        var offences: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                if let call = Self.forbiddenCalls.first(where: { line.contains($0) }) {
                    offences.append("\(file.lastPathComponent):\(index + 1) uses \(call)")
                }
            }
        }
        XCTAssertEqual(offences, [], message)
    }
}
