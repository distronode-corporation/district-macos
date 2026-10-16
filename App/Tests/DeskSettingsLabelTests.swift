import XCTest

/// The 3.0.2 visual walk: a Desk settings card titled with the words its own control draws.
final class DeskSettingsLabelTests: XCTestCase {
    /// ⛔ NO DESK SETTINGS CARD IS TITLED WITH THE WORDS ITS OWN CONTROL DRAWS. The brand
    /// name and the email switch each printed their label twice, as the card's eyebrow and
    /// as the field's or switch's label; the control keeps it, as its accessibility name.
    func testNoDeskSettingsCardRepeatsItsControlsLabel() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .appendingPathComponent("Sources/Features/Desk/DeskSettingsView.swift")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "sources are not beside this test")
        let code = try String(contentsOf: file, encoding: .utf8)
        let lines = code.components(separatedBy: "\n")
        let marker = "SettingsCard(eyebrow: "
        var cards = 0
        for (index, line) in lines.enumerated() {
            guard let range = line.range(of: marker) else { continue }
            cards += 1
            let eyebrow = String(line[range.upperBound...].prefix { $0 != ")" })
            let following = lines[(index + 1) ..< min(index + 6, lines.count)].joined(separator: "\n")
            XCTAssertFalse(following.contains(eyebrow), "\(eyebrow) titles a card and labels its control")
        }
        XCTAssertEqual(cards, 2, "the enabled and logo cards keep their eyebrows")
        // The controls still carry the label, which is what VoiceOver announces.
        XCTAssertTrue(code.contains("label: DeskCopy.brandNameLabel,"))
        XCTAssertTrue(code.contains("Toggle(\n                DeskCopy.notifyLabel,"))
    }
}
