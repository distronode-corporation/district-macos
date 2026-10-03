import DistrictNetwork
import SwiftUI

/// The one place a ``Route`` becomes a screen.
///
/// Ported from district-ios `Navigation/RouteDestinations.swift` (see PORTING.md).
///
/// ⛔ ONE SWITCH, AND EXHAUSTIVE. `navigationDestination(for: Route.self)` is registered
/// once per stack in ``ShellView``, so this function is the whole routing table, and
/// SwiftUI resolves `navigationDestination` by TYPE: two registrations in one stack are a
/// runtime coin toss rather than a compile error. A new ``Route`` case fails to compile
/// here until someone decides what it shows. Never reach for a `default`.
///
/// ⚠️ NO ARM IS A PLACEHOLDER ANY MORE (Wave 8 ported the last two), as iOS requires for a
/// build external testers see (App Store Review Guideline 2.1).
///
/// ⛔ TWO SESSIONS, AND THEY ARE NOT INTERCHANGEABLE. ``session`` is the WORKSPACE session;
/// ``accountSession`` is the process's one ``SessionModel``, which `Route.devices` needs:
/// signing out a device can end THIS installation's session, so that screen drives the
/// local sign-out itself.
enum RouteDestinations {
    @MainActor
    @ViewBuilder
    static func view(
        for route: Route,
        container: AppContainer,
        session _: WorkspaceSessionModel,
        accountSession: SessionModel
    ) -> some View {
        switch route {
        case let .callDetail(workspaceId, callId):
            CallDetailView(container: container, workspaceId: workspaceId, callId: callId)

        // ⛔ THE SET IS CARRIED WHOLE AND NOT NARROWED HERE. `Route.thread` holds every
        // channel the thread can be answered on, best first, and the composer is what
        // offers the choice. An EMPTY array means no reply box at all.
        case let .thread(workspaceId, role, threadKey, replyTargets, title):
            ThreadView(
                container: container,
                workspaceId: workspaceId,
                role: role,
                threadKey: threadKey,
                replyTargets: replyTargets,
                title: title
            )

        case let .contactDetail(workspaceId, role, contactId):
            ContactDetailView(container: container, workspaceId: workspaceId, role: role, contactId: contactId)

        case .devices:
            DevicesView(container: container, session: accountSession)

        // ⛔ THE ONE DESTINATION THAT SPENDS MONEY AND RINGS A STRANGER'S TELEPHONE, and it
        // is ONE destination for both the keypad and the live call: a separate in-call
        // route would be restored after relaunch and its start effect would run again,
        // placing a second billable call with no user action. See the ⛔ on `Route.dialer`.
        case let .dialer(workspaceId, role):
            DialerView(container: container, workspaceId: workspaceId, role: role)

        // ⚠️ THE ROLE IS CARRIED BUT THE LIST IS NOT GATED ON IT: the lobby hides only the
        // START form from a viewer, whose token carries `canPublish:false` anyway.
        case let .rooms(workspaceId, role):
            RoomsLobbyView(container: container, workspaceId: workspaceId, role: role)

        // ⛔ THE ONE DESTINATION THAT PUBLISHES VIDEO, AND IT JOINS NOTHING ON ARRIVAL: a
        // restored route that connected from a `.task` would re-enter a room with nobody
        // having asked, so `ActiveRoomView` opens on a Join control. ⛔ AND THE NAME IS
        // VALIDATED HERE AND NEVER REBUILT: `RoomName(joining:)` refuses a `video_` room (a
        // BILLABLE avatar session, one character away) and a bare `Call.id`.
        case let .activeRoom(_, role, roomName):
            if let room = RoomName(joining: roomName) {
                ActiveRoomView(container: container, roomName: room, role: role)
            } else {
                FailureView(failure: RoomsCopy.unusableName)
            }

        case let .hq(workspaceId, role):
            HQView(container: container, workspaceId: workspaceId, role: role)

        // ⚠️ CARRIES NO ROLE: both routes behind it admit every role. See `Route.analytics`.
        case let .analytics(workspaceId):
            AnalyticsView(container: container, workspaceId: workspaceId)

        // ⛔ READ-ONLY, IN BOTH MAC BUILDS. App Store Review Guideline 3.1.3(b) keeps plan
        // changes, payment methods and cancellations out of the app, and 3.1.1 keeps every
        // sentence from naming somewhere else to go (`StoreCopyTests`). The Developer ID
        // build is not exempt: it is the same bundle id and the same screens.
        case let .billing(workspaceId, role):
            BillingView(container: container, workspaceId: workspaceId, role: role)

        // ⚠️ A MONITOR RATHER THAN A SETTINGS SECTION: three of its four routes admit
        // `viewer` and nothing on it is authored. See `Route.workflows`.
        case let .workflows(workspaceId, role):
            WorkflowsView(container: container, workspaceId: workspaceId, role: role)

        // ⛔ SUPPORT AND THE DESK ARE OPPOSITE SURFACES that share every noun: Support is
        // this tenant writing to Distronode, the Desk is their own customers writing to
        // them. ⚠️ As list sections, their roots are drawn by ``ShellView``'s content
        // column with a selection; these arms are the same screens without one.
        case let .support(workspaceId, role):
            SupportView(container: container, workspaceId: workspaceId, role: role)

        case let .supportRequest(workspaceId, role, key):
            SupportThreadView(container: container, workspaceId: workspaceId, role: role, key: key)

        case let .desk(workspaceId, role):
            DeskView(container: container, workspaceId: workspaceId, role: role)

        case let .deskTicket(workspaceId, role, ticketId):
            DeskTicketView(container: container, workspaceId: workspaceId, ticketId: ticketId, role: role)

        // ⛔ THE ROLE IS A REAL GATE: every route behind the hub, the config read included,
        // excludes `viewer`. One line per destination family here; one per section in
        // ``SettingsDestinations``, which keeps both switches exhaustive.
        case let .workspaceSettings(workspaceId, role, section):
            SettingsDestinations.view(for: section, container: container, workspaceId: workspaceId, role: role)

        // ⚠️ THE HUB, ITS NINE SECTIONS AND THE TWO DRILL-DOWNS, one line here and one per
        // section in ``SchedulingDestinations``, as iOS splits it. The sidebar's Scheduling
        // row and the settings hub's both arrive here at `section: .hub`.
        case let .scheduling(workspaceId, role, section):
            SchedulingDestinations.view(
                for: section,
                container: container,
                workspaceId: workspaceId,
                role: role
            )

        // ⛔ NO PURCHASE, IN BOTH MAC BUILDS, AND NOTHING ON IT OPENS A URL. Buying a number is
        // a recurring charge for a service used in the app (Guideline 3.1.1), so it is absent
        // rather than linked; the role only words the read-only caption.
        // `MacMarketplaceNoExitTests`.
        case let .marketplace(workspaceId, role):
            MarketplaceView(container: container, workspaceId: workspaceId, role: role)
        }
    }
}
