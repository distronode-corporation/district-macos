import DistrictData
import DistrictModel
import SwiftUI

/// Everything that MOVES the shell: a tapped notification, an app link, and the one
/// function that applies either. Ported from district-ios `ShellView+Routing.swift`.
///
/// ⛔ A SIBLING FILE BECAUSE OF SwiftLint's 500-LINE `file_length`, WHICH `--strict`
/// PROMOTES TO AN ERROR, as on iOS.
///
/// ⚠️ WHAT THE SPLIT COSTS, LISTED SO IT CANNOT QUIETLY GROW. Five `@State` properties on
/// ``ShellView`` are internal rather than `private` (`workspaceSession`, `paths`,
/// `deepLinks`, `pendingLink`, `inboxPushSignal`), because `private` is file-scoped in
/// Swift and every one of them is read or written here.
///
/// ⛔ AND THIS FILE IS STILL INSIDE THE SIGNED-IN GATE. ``RootView`` draws ``ShellView``
/// only for a signed-in session, so nothing here can run for an account that is no longer
/// on this Mac, which is reachable: the server's token row survives a sign-out whose
/// unregister could not be delivered, and APNs keeps delivering to a live token.
///
/// ⚠️ WHAT THE MAC LEAVES OUT: iOS's Reply and Mark read from the notification shade
/// (`performMessageAction`). The Mac registers no message category, so a message
/// notification has no buttons and a press is always a plain tap.
extension ShellView {
    // ── Notification routing ─────────────────────────────────────────────────

    /// Take whatever the registrar is holding and make it the outstanding push.
    ///
    /// ⛔ THE MAILBOX IS EMPTIED ON PICKUP RATHER THAN ON CONSUMPTION, so there is never
    /// more than one live copy of "a push is outstanding", and a second tap on an
    /// IDENTICAL notification is still a change `onChange` sees. Whether the event survives
    /// is ``PushDeepLinks``'s question, asked below.
    ///
    /// ⚠️ AN UNPARSEABLE PAYLOAD IS STILL CONSUMED: a type this build does not know, or a
    /// missing id, leaves nothing to act on, and a payload left in the mailbox would block
    /// the next real one.
    func adoptTappedPush() {
        guard let payload = push.pendingTapPayload else { return }
        push.pendingTapPayload = nil
        guard let event = PushPayload.parse(payload) else { return }
        deepLinks.offer(event)
        resolvePendingPush()
    }

    /// Ask what the outstanding push means now, and act if it means anything yet.
    ///
    /// ⛔ CLEARED ON EVERY RESOLUTION EXCEPT ``PushDeepLinkDecision/wait``, INCLUDING
    /// ``PushDeepLinkDecision/drop``: a dropped link that survived would re-fire the moment
    /// the user switched to that workspace for their own reasons, minutes later.
    ///
    /// ⛔ THE SECTION MOVES BEFORE THE RESOLVE, which is what makes a failed resolve
    /// harmless: the Inbox is on screen before a request goes out.
    func resolvePendingPush() {
        let selected = workspaceSession.workspaceId
        let decision = deepLinks.decision(selectedWorkspaceId: selected)
        guard decision.consumesPending else { return }
        deepLinks.clear()
        guard let action = PushRouting.action(for: decision, selectedWorkspaceId: selected) else { return }
        apply(action)
        // ⚠️ THE ONLY DECISION WITH A SECOND, ASYNCHRONOUS HALF: a message names a row,
        // not a destination, so the thread has to be fetched.
        if case let .openMessage(workspaceId, messageId) = decision {
            resolveMessagePush(workspaceId: workspaceId, messageId: messageId)
        }
    }

    // ── App links ────────────────────────────────────────────────────────────

    /// Take a URL the system handed this app: `onOpenURL`, or a browsing-web
    /// `NSUserActivity` continued.
    ///
    /// ⛔ THREE ANSWERS, AND THE MIDDLE ONE IS NOT THE SAME AS EITHER NEIGHBOUR. nil is
    /// "never ours" and leaves the URL alone (the resolver refuses anything but https on
    /// the site's own hosts). ``AppLinkOutcome/openInBrowser`` is "ours, and the honest
    /// answer is the web page", opened in the default browser NAMED (``BrowserHandOff``),
    /// never through Launch Services' choice of handler, which for a claimed URL is this
    /// app again. Only the third navigates.
    ///
    /// ⚠️ ``recentLinks`` DROPS THE SAME URL DELIVERED TWICE IN A MOMENT. The shell listens
    /// on both entry points; should one link reach both, the second would open a second
    /// browser tab.
    func receiveLink(_ url: URL) {
        guard recentLinks.admit(url, at: Date()) else { return }
        guard let outcome = AppLinkResolver.resolve(url) else { return }
        switch outcome {
        case .openInBrowser:
            // ⚠️ THE URL AS DELIVERED, query and fragment included.
            BrowserHandOff.open(url)
        case let .destination(destination):
            // ⚠️ LAST ONE WINS, no queue: a second link is the one the user asked for now.
            pendingLink = destination
            resolvePendingLink()
        }
    }

