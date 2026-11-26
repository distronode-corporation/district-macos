import DistrictData
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import SwiftUI
import XCTest

/// The Phone numbers section's two sheets: one owned number's actions, and the confirmation
/// every billable or destructive write asks for first, at the sizes `MarketplaceView` presents
/// them (`macSheetSize(width: 460, height: 260)` and `(460, 360)`).
final class MarketplaceSheetScreenTests: ScreenSnapshotCase {
    private static let api = "/api/district/workspace"
    private static let actionsSize = CGSize(width: 460, height: MacSheetFit.height(260))
    private static let confirmSize = CGSize(width: 460, height: MacSheetFit.height(360))

    // MARK: - A number's actions

    func testActions() async throws {
        try await actions("bring-your-own-en", number: 0)
        try await actions("bring-your-own-fr", number: 0, locale: .frCA)
        try await actions("managed", number: 1)
        try await actions("viewer", number: 0, role: .viewer)
        let configured: [FixtureTransport.Rule] = [
            .any("\(Self.api)/numbers/configure", .fixture("mobile/district-number-configure.json")),
        ]
        try await actions("configured", number: 0, rules: configured) { model, number in
            await model.configure(phoneNumber: number.phoneNumber)
        }
        let refused: [FixtureTransport.Rule] = [.any("\(Self.api)/numbers/configure", .status(500))]
        try await actions("configure-failed", number: 0, rules: refused) { model, number in
            await model.configure(phoneNumber: number.phoneNumber)
        }
        let released: [FixtureTransport.Rule] = [
            .any("\(Self.api)/numbers/release", .fixture("mobile/district-number-release-warnings.json")),
        ]
        try await actions("released-with-a-warning", number: 0, rules: released) { model, number in
            await model.release(phoneNumber: number.phoneNumber)
        }
    }

    // MARK: - The confirmation

    func testConfirmRelease() async throws {
        try await confirm("en", confirmation: .release(phoneNumber: "+14165550100"))
        try await confirm("fr", confirmation: .release(phoneNumber: "+14165550100"), locale: .frCA)
    }

    func testConfirmRegistration() async throws {
        try await confirm("en", confirmation: .submitRegistration(bundleId: "BU_draft", country: "DE"))
    }

    func testConfirmA2P() async throws {
        try await confirm("en", confirmation: .a2p)
        // The submission, answered with the recorded registration, which closes the sheet and
        // leaves its notice on the carrier tab.
        let submitted: [FixtureTransport.Rule] = [
            .any("\(Self.api)/a2p", .fixture("mobile/district-a2p-registration.json")),
        ]
        try await assertView(
            "submitted",
            rules: submitted + MarketplaceTabScreenTests.carrier + ScreenRules.loaded,
            size: MarketplaceTabScreenTests.size
        ) { app in
            try await MarketplaceTabScreenTests.carrierTab(app) { model in
                model.a2pDraft = Self.a2p
                await model.submitA2P()
            }
        }
    }

    func testConfirmTollFree() async throws {
        try await confirm("en", confirmation: .tfv(phoneNumber: "+18005550122"))
        let submitted: [FixtureTransport.Rule] = [
            .any("\(Self.api)/tfv", .fixture("mobile/district-tfv-submission.json")),
        ]
        try await assertView(
            "submitted",
            rules: submitted + MarketplaceTabScreenTests.carrier + ScreenRules.loaded,
            size: MarketplaceTabScreenTests.size
        ) { app in
            try await MarketplaceTabScreenTests.carrierTab(app) { model in
                model.tfvDraft = Self.tollFree
                await model.submitTollFree()
            }
        }
        try await assertView(
            "failed",
            rules: [.any("\(Self.api)/tfv", .status(500))] + MarketplaceTabScreenTests.carrier + ScreenRules.loaded,
            size: MarketplaceTabScreenTests.size
        ) { app in
            try await MarketplaceTabScreenTests.carrierTab(app) { model in
                model.tfvDraft = Self.tollFree
                await model.submitTollFree()
            }
        }
    }

    func testConfirmLookup() async throws {
        try await confirm("en", confirmation: .lookup(phoneNumber: "+14165550142"))
    }

    // MARK: - Drawing

    /// One row of the recorded `provider/numbers` in ``NumberActionsSheet``, after `then`.
    private func actions(
        _ name: String,
        number index: Int,
        locale: L10nLocale = .en,
        role: WorkspaceRole = .agency,
        rules: [FixtureTransport.Rule] = [],
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        then: @escaping (NumberProvisioningModel, ListedNumber) async -> Void = { _, _ in }
    ) async throws {
        try await assertView(
            name,
            rules: rules + ScreenRules.loaded,
            locale: locale,
            size: Self.actionsSize,
            file: file,
            testName: testName,
            line: line
        ) { app in
            let numbers = try await app.container.numbers.owned(workspaceId: app.workspaceId).get().numbers
            let number = try XCTUnwrap(numbers.indices.contains(index) ? numbers[index] : nil)
            let model = MarketplaceTabScreenTests.provisioning(app, role: role)
            await then(model, number)
            return AnyView(NumberActionsSheet(model: model, number: number))
        }
    }

    /// ``NumberConfirmationHost`` asking for `confirmation`, with the form behind it filled so
    /// the request is one the model would arm.
    private func confirm(
        _ name: String,
        confirmation: NumberConfirmation,
        locale: L10nLocale = .en,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) async throws {
        try await assertView(
            name,
            rules: ScreenRules.loaded,
            locale: locale,
            size: Self.confirmSize,
            file: file,
            testName: testName,
            line: line
        ) { app in
            let model = MarketplaceTabScreenTests.provisioning(app)
            model.a2pDraft = Self.a2p
            model.tfvDraft = Self.tollFree
            model.lookupNumber = "+14165550142"
            model.requestConfirmation(confirmation)
            XCTAssertNotNil(model.confirmation, file: file, line: line)
            return AnyView(NumberConfirmationHost(model: model))
        }
    }

    private static var a2p: A2PDraft {
        var draft = A2PDraft()
        draft.businessName = "Contract Test Ltd"
        draft.campaignDescription = "Appointment reminders for booked customers."
        draft.sampleOne = "Your appointment is tomorrow at 10:00. Reply STOP to opt out."
        draft.sampleTwo = "We moved your call to 14:00. Reply STOP to opt out."
        return draft
    }

    private static var tollFree: TollFreeDraft {
        var draft = TollFreeDraft()
        draft.phoneNumber = "+18005550122"
        draft.businessName = "Contract Test Ltd"
        draft.optInImageUrl = "https://www.contract.test/opt-in.png"
        draft.messageContent = "Appointment reminders."
        return draft
    }
}
