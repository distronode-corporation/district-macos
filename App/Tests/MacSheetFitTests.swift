@testable import DistrictMac
import XCTest

/// The 3.0.2 visual walk: a sheet taller than the smallest window, with its Done below the edge.
final class MacSheetFitTests: XCTestCase {
    /// ⛔ A CAPPED SHEET AND ITS BAR FIT INSIDE THE SMALLEST WINDOW. Measured on build 20065:
    /// the Desk settings sheet, framed at 600pt, drew 661pt tall (61pt of bar) in a window
    /// with 560pt of content.
    func testACappedSheetAndItsBarFitTheSmallestWindow() {
        XCTAssertGreaterThanOrEqual(MacSheetFit.toolbarBar, 61, "the measured bar")
        XCTAssertLessThanOrEqual(MacSheetFit.maxHeight + MacSheetFit.toolbarBar, MacWindowSize.minHeight)
        XCTAssertLessThanOrEqual(MacSheetFit.height(600) + 61, MacWindowSize.minHeight, "the Desk settings sheet")
        XCTAssertLessThanOrEqual(MacSheetFit.height(620) + 61, MacWindowSize.minHeight, "the carrier account sheet")
    }

    /// A sheet that already fits keeps the height it asked for.
    func testASheetThatFitsKeepsItsHeight() {
        XCTAssertEqual(MacSheetFit.height(320), 320)
        XCTAssertEqual(MacSheetFit.height(MacSheetFit.maxHeight), MacSheetFit.maxHeight)
    }

    /// ⛔ NO SHEET STATES ITS OWN HEIGHT PAST THE CAP, AND THE WINDOW'S MINIMUM IS THE ONE
    /// CONSTANT. A sheet sized with a raw `.frame` (not ``View/macSheetSize(width:height:)``)
    /// is not capped by it, so its literal `idealHeight` and `minHeight` are checked here.
    func testNoSheetFrameLiteralRunsPastTheCap() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path), "sources are not beside this test")
        let app = try String(contentsOf: sources.appendingPathComponent("DistrictMacApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("minHeight: MacWindowSize.minHeight)"), "the window's minimum is MacWindowSize's")

        let literal = try NSRegularExpression(pattern: #"(?:idealHeight|minHeight): (\d+)\b"#)
        var checked = 0
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let code = try String(contentsOf: file, encoding: .utf8)
            // Only sheets: a file that presents nothing and is presented as nothing is out of scope.
            guard code.contains("Sheet") else { continue }
            let range = NSRange(code.startIndex..., in: code)
            for match in literal.matches(in: code, range: range) {
                guard let value = Range(match.range(at: 1), in: code).flatMap({ Double(code[$0]) }) else { continue }
                // Row and button heights (44, 56) are not sheet sizes.
                guard value > 100 else { continue }
                checked += 1
                XCTAssertLessThanOrEqual(
                    CGFloat(value),
                    MacSheetFit.maxHeight,
                    "\(file.lastPathComponent): a sheet height of \(Int(value))pt runs past the smallest window"
                )
            }
        }
        XCTAssertGreaterThan(checked, 0, "the scan found no sheet frame at all")
    }
}
