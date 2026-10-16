@testable import DistrictMac
import XCTest

/// The 3.0.2 visual walk: a sheet taller than the smallest window, with its Done below the
/// edge, and every sheet on the system's grey rather than the palette, its title and
/// button bars included (walk 2).
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
        let sources = try SheetScan.sources()
        XCTAssertTrue(
            sources["DistrictMacApp.swift", default: ""].contains("minHeight: MacWindowSize.minHeight)"),
            "the window's minimum is MacWindowSize's"
        )

        let literal = try NSRegularExpression(pattern: #"(?:idealHeight|minHeight): (\d+)\b"#)
        var checked = 0
        // Only sheets: a file that presents nothing and is presented as nothing is out of scope.
        for (name, code) in sources where code.contains("Sheet") {
            let range = NSRange(code.startIndex..., in: code)
            for match in literal.matches(in: code, range: range) {
                guard let value = Range(match.range(at: 1), in: code).flatMap({ Double(code[$0]) }) else { continue }
                // Row and button heights (44, 56) are not sheet sizes.
                guard value > 100 else { continue }
                checked += 1
                XCTAssertLessThanOrEqual(
                    CGFloat(value),
                    MacSheetFit.maxHeight,
                    "\(name): a sheet height of \(Int(value))pt runs past the smallest window"
                )
            }
        }
        XCTAssertGreaterThan(checked, 0, "the scan found no sheet frame at all")
    }

    /// ⛔ EVERY `.sheet` CONTENT IS PAINTED WITH THE PALETTE. Its closure, the view type it
    /// presents, or the member it names applies `macSheetSize` or `macSheetBackground()`,
    /// directly or through a view that does (`SchedulingWriteSheet` for the scheduling writes).
    func testEverySheetContentTakesThePaletteBackground() throws {
        let sources = try SheetScan.sources()
        let painted = SheetScan.paintedTypes(sources)
        XCTAssertTrue(painted.contains("SchedulingWriteSheet"), "the scheduling writes' shared sheet")
        var sheets = 0
        for (name, code) in sources {
            for site in SheetScan.sheetSites(in: code) {
                sheets += 1
                let content = String(code[site.content])
                let named = SheetScan.bareMembers(in: content).map { SheetScan.member($0, in: code) }
                let covered = ([content] + named).contains { SheetScan.paints($0, painted: painted) }
                let line = code[..<site.call].filter { $0 == "\n" }.count + 1
                XCTAssertTrue(covered, "\(name):\(line): a sheet without macSheetSize or macSheetBackground()")
            }
        }
        XCTAssertGreaterThan(sheets, 30, "the scan found too few sheets to have read the app")
    }

    /// ⛔ NO SHEET DRAWS THE SYSTEM'S TITLE BAR OR BUTTON BAR (3.0.2 walk 2). The palette
    /// background paints only the content area: a `NavigationStack`'s title and a toolbar's
    /// Cancel and Done sit in bars of the system's grey (#1E1E1E in dark) on Desk settings,
    /// New message and the workspace picker. A sheet's content closure, the members it
    /// names and every app type they draw, to a fixed point, use neither; the title and
    /// the buttons are ``MacSheetChrome``'s. The two placements that exist only to fill a
    /// sheet's bars are refused anywhere in the app.
    func testNoSheetDrawsTheSystemsTitleOrButtonBar() throws {
        let sources = try SheetScan.sources()
        let bodies = SheetScan.structBodies(sources)
        var presented: Set<String> = []
        for (name, code) in sources {
            for site in SheetScan.sheetSites(in: code) {
                let content = String(code[site.content])
                let named = SheetScan.bareMembers(in: content).map { SheetScan.member($0, in: code) }
                let line = code[..<site.call].filter { $0 == "\n" }.count + 1
                for text in [content] + named {
                    let bar = SheetScan.systemBar(in: text)
                    XCTAssertNil(bar, "\(name):\(line): a sheet draws \(bar ?? "") (use MacSheetChrome)")
                    presented.formUnion(SheetScan.calledTypes(text))
                }
            }
        }
        let drawn = SheetScan.reachable(from: presented, bodies: bodies)
        let walked: Set = [
            "ComposeSheet", "DeskComposeSheet", "DeskSettingsView", "MeetingRecordSheet",
            "PersonaPreviewView", "WorkspacePickerSheet", "SchedulingWriteSheet", "MacSheetChrome",
        ]
        XCTAssertTrue(walked.isSubset(of: drawn), "the scan missed \(walked.subtracting(drawn).sorted())")
        for sheetType in drawn.sorted() {
            let bar = SheetScan.systemBar(in: bodies[sheetType] ?? "")
            XCTAssertNil(bar, "\(sheetType) is drawn in a sheet and draws \(bar ?? "") (use MacSheetChrome)")
        }
        for (name, code) in sources {
            let placement = SheetScan.firstMatch(SheetScan.sheetBarPlacement, in: SheetScan.uncommented(code))
            XCTAssertNil(placement, "\(name): \(placement ?? "") fills a system sheet bar")
        }
    }
}

/// A source scan of the app's sheets, for ``MacSheetFitTests``.
private enum SheetScan {
    struct Site {
        /// Where `.sheet(` starts.
        let call: String.Index
        /// The content closure, braces included.
        let content: Range<String.Index>
    }

    static let marks = [".macSheetSize(", ".macSheetBackground()"]

