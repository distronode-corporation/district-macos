import DistrictData
import DistrictL10n
@testable import DistrictMac
import DistrictModel
import DistrictNetwork
import SwiftUI
import XCTest

/// The Phone numbers section's four tabs, each drawn as `MarketplaceView` lays its content out,
/// from the service's recorded answers: owned numbers (with a provider that did not answer),
/// the search form and its results, registrations and the carrier tab.
///
/// ⚠️ THE TABS ARE DRAWN ON THEIR OWN, NOT THROUGH `MarketplaceView`. The view keeps its tab in
/// a model it owns, so the shell can only ever open it on My numbers (``SectionScreenTests``
/// draws that); each other tab is its own view over a ``NumberProvisioningModel`` this test
/// builds and reads, the reads the view runs when the tab is chosen.
final class MarketplaceTabScreenTests: ScreenSnapshotCase {
    private static let api = "/api/district/workspace"

    // MARK: - My numbers and Search

    /// The recorded answer with one provider that did not answer, and its banner.
    func testOwnedPartial() async throws {
        let rules: [FixtureTransport.Rule] = [
            .get("\(Self.api)/provider/numbers", .fixture("mobile/district-provider-numbers-partial.json")),
        ]
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("partial", locale),
                rules: rules + ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let response = try await Self.unwrap(app.container.numbers.owned(workspaceId: app.workspaceId))
                return Self.tab {
                    OwnedNumbersList(
                        numbers: response.numbers,
                        partial: response.partial ?? false,
                        failedProviders: response.failedProviderNames,
                        onSelect: { _ in }
                    )
                }
            }
        }
    }

    func testSearch() async throws {
        let rules: [FixtureTransport.Rule] = [
            .any("\(Self.api)/numbers/search", .fixture("mobile/district-numbers-search.json")),
        ]
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("results", locale),
                rules: rules + ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let response = try await Self.unwrap(app.container.numbers.search(
                    workspaceId: app.workspaceId,
                    areaCode: "416"
                ))
                return Self.search(areaCode: "416", type: "local") {
                    SearchResultsList(provider: response.provider, numbers: response.numbers)
                }
            }
        }
        let none: [FixtureTransport.Rule] = [
            .any("\(Self.api)/numbers/search", .emptied("mobile/district-numbers-search.json")),
        ]
        try await assertView("no-results", rules: none + ScreenRules.loaded, size: Self.size) { app in
            let response = try await Self.unwrap(app.container.numbers.search(
                workspaceId: app.workspaceId,
                type: "tollFree"
            ))
            return Self.search(areaCode: "", type: "tollFree") {
                SearchResultsList(provider: response.provider, numbers: response.numbers)
            }
        }
        let failing: [FixtureTransport.Rule] = [.any("\(Self.api)/numbers/search", .status(500))]
        try await assertView("failed", rules: failing + ScreenRules.loaded, size: Self.size) { app in
            let outcome = await app.container.numbers.search(workspaceId: app.workspaceId, areaCode: "416")
            guard case let .failure(error) = outcome else {
                XCTFail("the search answered a 500 and did not fail")
                return AnyView(EmptyView())
            }
            return Self.search(areaCode: "416", type: "local") {
                MarketplaceFailureCard(
                    title: MarketplaceCopy.searchFailed,
                    failure: FailureText.from(error),
                    onRetry: {}
                )
            }
        }
    }

    // MARK: - Registrations

    func testRegistrations() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("loaded", locale),
                rules: Self.registrations + ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                let model = Self.provisioning(app)
                await model.loadRegistrations()
                return Self.tab { RegistrationsSection(model: model) }
            }
        }
        // Written for the same reason as ``registrations``: the same keys, every list empty.
        let none: [FixtureTransport.Rule] = [
            .get("\(Self.api)/numbers/registrations", .json(
                #"{"success":true,"registrations":[],"approvedCountries":[],"platformCountries":[]}"#
            )),
        ]
        try await assertView("empty", rules: none + ScreenRules.loaded, size: Self.size) { app in
            let model = Self.provisioning(app)
            await model.loadRegistrations()
            return Self.tab { RegistrationsSection(model: model) }
        }
        let failing: [FixtureTransport.Rule] = [.get("\(Self.api)/numbers/registrations", .status(500))]
        try await assertView("failed", rules: failing + ScreenRules.loaded, size: Self.size) { app in
            let model = Self.provisioning(app)
            await model.loadRegistrations()
            return Self.tab { RegistrationsSection(model: model) }
        }
        try await assertView("viewer", rules: ScreenRules.loaded, size: Self.size) { app in
            let model = Self.provisioning(app, role: .viewer)
            await model.loadRegistrations()
            return Self.tab { RegistrationsSection(model: model) }
        }
    }

    func testRegistrationRequirements() async throws {
        try await assertView("regulated", rules: Self.registrations + ScreenRules.loaded, size: Self.size) { app in
            let model = Self.provisioning(app)
            await model.loadRegistrations()
            model.registrationDraft.country = "DE"
            await model.loadRequirements()
            return Self.tab { RegistrationsSection(model: model) }
        }
        let unregulated: [FixtureTransport.Rule] = [
            .get("\(Self.api)/numbers/requirements", .json(
                #"{"success":true,"country":"US","numberType":"local","purchasable":false,"requirements":null}"#
            )),
        ]
        try await assertView(
            "unregulated",
            rules: unregulated + Self.registrations + ScreenRules.loaded,
            size: Self.size
        ) { app in
            let model = Self.provisioning(app)
            await model.loadRegistrations()
            model.registrationDraft.country = "US"
            await model.loadRequirements()
            return Self.tab { RegistrationsSection(model: model) }
        }
        let failing: [FixtureTransport.Rule] = [
            .get("\(Self.api)/numbers/requirements", .status(500)),
            .any("\(Self.api)/numbers/registrations", .status(500)),
        ]
        // The list, the requirements read and the start all answered 500.
        try await assertView("failed", rules: failing + ScreenRules.loaded, size: Self.size) { app in
            let model = Self.provisioning(app)
            await model.loadRegistrations()
            model.registrationDraft.country = "DE"
            await model.loadRequirements()
            await model.createRegistration()
            return Self.tab { RegistrationsSection(model: model) }
        }
    }

    // MARK: - Carrier

    func testCarrier() async throws {
        for locale in [L10nLocale.en, .frCA] {
            try await assertView(
                Self.named("loaded", locale),
                rules: Self.carrier + ScreenRules.loaded,
                locale: locale,
                size: Self.size
            ) { app in
                try await Self.carrierTab(app)
            }
        }
        let none: [FixtureTransport.Rule] = [
            .get("\(Self.api)/provider/status", .fixture("mobile/district-provider-status-none.json")),
        ]
        try await assertView("not-connected", rules: none + Self.carrier + ScreenRules.loaded, size: Self.size) { app in
            try await Self.carrierTab(app)
        }
        let failing: [FixtureTransport.Rule] = [
            .get("\(Self.api)/provider/status", .status(500)),
            .get("\(Self.api)/verify", .status(500)),
            .get("\(Self.api)/sip", .status(500)),
        ]
        try await assertView("failed", rules: failing + ScreenRules.loaded, size: Self.size) { app in
            try await Self.carrierTab(app)
        }
        try await assertView("viewer", rules: Self.carrier + ScreenRules.loaded, size: Self.size) { app in
            try await Self.carrierTab(app, role: .viewer)
        }
    }

    /// The paid lookup, answered with the recorded valid and invalid numbers. The card alone,
    /// since on the carrier tab its answer is drawn below the fold.
    func testLookup() async throws {
        let valid: [FixtureTransport.Rule] = [
            .get("\(Self.api)/lookup", .fixture("mobile/district-number-lookup.json")),
        ]
        try await assertView("valid", rules: valid + Self.carrier + ScreenRules.loaded, size: Self.size) { app in
            try await Self.lookupCard(app) { model in
                model.lookupNumber = "+14165550142"
                await model.lookup()
            }
        }
        let invalid: [FixtureTransport.Rule] = [
            .get("\(Self.api)/lookup", .fixture("mobile/district-number-lookup-invalid.json")),
        ]
        try await assertView("invalid", rules: invalid + Self.carrier + ScreenRules.loaded, size: Self.size) { app in
            try await Self.lookupCard(app) { model in
                model.lookupNumber = "+1416"
                await model.lookup()
            }
        }
        let failing: [FixtureTransport.Rule] = [.get("\(Self.api)/lookup", .status(500))]
        try await assertView("failed", rules: failing + Self.carrier + ScreenRules.loaded, size: Self.size) { app in
            try await Self.lookupCard(app) { model in
                model.lookupNumber = "+14165550142"
                await model.lookup()
            }
        }
    }

    // MARK: - Drawing

    /// The detail column of the regular window, less the sidebar.
    static let size = CGSize(width: 900, height: 800)

    /// The tab's content as `MarketplaceView` lays it out: scrolled, padded, readable width.
    static func tab(@ViewBuilder _ content: () -> some View) -> AnyView {
        AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: DistrictSpacing.section) {
                    content()
                }
                .padding(DistrictSpacing.gutter)
                .districtReadableWidth()
            }
        )
    }

    /// The search tab: the form, filled as given, over `results`.
    private static func search(areaCode: String, type: String, @ViewBuilder results: () -> some View) -> AnyView {
        tab {
            VStack(alignment: .leading, spacing: DistrictSpacing.row) {
                NumberSearchFormCard(
                    areaCode: .constant(areaCode),
                    country: .constant(""),
                    selectedType: type,
                    searching: false,
                    onSelectType: { _ in },
                    onSearch: {}
                )
                results()
            }
        }
    }

    /// The carrier tab after the three reads `MarketplaceView` runs when it is chosen, and
    /// whatever `then` does to the model after them.
    static func carrierTab(
        _ app: SignedInApp,
        role: WorkspaceRole = .agency,
        then: (NumberProvisioningModel) async -> Void = { _ in }
    ) async throws -> AnyView {
        let model = provisioning(app, role: role)
        await model.loadCarrier()
        await model.loadVerify()
        await model.loadSip()
        await then(model)
        return tab {
            VStack(alignment: .leading, spacing: DistrictSpacing.row) {
                CarrierSection(model: model)
                NumberLookupCard(model: model)
                ComplianceSection(model: model)
            }
        }
    }

    /// The lookup card after `then`.
    private static func lookupCard(
        _ app: SignedInApp,
        then: (NumberProvisioningModel) async -> Void
    ) async throws -> AnyView {
        let model = provisioning(app)
        await then(model)
        return tab { NumberLookupCard(model: model) }
    }

    static func provisioning(_ app: SignedInApp, role: WorkspaceRole = .agency) -> NumberProvisioningModel {
        NumberProvisioningModel(container: app.container, workspaceId: app.workspaceId, role: role)
    }

    static func named(_ state: String, _ locale: L10nLocale) -> String {
        "\(state)-\(locale == .en ? "en" : "fr")"
    }

    static func unwrap<Value>(_ outcome: Result<Value, ApiError>) throws -> Value {
        try outcome.get()
    }

    // MARK: - Rules

    /// The carrier tab's reads: the provider status and SIP trunks are in ``ScreenRules/loaded``;
    /// the Verify service is answered here.
    static let carrier: [FixtureTransport.Rule] = [
        .get("\(api)/verify", .fixture("mobile/district-verify.json")),
    ]

    /// ⚠️ WRITTEN BODIES, BECAUSE THE CORPUS RECORDS NO ANSWER FOR EITHER READ, and they are the
    /// only way to draw the registrations list. Their keys are `NumberRegistrationsResponse`'s and
    /// `NumberRegistration`'s, all present: a draft with a stored document, a rejected bundle with
    /// its reasons, and an approved one, which are the three ways a row draws.
    static let registrations: [FixtureTransport.Rule] = [
        .get("\(api)/numbers/registrations", .json(registrationsJSON)),
        .get("\(api)/numbers/requirements", .json(requirementsJSON)),
    ]

    private static let registrationsJSON = """
    {"success":true,"approvedCountries":["GB"],"platformCountries":["CA","US"],"registrations":[\
    {"id":"BU_draft","isoCountry":"DE","numberType":"local","endUserType":"business",\
    "friendlyName":"Berlin office","status":"draft","rejectionReasons":[],"submittedAt":null,\
    "reviewedAt":null,"createdAt":"2026-09-01T10:00:00Z","documents":[{"id":"doc-1",\
    "requirementName":"proof_of_address","mimeType":"application/pdf","sizeBytes":182044,\
    "stored":true,"submitted":false,"updatedAt":"2026-09-01T10:05:00Z"}]},\
    {"id":"BU_rejected","isoCountry":"FR","numberType":"mobile","endUserType":"business",\
    "friendlyName":null,"status":"twilio-rejected","rejectionReasons":["The address does not match the document."],\
    "submittedAt":"2026-09-02T10:00:00Z","reviewedAt":"2026-09-04T10:00:00Z",\
    "createdAt":"2026-09-02T09:00:00Z","documents":[]},\
    {"id":"BU_approved","isoCountry":"GB","numberType":"local","endUserType":"business",\
    "friendlyName":"London","status":"twilio-approved","rejectionReasons":[],\
    "submittedAt":"2026-08-20T10:00:00Z","reviewedAt":"2026-08-25T10:00:00Z",\
    "createdAt":"2026-08-20T09:00:00Z","documents":[]}]}
    """

    /// ⚠️ WRITTEN FOR THE SAME REASON: no recorded answer. `NumberRequirementsResponse`'s keys,
    /// with one field requirement and one document requirement.
    private static let requirementsJSON = """
    {"success":true,"country":"DE","numberType":"local","purchasable":true,"requirements":\
    {"isoCountry":"DE","numberType":"local","endUserType":"business","regulationSid":"RN_contract",\
    "friendlyName":"Germany: local, business","requirements":[\
    {"kind":"end_user","name":"Business information","requirementName":"business_info",\
    "type":"end_user","fields":["business_name","business_registration_number"],"acceptedDocuments":null},\
    {"kind":"document","name":"Proof of address","requirementName":"proof_of_address",\
    "type":"document","fields":["address_sids"],"acceptedDocuments":[{"name":"Utility bill",\
    "type":"utility_bill","fields":["address_sids"]}]}]}}
    """
}
