@testable import DistrictMac
import XCTest

/// Billing and Phone numbers open nothing outside the app, in both Mac builds, and
/// Scheduling opens only its documented hand-off.
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

    // MARK: - Scheduling

    /// ⛔ SCHEDULING KEEPS IN THE APP WHAT iOS KEEPS IN THE APP, and leaves it only where iOS
    /// does. Every section and every booking is drawn and edited here; the
    /// two ways out are the two iOS takes out of the app into a Safari sheet, which a Mac
    /// can only open in the default browser: the hand-off into our own scheduler
    /// (``SchedulingHubView``'s "Open in browser", S33) and the calendar provider's consent
    /// screen (``SchedulingCalendarConnectSection``, a page the provider owns and refuses
    /// to show in an embedded view). Nothing on the surface is a purchase, and no other
    /// control may hand a URL to the browser.
    ///
    /// ⚠️ THE ALLOWANCES ARE PER FILE AND PER CALL, and each is a thing iOS also does: the
    /// hand-off's two `NSWorkspace.open` calls, the calendar connect's one `BrowserHandOff`,
    /// the booking link's `ShareLink` (a share picker, as iOS's share sheet, and it carries
    /// our own booking page), and two `URL(string:)` parses that open nothing (the SSO
    /// route's `Location`, and the branding form's check that a privacy or terms address
    /// is absolute).
    func test_MAC_BILLING_5_schedulingOpensOnlyTheDocumentedHandOff() throws {
        try assertNothingOpens(
            in: "Scheduling",
            atLeast: 85,
            "scheduling stays in the app except for the documented hand-off",
            allowing: [
                "SchedulingHubView.swift": ["NSWorkspace", "ShareLink", "URL(string"],
                "SchedulingCalendarConnectSection.swift": ["BrowserHandOff"],
                "SchedulingSSOClient.swift": ["URL(string"],
                "SchedulingBrandingModel.swift": ["URL(string"],
            ]
        )
    }

    /// ⛔ THE HAND-OFF IS THE HUB'S AND NOBODY ELSE'S: exactly two opens, leg 1 and the
    /// minted URL, in the one function that runs the bound flow.
    func test_MAC_BILLING_6_theHandOffOpensTwiceFromOnePlace() throws {
        let hub = try String(
            contentsOf: Self.features.appendingPathComponent("Scheduling/SchedulingHubView.swift"),
            encoding: .utf8
        )
        let opens = hub.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && $0.contains("NSWorkspace.shared.open(")
        }
        XCTAssertEqual(opens.count, 2, "leg 1 and the minted URL, nothing else")
    }

    /// ⛔ THE CALENDAR CONNECT OPENS ONCE, FROM ITS CONNECT FUNCTION, and only what the SSO
    /// route answered: a fresh single-use hand-off per press.
    func test_MAC_BILLING_7_theCalendarConnectOpensOnceFromOnePlace() throws {
        let file = Self.features.appendingPathComponent("Scheduling/Writes/SchedulingCalendarConnectSection.swift")
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        let opens = lines.filter { $0.contains("BrowserHandOff.open(") }
        XCTAssertEqual(opens.count, 1)
        XCTAssertTrue(
            opens.first?.contains("BrowserHandOff.open(url)") == true,
            "the minted URL, and nothing built here"
        )
    }

    private static let features = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Features")

    /// - Parameter allowing: per file name, the calls that file may make (see the case that
    ///   passes it). ⚠️ The walk is recursive, so a subfolder (`Scheduling/Writes`) is read too.
    private func assertNothingOpens(
        in feature: String,
        atLeast minimum: Int,
        _ message: String,
        allowing allowed: [String: Set<String>] = [:]
    ) throws {
        let root = Self.features.appendingPathComponent(feature)
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let files = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }

        XCTAssertGreaterThanOrEqual(files.count, minimum, "the walk reached almost nothing")

        var offences: [String] = []
        for file in files {
            let permitted = allowed[file.lastPathComponent] ?? []
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                let call = Self.forbiddenCalls.first { call in
                    !permitted.contains(call) && Self.uses(call, in: line)
                }
                if let call {
                    offences.append("\(file.lastPathComponent):\(index + 1) uses \(call)")
                }
            }
        }
        XCTAssertEqual(offences, [], message)
    }

    /// ⚠️ `Link(` IS A WHOLE WORD: a `NavigationLink(` pushes a screen inside the app and is
    /// how every scheduling row opens.
    private static func uses(_ call: String, in line: String) -> Bool {
        guard call == "Link(" else { return line.contains(call) }
        return line.range(of: #"(?<![A-Za-z])Link\("#, options: .regularExpression) != nil
    }
}