    /// Every `.swift` file under `App/Sources`, by file name.
    static func sources() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path), "sources are not beside this test")
        var found: [String: String] = [:]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            found[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        return found
    }

    /// The balanced `{ ... }` that opens at or after `start`.
    static func closure(in code: String, from start: String.Index) -> Range<String.Index>? {
        guard let open = code[start...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < code.endIndex {
            if code[index] == "{" {
                depth += 1
            } else if code[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return open ..< code.index(after: index)
                }
            }
            index = code.index(after: index)
        }
        return nil
    }

    static func sheetSites(in code: String) -> [Site] {
        var sites: [Site] = []
        var cursor = code.startIndex
        while let call = code.range(of: ".sheet(", range: cursor ..< code.endIndex) {
            guard let content = closure(in: code, from: call.upperBound) else { break }
            sites.append(Site(call: call.lowerBound, content: content))
            cursor = content.upperBound
        }
        return sites
    }

    /// `code` without its `.sheet` presentations, so a screen that PRESENTS a painted sheet
    /// is not counted as a painted sheet itself.
    static func withoutSheets(_ code: String) -> String {
        var kept = ""
        var cursor = code.startIndex
        for site in sheetSites(in: code) {
            kept.append(contentsOf: code[cursor ..< site.call])
            cursor = site.content.upperBound
        }
        kept.append(contentsOf: code[cursor...])
        return kept
    }

    /// The upper-case names called in `text`: `Name(`.
    static func calledTypes(_ text: String) -> Set<String> {
        guard let call = try? NSRegularExpression(pattern: #"\b([A-Z]\w*)\("#) else { return [] }
        let matches = call.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    static func paints(_ text: String, painted: Set<String>) -> Bool {
        marks.contains { text.contains($0) } || !calledTypes(text).isDisjoint(with: painted)
    }

    /// Each top-level `struct` whose own body (its presentations aside) paints a sheet, and
    /// each one that draws such a struct, to a fixed point.
    static func paintedTypes(_ sources: [String: String]) -> Set<String> {
        var calls: [String: Set<String>] = [:]
        var painted: Set<String> = []
        for code in sources.values {
            for (name, body) in structs(in: code) {
                calls[name] = calledTypes(body)
                if marks.contains(where: { body.contains($0) }) {
                    painted.insert(name)
                }
            }
        }
        var grew = true
        while grew {
            let more = calls.filter { name, called in !painted.contains(name) && !called.isDisjoint(with: painted) }
            painted.formUnion(more.keys)
            grew = !more.isEmpty
        }
        return painted
    }

    /// Each top-level `struct` in `code` by name, to its closing brace, presentations removed.
    static func structs(in code: String) -> [(String, String)] {
        guard let header = try? NSRegularExpression(
            pattern: #"^(?:private |fileprivate )?struct (\w+)\b"#,
            options: .anchorsMatchLines
        ) else { return [] }
        return header.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
            guard let start = Range(match.range, in: code), let name = Range(match.range(at: 1), in: code) else {
                return nil
            }
            let rest = start.lowerBound ..< code.endIndex
            let end = code.range(of: "\n}\n", range: rest)?.upperBound ?? code.endIndex
            return (String(code[name]), withoutSheets(String(code[start.lowerBound ..< end])))
        }
    }

    /// Every top-level `struct` by name to its body (presentations removed). Two private
    /// types of one name in different files are read as one, which can only find more.
    static func structBodies(_ sources: [String: String]) -> [String: String] {
        var bodies: [String: String] = [:]
        for code in sources.values {
            for (name, body) in structs(in: code) {
                bodies[name, default: ""] += body
            }
        }
        return bodies
    }

    /// The app types `start` names and every app type those draw, to a fixed point.
    static func reachable(from start: Set<String>, bodies: [String: String]) -> Set<String> {
        var found = start.filter { bodies[$0] != nil }
        var grew = true
        while grew {
            let more = Set(found.flatMap { calledTypes(bodies[$0] ?? "") }.filter { bodies[$0] != nil })
                .subtracting(found)
            found.formUnion(more)
            grew = !more.isEmpty
        }
        return found
    }

    /// A `NavigationStack`, a `.toolbar` or a sheet-bar placement, in code.
    static let systemBarPattern = #"\bNavigationStack\s*[({]|\.toolbar\s*[({]|"#
        + #"placement:\s*\.(?:cancellationAction|confirmationAction)\b"#
    static let sheetBarPlacement = #"placement:\s*\.(?:cancellationAction|confirmationAction)\b"#

    /// What in `text` draws a system bar in a sheet, or nil. Comment lines are not code.
    static func systemBar(in text: String) -> String? {
        firstMatch(systemBarPattern, in: uncommented(text))
    }

    /// `text` without its `//` comment lines, so prose naming a `NavigationStack` is not one.
    static func uncommented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

    /// The lower-case names a content closure is nothing but (`editor`, `addSheet`).
    static func bareMembers(in content: String) -> [String] {
        content.dropFirst().dropLast()
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^[a-z]\w*$"#, options: .regularExpression) != nil }
    }

    /// A type member's declaration, to the end of its body.
    static func member(_ name: String, in code: String) -> String {
        let pattern = #"\n    (?:private )?(?:var|func) "# + name + #"\b"#
        guard let start = code.range(of: pattern, options: .regularExpression) else { return "" }
        let rest = start.upperBound ..< code.endIndex
        let end = code.range(of: "\n    }\n", range: rest)?.upperBound ?? code.endIndex
        return String(code[start.lowerBound ..< end])
    }
}