    /// Act on the outstanding link, if the app knows enough to.
    ///
    /// ⛔ WAIT, NOT DROP, AND THE LINK SURVIVES THE WAIT. A destination that becomes a
    /// workspace-scoped ``Route`` is held until ``WorkspaceSessionModel/workspaceId``
    /// resolves, and the `onChange` in ``ShellView`` asks again. Dropping instead would make
    /// app links work only when the app was already open and loaded.
    ///
    /// ⛔ CLEARED THE MOMENT IT IS ACTED ON, as a consumed push is.
    func resolvePendingLink() {
        guard let destination = pendingLink else { return }
        let selected = workspaceSession.workspaceId
        guard !destination.requiresWorkspace || selected != nil else { return }
        pendingLink = nil
        apply(AppLinkRouting.action(
            for: destination,
            selectedWorkspaceId: selected,
            role: workspaceSession.role
        ))
    }

    // ── Applying an action ───────────────────────────────────────────────────

    /// ⛔ THE ONE PLACE ANYTHING MOVES THE SHELL, which is why pushes and links share an
    /// action type. What moves is ``ShellPaths/apply(_:)``, which is pure and tested; what
    /// stays here is what cannot be.
    ///
    /// ⚠️ THE WORKSPACE SWITCH IS STARTED FIRST AND NOT WAITED FOR, and the route is safe to
    /// land early because it carries its own `workspaceId` (the ⛔ on
    /// ``PushRouteAction/route``).
    ///
    /// ⛔ A WORKSPACE SWITCH ENDS A LIVE ROOM. A room belongs to the workspace that minted
    /// its token, and the switch puts the shell back on its loading state, which takes the
    /// room's screen (and its controls) away while ``CallStack`` keeps it publishing.
    private func apply(_ action: PushRouteAction) {
        if let workspaceId = action.selectWorkspaceId {
            let callStack = container.callStack
            Task { await callStack.endRoom(.workspaceChanged) }
            Task { await workspaceSession.select(workspaceId) }
            // ⛔ EVERY STACK IS CLEARED HERE AND NOT LEFT TO ``ShellPaths/adopt(_:)``, and the
            // stamp is what tells the `onChange` the switch is already accounted for, so the
            // route landed below is not cleared again when the new list resolves.
            paths.reset(to: workspaceId)
        }
        paths.apply(action)
    }

    // ── Resolving a pushed message into its conversation ─────────────────────

    /// Turn a pushed `messageId` into the thread it names, and open it beside the Inbox.
    ///
    /// ⛔ THE LIST IS ALREADY ON SCREEN BY THE TIME THIS RUNS, AND THAT IS THE WHOLE
    /// FALLBACK. Every way this can fail (a 404, a 409, an offline Mac, a 403 for a viewer,
    /// a message a workflow deleted) degrades to the Inbox list, so there is no failure
    /// branch below.
    ///
    /// ⛔ AND THE TENANT IS RE-READ AFTER THE AWAIT: if the selected workspace has moved on,
    /// the thread belongs to a section this notification no longer has a claim over.
    ///
    /// ⚠️ IT ALSO REFRESHES THE LIST, THROUGH ``inboxPushSignal``: a push means the
    /// workspace has a message the loaded rows do not.
    func resolveMessagePush(workspaceId: String, messageId: String) {
        inboxPushSignal += 1
        let repository = container.inbox
        let role = workspaceSession.role
        Task {
            guard case let .success(resolved) = await repository.messageThread(
                workspaceId: workspaceId,
                messageId: messageId
            ) else {
                return
            }
            guard workspaceSession.workspaceId == workspaceId else { return }
            // ⚠️ THE OPEN ROW OF THE INBOX'S LIST, as ``ShellPaths/open(_:)`` would place it.
            paths.setPath([
                Route.thread(
                    workspaceId: workspaceId,
                    role: role,
                    threadKey: resolved.threadKey,
                    // ⛔ THE SERVER'S OWN PAIR, the only one available on this path: the list
                    // has not been read here, so the composer names the channel instead of
                    // offering the set, which arrives with the list refresh.
                    replyTargets: [resolved.replyTarget],
                    // ⚠️ NO TITLE: the name comes from the list, which this path has not read.
                    title: nil
                ),
            ], for: .inbox)
        }
    }
}

/// The URLs the shell took in the last moment, so one link delivered twice opens once.
///
/// ⚠️ A WINDOW, NOT A SET: the same link tapped again a few seconds later is a new request
/// (a browser tab closed by accident, a section left) and is honoured.
struct RecentLinks {
    static let window: TimeInterval = 2

    private var last: (url: URL, at: Date)?

    /// Whether `url` is new, recording it either way.
    mutating func admit(_ url: URL, at now: Date) -> Bool {
        defer { last = (url, now) }
        guard let last, last.url == url else { return true }
        return now.timeIntervalSince(last.at) >= Self.window
    }
}
