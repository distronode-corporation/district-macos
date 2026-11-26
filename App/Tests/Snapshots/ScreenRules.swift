import Foundation

/// Which recorded response answers which route, for the screen snapshot tests.
///
/// ⚠️ EVERY BODY IS THE SERVICE'S OWN (`contracts/`), edited only where a screen needs a state
/// the recording does not hold, and each edit says why. The one standing edit is the workspace
/// list's default, moved to the agency workspace so every section is drawn as a role that may
/// open it.
enum ScreenRules {
    private static let api = "/api/district"

    /// The workspace list, with the agency workspace as the default.
    static let workspaces: [FixtureTransport.Rule] = [
        .get("\(api)/workspace/list", .edited("mobile/district-workspace-list.json") { list in
            list["defaultWorkspaceId"] = ScreenSnapshotCase.workspaceId
        }),
    ]

    /// Every read the screens make, answered with a recorded response that has rows in it.
    static let loaded: [FixtureTransport.Rule] = workspaces + [
        // The account.
        .get("/api/settings", .fixture("mobile/district-settings.json")),
        .get("/api/auth/native/devices", .fixture("mobile/district-devices.json")),
        .get("/api/auth/native/mfa/status", .fixture("mobile/district-mfa-status.json")),
        .get("/api/auth/mfa/status", .fixture("mobile/district-mfa-status.json")),
        .get("/api/billing", .fixture("mobile/district-billing.json")),

        // The workspace's own reads.
        .get("\(api)/workspace/config", .fixture("mobile/district-workspace-config.json")),
        .get("\(api)/workspace/usage/history", .fixture("mobile/district-usage-history.json")),
        .get("\(api)/workspace/usage", .fixture("mobile/district-usage.json")),
        .get("\(api)/workspace/billing", .fixture("mobile/district-workspace-billing.json")),
        .get("\(api)/workspace/persona/options", .fixture("mobile/district-persona-options.json")),
        .get("\(api)/workspace/persona/voice-studio", .fixture("mobile/district-voice-studio.json")),
        .get("\(api)/workspace/knowledge-mode", .fixture("mobile/district-knowledge-mode.json")),
        .get("\(api)/workspace/knowledge", .fixture("mobile/district-knowledge.json")),
        .get("\(api)/workspace/messaging", .fixture("mobile/district-messaging.json")),
        .get("\(api)/workspace/members", .fixture("mobile/district-members.json")),
        .get("\(api)/workspace/call-handling", .fixture("mobile/district-call-handling.json")),
        .get("\(api)/workspace/campaign-status", .fixture("mobile/district-campaign-status.json")),
        .get("\(api)/workspace/campaign-settings", .fixture("mobile/district-campaign-settings.json")),
        .get("\(api)/workspace/provider/numbers", .fixture("mobile/district-provider-numbers.json")),
        .get("\(api)/workspace/provider/status", .fixture("mobile/district-provider-status.json")),
        .get("\(api)/workspace/email-identity", .fixture("mobile/district-email-identity.json")),
        .get("\(api)/workspace/whatsapp/templates", .fixture("mobile/district-whatsapp-templates.json")),
        .get("\(api)/workspace/whatsapp/window", .fixture("mobile/district-whatsapp-window.json")),
        .get("\(api)/workspace/sip", .fixture("mobile/district-sip-trunks.json")),

        // The sections.
        .get("\(api)/overview", .fixture("mobile/district-overview.json")),
        .get("\(api)/setup", .fixture("mobile/district-setup.json")),
        .get("\(api)/analytics", .fixture("mobile/district-analytics.json")),
        .get("\(api)/calls/[^/]+/transcript", .fixture("mobile/district-call-transcript.json")),
        .get("\(api)/calls/[^/]+", .fixture("mobile/district-call-detail.json")),
        .get("\(api)/calls", .fixture("mobile/district-calls.json")),
        .get("\(api)/contacts/blocked", .fixture("mobile/district-contacts-blocked.json")),
        .get("\(api)/contacts/get", .fixture("mobile/district-contact-detail.json")),
        .get("\(api)/contacts", .fixture("mobile/district-contacts.json")),
        .get("\(api)/conversations", .fixture("mobile/district-conversations.json")),
        .get("\(api)/timeline", .fixture("mobile/district-timeline.json")),
        .get("\(api)/messages/unread-count", .fixture("mobile/district-messages-unread-count.json")),
        .get("\(api)/messages/drafts", .fixture("mobile/district-drafts-list.json")),
        .get("\(api)/messages/draft", .fixture("mobile/district-draft-null.json")),
        .get("\(api)/messages/[^/]+/sender", .fixture("mobile/district-message-sender.json")),
        .get("\(api)/messages/[^/]+", .fixture("mobile/district-message-thread.json")),
        .get("\(api)/meetings/[^/]+", .fixture("mobile/district-meeting-detail.json")),
        .get("\(api)/meetings", .fixture("mobile/district-meetings.json")),
        .get("\(api)/workflows/runs", .fixture("mobile/district-workflow-runs.json")),
        .get("\(api)/workflows", .fixture("mobile/district-workflows.json")),
        .get("\(api)/desk/settings", .fixture("mobile/district-desk-settings.json")),
        .get("\(api)/desk/tickets/[^/]+", .fixture("mobile/district-desk-ticket.json")),
        .get("\(api)/desk/tickets", .fixture("mobile/district-desk-tickets.json")),
        .get("\(api)/support/requests/[^/]+", .fixture("mobile/district-support-request.json")),
        .get("\(api)/support/requests", .fixture("mobile/district-support-requests.json")),
        .get("\(api)/hq/voice-settings", .fixture("mobile/district-hq-voice-settings.json")),
        .get("\(api)/hq/voice-context", .fixture("mobile/district-hq-voice-context.json")),
        .get("\(api)/scheduling/status", .fixture("mobile/district-scheduling-status-ready.json")),
    ] + scheduling

