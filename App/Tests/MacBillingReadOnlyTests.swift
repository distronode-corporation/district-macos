@testable import DistrictMac
import XCTest

/// Billing stays read-only on the Mac, in both builds.
///
/// ⛔ MAC ONLY, AND A SECOND HOLD BESIDE ``StoreCopyTests``. That gate reads the SENTENCES;
/// this one reads the CONTROLS. iOS keeps every purchase path out of its billing screen
/// (App Store Review Guideline 3.1.3(b)), and a Mac adds ways to leave the app that iOS
/// does not have: `NSWorkspace.open`, ``BrowserHandOff`` and `Link` all hand a URL to the
/// default browser in one line. The Developer ID build compiles the same files under the
/// same bundle id as the store build, so a hand-off added "for the .dmg only" ships to App
/// Review too. Nothing under `Features/Billing` may open anything.
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Billing")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // ⛔ A WALK THAT FOUND NOTHING PROVES NOTHING: the screen is seven files.
        XCTAssertGreaterThanOrEqual(files.count, 7, "the walk reached almost nothing")

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
        XCTAssertEqual(offences, [], "billing is read-only: nothing on it may leave the app")
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
}
