@testable import DistrictMac
import DistrictModel
import Foundation
import XCTest

/// The business facts the setup wizard reads and writes: services, FAQs, the address and the
/// "what does the business do" answer, each read from the stored facts and written back, and
/// the limits each draft is checked against. The hours are pinned in ``SetupFlowTests``.
@MainActor
final class SetupFactsTests: XCTestCase {
    private let stored: WireJSON = .object([
        "services": .array([
            .object(["name": .string("Cleaning"), "price": .string("$120"), "enabled": .bool(true)]),
            .object(["name": .string("Whitening")]),
        ]),
        "faqs": .array([
            .object([
                "question": .string("What does the business do?"),
                "answer": .string("Family dentistry."),
                "enabled": .bool(true),
            ]),
            .object(["question": .string("Parking?"), "answer": .string("Behind the building.")]),
        ]),
        "address": .object([
            "line1": .string("1 Main St"),
            "city": .string("Laval"),
            "region": .string("QC"),
            "postalCode": .string("H7A 1A1"),
            "country": .string("CA"),
        ]),
    ])

    // MARK: - Reading

    func testServicesAreReadWithAMissingFlagAsOff() {
        XCTAssertEqual(SetupFacts.services(stored), [
            SetupServiceDraft(name: "Cleaning", price: "$120", enabled: true),
            SetupServiceDraft(name: "Whitening", price: "", enabled: false),
        ])
        XCTAssertEqual(SetupFacts.services(nil), [])
    }

    func testFaqsAreReadWithAMissingFlagAsOff() {
        XCTAssertEqual(SetupFacts.faqs(stored), [
            SetupFaqDraft(question: "What does the business do?", answer: "Family dentistry.", enabled: true),
            SetupFaqDraft(question: "Parking?", answer: "Behind the building.", enabled: false),
        ])
        XCTAssertEqual(SetupFacts.faqs(nil), [])
    }

    func testTheAddressIsReadPartByPart() {
        XCTAssertEqual(
            SetupFacts.address(stored),
            SetupAddressDraft(line1: "1 Main St", city: "Laval", region: "QC", postalCode: "H7A 1A1", country: "CA")
        )
        XCTAssertTrue(SetupFacts.address(nil).isEmpty)
    }

    /// The answer to the "what" question, in either language, or nothing.
    func testWhatIsTheAnswerToTheWhatQuestionInEitherLanguage() {
        XCTAssertEqual(SetupFacts.what(stored), "Family dentistry.")
        let row: WireJSON = .object(["question": .string("Que fait l'entreprise?"), "answer": .string("Dentisterie.")])
        let french: WireJSON = .object(["faqs": .array([row])])
        XCTAssertEqual(SetupFacts.what(french), "Dentisterie.")
        XCTAssertEqual(SetupFacts.what(.object(["faqs": .array([])])), "")
        XCTAssertEqual(SetupFacts.what(nil), "")
    }

    // MARK: - Writing

    /// ⚠️ A BLANK PRICE IS LEFT OUT, and no rows is a clear.
    func testServicesAreWrittenTrimmedWithABlankPriceLeftOut() {
        XCTAssertEqual(SetupFacts.json(services: []), .null)
        XCTAssertEqual(
            SetupFacts.json(services: [
                SetupServiceDraft(name: " Cleaning ", price: " $120 ", enabled: true),
                SetupServiceDraft(name: "Whitening", price: "  ", enabled: false),
            ]),
            .array([
                .object(["name": .string("Cleaning"), "price": .string("$120"), "enabled": .bool(true)]),
                .object(["name": .string("Whitening"), "enabled": .bool(false)]),
            ])
        )
    }

    func testFaqsAreWrittenTrimmed() {
        XCTAssertEqual(SetupFacts.json(faqs: []), .null)
        XCTAssertEqual(
            SetupFacts.json(faqs: [SetupFaqDraft(question: " Parking? ", answer: " Behind. ", enabled: true)]),
            .array([
                .object(["question": .string("Parking?"), "answer": .string("Behind."), "enabled": .bool(true)]),
            ])
        )
    }