    /// The scheduling admin proxy's reads.
    static let scheduling: [FixtureTransport.Rule] = [
        .scheduling("me.get", .fixture("mobile/district-scheduling-me.json")),
        .scheduling("eventTypes.list", .fixture("mobile/district-scheduling-event-types.json")),
        .scheduling("eventTypes.get", .fixture("mobile/district-scheduling-event-type.json")),
        .scheduling("eventTypes.hosts.get", .fixture("mobile/district-scheduling-hosts.json")),
        .scheduling("eventTypes.questions.list", .fixture("mobile/district-scheduling-questions.json")),
        .scheduling("eventTypes.slots", .fixture("mobile/district-scheduling-slots.json")),
        .scheduling("availability.rules.list", .fixture("mobile/district-scheduling-rules.json")),
        .scheduling("availability.overrides.list", .fixture("mobile/district-scheduling-overrides.json")),
        .scheduling("bookings.list", .fixture("mobile/district-scheduling-bookings.json")),
        .scheduling("bookings.answers", .fixture("mobile/district-scheduling-booking-answers.json")),
        .scheduling("calendar.status", .fixture("mobile/district-scheduling-calendar-status.json")),
        .scheduling("calendar.connections.calendars.get", .fixture("mobile/district-scheduling-calendars.json")),
        .scheduling("zoom.status", .fixture("mobile/district-scheduling-zoom-status.json")),
        .scheduling("users.list", .fixture("mobile/district-scheduling-users.json")),
        .scheduling("users.upcomingBookings", .fixture("mobile/district-scheduling-user-upcoming.json")),
        .scheduling("teams.list", .fixture("mobile/district-scheduling-teams.json")),
        .scheduling("teams.get", .fixture("mobile/district-scheduling-team.json")),
        .scheduling("settings.branding.get", .fixture("mobile/district-scheduling-branding.json")),
        .scheduling("settings.llm.get", .fixture("mobile/district-scheduling-llm.json")),
        .scheduling("apiKeys.list", .fixture("mobile/district-scheduling-api-keys.json")),
        .scheduling("oauth.connections.list", .fixture("mobile/district-scheduling-oauth-connections.json")),
        .scheduling("webhooks.list", .fixture("mobile/district-scheduling-webhooks.json")),
        .scheduling("webhooks.deliveries", .fixture("mobile/district-scheduling-webhook-deliveries.json")),
    ]

    /// Every read answered with a 500, after the workspace list: each screen's failure state.
    static let failing: [FixtureTransport.Rule] = workspaces + [
        .any(".*", .status(500)),
    ]
}
