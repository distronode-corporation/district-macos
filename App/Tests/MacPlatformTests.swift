import AppKit
@testable import DistrictMac
import XCTest

/// The AppKit stand-ins for what the ported screens did through UIKit.
@MainActor
final class MacPlatformTests: XCTestCase {
    /// ⛔ A COPY REPLACES THE PASTEBOARD, IT DOES NOT ADD TO IT: whatever the last writer
    /// left (here, a URL) is gone, so a paste target cannot pick the stale type.
    func testClipboardCopyReplacesEveryTypeOnThePasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("district-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/old", forType: .URL)

        Clipboard.copy("+1 555 0100", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "+1 555 0100")
        XCTAssertNil(pasteboard.string(forType: .URL))
    }

    func testAPlatformImageIsAnNSImage() {
        let image: PlatformImage = NSImage(size: NSSize(width: 2, height: 2))
        XCTAssertEqual(image.size, NSSize(width: 2, height: 2))
    }
}