    func testAWholeAddressIsWrittenWithEveryPart() {
        XCTAssertEqual(
            SetupFacts.json(address: SetupFacts.address(stored)),
            .object([
                "line1": .string("1 Main St"),
                "city": .string("Laval"),
                "region": .string("QC"),
                "postalCode": .string("H7A 1A1"),
                "country": .string("CA"),
            ])
        )
    }

    // MARK: - Limits

    func testAServiceNeedsANameWithinTheLimitsAndAShortPrice() {
        XCTAssertTrue(SetupFacts.isValid(SetupServiceDraft(name: "Cleaning", price: "", enabled: true)))
        XCTAssertFalse(SetupFacts.isValid(SetupServiceDraft(name: "   ", price: "", enabled: true)))
        let longName = String(repeating: "a", count: SetupFacts.Limit.serviceName + 1)
        XCTAssertFalse(SetupFacts.isValid(SetupServiceDraft(name: longName, price: "", enabled: true)))
        let longPrice = String(repeating: "9", count: SetupFacts.Limit.servicePrice + 1)
        XCTAssertFalse(SetupFacts.isValid(SetupServiceDraft(name: "Cleaning", price: longPrice, enabled: true)))
    }

    func testAFaqNeedsAQuestionAndAnAnswerWithinTheLimits() {
        XCTAssertTrue(SetupFacts.isValid(SetupFaqDraft(question: "Parking?", answer: "Behind.", enabled: true)))
        XCTAssertFalse(SetupFacts.isValid(SetupFaqDraft(question: " ", answer: "Behind.", enabled: true)))
        XCTAssertFalse(SetupFacts.isValid(SetupFaqDraft(question: "Parking?", answer: " ", enabled: true)))
        let longQuestion = String(repeating: "q", count: SetupFacts.Limit.faqQuestion + 1)
        XCTAssertFalse(SetupFacts.isValid(SetupFaqDraft(question: longQuestion, answer: "Behind.", enabled: true)))
        let longAnswer = String(repeating: "a", count: SetupFacts.Limit.faqAnswer + 1)
        XCTAssertFalse(SetupFacts.isValid(SetupFaqDraft(question: "Parking?", answer: longAnswer, enabled: true)))
    }

    func testEachAddressPartHasItsLimit() {
        let base = SetupAddressDraft(city: "Laval", country: "CA")
        var line = base
        line.line1 = String(repeating: "l", count: SetupFacts.Limit.addressLine + 1)
        XCTAssertFalse(SetupFacts.isValid(line))
        var city = base
        city.city = String(repeating: "c", count: SetupFacts.Limit.addressPart + 1)
        XCTAssertFalse(SetupFacts.isValid(city))
        var region = base
        region.region = String(repeating: "r", count: SetupFacts.Limit.addressPart + 1)
        XCTAssertFalse(SetupFacts.isValid(region))
        var postal = base
        postal.postalCode = String(repeating: "p", count: SetupFacts.Limit.postalCode + 1)
        XCTAssertFalse(SetupFacts.isValid(postal))
        XCTAssertTrue(SetupFacts.isValid(SetupFacts.address(stored)))
    }

    func testIntervalTextAndMinutes() {
        XCTAssertEqual(SetupInterval.minutes("09:30"), 570)
        XCTAssertEqual(SetupInterval.minutes("24:00"), 1440)
        XCTAssertNil(SetupInterval.minutes("25:00"))
        XCTAssertNil(SetupInterval.minutes("9:30"))
        XCTAssertNil(SetupInterval.minutes(nil))
        XCTAssertEqual(SetupInterval.text(570), "09:30")
        XCTAssertEqual(SetupInterval.standard, SetupInterval(open: 540, close: 1020))
    }

    func testEveryWeekdayHasAName() {
        XCTAssertEqual(Set(SetupWeekday.allCases.map(\.name)).count, 7)
        XCTAssertEqual(SetupWeekday.mon.id, "mon")
    }
}
