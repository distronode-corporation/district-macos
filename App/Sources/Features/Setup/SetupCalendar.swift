import DistrictModel

/// The calendar the receptionist books into, read as district-ios's Integrations screen reads
/// it (`IntegrationsModel.rows(from:)`), for step 5's Bookings card.
///
/// ⚠️ THE MAC HAS NO INTEGRATIONS SCREEN YET, so this is that screen's rule alone, copied
/// unchanged: when one is ported, step 5 reads its rows again, as on iOS, so the two can never
/// disagree.
///
/// ⛔ THE NAMES ARE THE PROVIDERS' PRODUCT NAMES AND ARE THE SAME IN BOTH LOCALES, so they are
/// not in the catalog (the web keeps them identically, `capabilitiesI18n` `calendarProviderNames`).
enum SetupCalendarProvider: String, CaseIterable {
    case google
    case microsoft

    /// The `provider` the connections read stores for this calendar.
    var connectionProvider: String {
        switch self {
        case .google: "google-calendar"
        case .microsoft: "microsoft-calendar"
        }
    }

    var name: String {
        switch self {
        case .google: "Google Calendar"
        case .microsoft: "Microsoft Outlook Calendar"
        }
    }

    /// The provider whose connection is `active` AND is the one the workspace books through,
    /// in the web's order; nil when none is. ⚠️ A VIEWER'S ANSWER CARRIES NO `calendar` BLOCK,
    /// so it names none.
    static func active(in response: ConnectionsResponse) -> SetupCalendarProvider? {
        allCases.first { provider in
            let stored = response.connections.first { $0.provider == provider.connectionProvider }
            return stored?.status == "active" && response.calendar?.activeProvider == provider.rawValue
        }
    }
}
