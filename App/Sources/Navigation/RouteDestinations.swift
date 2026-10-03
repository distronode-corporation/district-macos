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
/// ⚠️ UNLIKE iOS, A ROUTE WHOSE SCREEN IS NOT PORTED YET LANDS ON ``ComingLaterView``,
/// named after the sidebar section that owns it. iOS forbids a placeholder arm because
/// that build goes to external testers (App Store Review Guideline 2.1); the Mac app
/// ships nothing until every section is ported (plan Wave 10), and each wave replaces
/// arms here with the real screen.
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

        case .hq, .analytics, .marketplace, .billing, .workflows, .rooms, .activeRoom, .dialer,
             .workspaceSettings, .scheduling, .support, .supportRequest, .desk, .deskTicket:
            ComingLaterView(item: ShellPaths.listSection(of: route))
        }
    }
}
