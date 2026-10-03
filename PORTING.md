# Porting from district-ios

Version 1 of the Mac app is parity with the iPad app. Its screens are copied from
[district-ios](https://github.com/distronode-corporation/district-ios) (`App/Sources` and
`App/Tests`) at a recorded commit and then adapted to macOS. This file records which
commit each part came from, so a later change on iOS can be found and carried over with
`git diff <recorded commit>..main -- <path>` in district-ios.

Both apps use the same [district-core-swift](https://github.com/distronode-corporation/district-core-swift)
release (2.0.0 at the time of these ports), so models, repositories and their tests are
not copied: they are shared.

## Ported so far

| Wave | Part | From district-ios | Mac files |
|---|---|---|---|
| 5 | Overview (with Finish setup) | `4777c40` | `App/Sources/Features/Overview/` |
| 5 | Account (with Calls to you) | `4777c40` | `App/Sources/Features/Account/` |
| 5 | Workspaces (header, picker, region and role copy) | `4777c40` | `App/Sources/Features/Workspaces/` |
| 5 | Devices | `4777c40` | `App/Sources/Features/Devices/` |
| 5 | Inbox (list, search, compose, thread, drafts, moderation) | `4777c40` | `App/Sources/Features/Inbox/` |
| 5 | Calls (the call log and one call; live calling is Wave 6) | `4777c40` | `App/Sources/Features/Calls/` |
| 5 | Contacts (list, create, detail, dossier, block) | `4777c40` | `App/Sources/Features/Contacts/` |
| 5 | Reporting a message or a call (from Support) | `4777c40` | `App/Sources/Features/Support/Report*.swift` |
| 5 | `SettingsField` only (from `Features/Settings/SettingsChrome.swift`) | `4777c40` | `App/Sources/Features/Settings/SettingsField.swift` |
| 5 | Paged feeds, unread badge, photo MIME types | `4777c40` | `App/Sources/Platform/` |
| 5 | Design system | `4777c40` | `App/Sources/DesignSystem/` |
| 5 | Routes, role gates, list/detail paths, menu commands | `4777c40` | `App/Sources/Navigation/` |
| 5 | Accessibility identifiers | `4777c40` | `App/Sources/Accessibility/` |
| 5 | Tests for the above | `4777c40` | `App/Tests/`, under the iOS file names; Mac-only tests are named `Mac*` or `test_MAC_*` |
| 6 | Incoming call (the model, its tasks, copy, caller identity, session gate, view) | `4777c40` | `App/Sources/Features/Incoming/` |
| 6 | The live-call surface shared by both directions (`LiveCall`, `InCallView`) | `4777c40` | `App/Sources/Features/Dialer/LiveCall.swift`, `InCallView.swift` |
| 6 | Call platform: `CallStack`, `LiveKitCallEngine`, `RoomAudio`, `MicrophoneAccess` | `4777c40` | `App/Sources/Platform/Calls/` |
| 6 | Tests: `InCallCopyTests`, the sentence half of `IncomingCallCopyTests`, `FakeMicrophoneAccess`, the at-Answer case of `MicrophoneAccessTests` (as `test_MAC_INCOMING_12`) | `4777c40` | `App/Tests/` |
| 6 | Dial (keypad, call-backs, outbound call, carrier hang-up, emergency-number guard) | `4777c40` | `App/Sources/Features/Dialer/` |
| 6 | Rooms (lobby, meeting record, the room, its engine and tiles) | `4777c40` | `App/Sources/Features/Rooms/` |
| 6 | Contacts: the Video call row (`ContactVideoCallModel`) | `4777c40` | `App/Sources/Features/Contacts/` |
| 6 | Tests: `DialerDestinationLineTests`, `LiveMediaReattachTests`, `RoomGridTests`, `RoomMediaToggleTests`, the dial half of `MicrophoneAccessTests` | `4777c40` | `App/Tests/` |
| 7 | District HQ (the console, the confirm card) | `4777c40` | `App/Sources/Features/HQ/` |
| 7 | Analytics (the window, the cards, the usage cards) | `4777c40` | `App/Sources/Features/Analytics/` |
| 7 | Billing (read-only: plan, overage, usage meter, Stripe half) | `4777c40` | `App/Sources/Features/Billing/` |
| 7 | Tests: `StoreCopyTests` (the 3.1.1 gate, Mac allowlist), `A11ySpokenFormTests` | `4777c40` | `App/Tests/` |
| 7 | Workflows (the SDR campaign card, the workflow list, a workflow's runs) | `4777c40` | `App/Sources/Features/Workflows/` |
| 7 | Desk (the queue, a ticket, settings with the public name and logo, the compose sheet) | `4777c40` | `App/Sources/Features/Desk/` |
| 7 | Support (requests to Distronode, a request's thread, inline compose) | `4777c40` | `App/Sources/Features/Support/Support*.swift` |
| 7 | `SettingsChrome.swift` whole (replacing Wave 5's `SettingsField.swift`), `SettingsConfigState.swift`, `SettingsCopy.swift` | `4777c40` | `App/Sources/Features/Settings/` |
| 7 | Tests: `DeskModelCreateTests`, `SettingsTestSupport` | `4777c40` | `App/Tests/` |
| 8 | Workspace settings: the hub and its eight sections (persona with its engine and the audition, capabilities, how calls are answered, transfer directory, dynamic persona rules, knowledge base, messaging with the carrier-account sheet, members), `SettingsCopy+*.swift`, `SettingsDestinations`, `SettingsWireDisplay` | `4777c40` | `App/Sources/Features/Settings/` |
| 8 | Tests: `PersonaEngineDraftTests`, `PersonaPreviewStateTests`, `RoutingEditorTests`, `SettingsPersonaCopyTests` | `4777c40` | `App/Tests/` |
| 8 | Phone numbers (my numbers, the carrier search, registrations, the carrier account and compliance, one number's actions and the confirmations) | `4777c40` | `App/Sources/Features/Marketplace/` |
| 8 | Tests: `StoreCopyTests`' Marketplace allowance and its two direct assertions (the purchase boundary, the trunk sentence) | `4777c40` | `App/Tests/StoreCopyTests.swift` |
| 9 | Scheduling, the read side: the hub (tenancy card, Enable, the provisioning poll, the booking link, the hand-off), the register (Overview), event types and one event type, hours and overrides, bookings and one booking (answers, notes, transcript), calendar connections, team, recordings (play, consent), settings (four tabs) and developer (keys, apps and MCP, webhooks and deliveries); `SchedulingCopy*`, `SchedulingSectionChrome`, `SchedulingDestinations` | `4777c40` | `App/Sources/Features/Scheduling/` |
| 9 | `A11yID+SchedulingWritesC.swift` (the webhook deliveries' identifiers live there on iOS too) | `4777c40` | `App/Sources/Accessibility/` |
| 9 | Scheduling, the write side: everything under `Writes/` (booking cancel, reschedule and reassign, regenerated notes; event type create, edit, state actions, hosts and questions; weekly hours and date overrides; calendar connect, CalDAV, calendar choice and disconnect; team create, edit, members and user archive; recording delete and delete-all; branding, automation, profile and notifications; API keys, connected apps and webhooks), the write hooks in the section screens, and `SchedulingSSOClient` | `4777c40` | `App/Sources/Features/Scheduling/`, `Writes/` |
| 9 | `A11yID+SchedulingWrites.swift`, `A11yID+SchedulingWritesB.swift`, `A11yID+SchedulingWriteEntry.swift` | `4777c40` | `App/Sources/Accessibility/` |
| 9 | Tests: every `SchedulingWrites*Tests` file and its support, and `SchedulingRescheduleDayZoneTests` (rewritten to find the `NSDatePicker` in an offscreen window) | `4777c40` | `App/Tests/` |
| 9 | Tests: `SchedulingFailureCopyTests`, `SchedulingHandOffTests`, `SchedulingModelTestCase`, `SchedulingModelTests`, `SchedulingReadConcurrencyTests`, `SchedulingSectionModelTests`, `SchedulingSectionTests`, `SchedulingTestTransport`, and `SchedulingRoutingTests` from its gate cases on (`_10` to `_15`, the settings hub's row among them) | `4777c40` | `App/Tests/` |

`4777c40` is district-ios commit `4777c40b032ecb437ede22060b71b754cebe6610` ("Adopt
district-core-swift 2.0.0").

Wave 6 also adds Mac-only parts with no iOS original: ringing over the telemetry socket
(`App/Sources/Platform/Live/`: the `URLSessionWebSocketTask` adapter for district-core-swift's
`DistrictLive`, the live session and its lifecycle, "Ring on this computer"), the ring panel,
sound and notification (`RingPanelController`, `RingPresenter`, `RingNotifications`), and the
microphone and speaker pickers (`AudioDevices`, `AudioDevicePickers`). Their behaviour follows
district-linux's desktop ringing, the one client that rang a desktop before this one.

Every section of the sidebar is now drawn for real, so the placeholder (`ComingLaterView`)
and `SidebarItem.portedInWave` are gone; `MacSidebarItemTests` pins that every section the
shell draws through `RouteDestinations` has a root route.

Wave 7 adds Mac-only tests with no iOS original: `MacBillingReadOnlyTests` (nothing under
`Features/Billing` may open a URL, see "Billing and Phone numbers" below), `MacAnalyticsBillingFormatTests`
(the figures a bill is read in), `MacDeskSupportWorkflowsTests` (status wording, the
support write states, trigger labels) and `MacTestIsolationTests` (see "Tests never touch
an installed copy").

Wave 8 adds Mac-only tests with no iOS original: `MacListSectionLoadTests` (see "A list
section reads once" below), `MacMarketplaceTests` (the role's wording and provisioning gate,
and that opening Phone numbers reads only the owned list), and two Phone numbers cases in
`MacBillingReadOnlyTests` (see "Billing and Phone numbers" below).

Wave 9 adds Mac-only tests with no iOS original: `MacSchedulingTests` (the two scheduling
tables' order and cells, the navigator a table row opens through, the settings hub's
Scheduling row, and ⌘N's create) and three Scheduling cases in `MacBillingReadOnlyTests`
(see "Billing and Phone numbers" below).

## Left out on purpose, and where it goes

- **`SchedulingRoutingTests`' first nine cases** (`test_IOS_SCHLINK_01` to `_09`) resolve a
  `www.distronode.com/dashboard/district/scheduling/...` link, so they come over with app
  links (below). The gate cases and the settings hub's row are ported.
- **A "New ticket" entry point on the Desk**: iOS at `4777c40` declares the compose sheet
  and its `composing` flag but nothing sets the flag, so the sheet is unreachable there.
  The Mac keeps the same code and the same absence; adding a button or a menu command is a
  product change for both apps, not a port.
- **App links and push taps** (`AppLinkRouting`, `PushRouting`, `ShellView+Routing`):
  a tapped notification or a `www.distronode.com` link does not open a section yet. The
  incoming-call notification's Answer and Decline buttons do work (Wave 6).
- **CallKit and VoIP push** (`CallKitBridge`, `VoIPPushHandler`, `AudioSessionCoordinator`,
  `SpeakerToggleRule`): never ported, by decision (the plan's decision 4). See "How the call
  path is adapted" below.

## How a file is adapted

Copied as is, then:

- `fullScreenCover` becomes a `sheet`, and a sheet gets a Cancel button
  (`.cancellationAction`, which takes Esc) and a size, because a Mac sheet has neither a
  swipe to dismiss nor a size of its own.
- `topBar*` toolbar placements become `.primaryAction`, `.cancellationAction` or
  `.confirmationAction`.
- `keyboardType`, `textInputAutocapitalization`, `navigationBarTitleDisplayMode` and
  `hoverEffect` are dropped: they do not exist on macOS.
- `UIPasteboard` becomes `Clipboard` (an `NSPasteboard` wrapper), and images go through
  the `PlatformImage` alias (`App/Sources/Platform/MacPlatform.swift`).
- UIKit bridges are rewritten in AppKit. `SafariView` has no Mac equivalent: a page the
  app itself claims (`applinks:`) opens in the default browser, named explicitly
  (`BrowserHandOff`), so it cannot be routed back into the app.
- Mac idioms are added where they are natural: `Table` with sortable columns for the
  call log and contacts (the Inbox keeps the iPad's rows), menu commands with keyboard
  shortcuts (File > New Message and New Contact, Edit > Search Messages, View > Refresh,
  Go), a toolbar Refresh button standing in for pull-to-refresh, and an Attach file
  button (the Finder's open panel) beside the Photos picker in a reply. District HQ's
  Send takes ⌘↩ (asking writes nothing); its Confirm takes no shortcut, like every
  control that deletes, places a call or spends money. Support's Send request and Send
  reply take ⌘↩ (they go to Distronode); the Desk's reply goes to a customer and, like the
  Inbox's, takes none. The Desk's logo gets a Choose file button (the Finder's open panel)
  beside the Photos picker, as a reply does. Desk and Support keep the iPad's rows rather
  than a `Table`: like the Inbox, each list is interleaved with state cards (desk off,
  settings unreadable, inline compose, status chips), which a table cannot hold.
- Scheduling's two list-heavy screens, Bookings and Event types, are sortable `Table`s with
  the web dashboard's column headings (When, Who, Event type, Host, Status; Name,
  Duration, Starts every, Location, State), every cell the iPad row's own words. A
  double-click or Return opens the row by appending to the stack (`ShellNavigator`), as
  the iPad's link does. Bookings keeps the iPad's view buttons above the table and its
  Load more button below it (one request per press, never on scroll). The other sections
  keep the iPad's cards: each row there carries inline state (a recording's consent, a
  webhook's deliveries, a team's actions) that a table row cannot hold.
- Scheduling's hours are a week of seven columns, Monday first, where the iPad stacks
  seven `label: value` rows: the same days, the same order, and each range in the words
  `SchedulingCopy.dayHours` writes ("Not bookable" for an empty day).
- Scheduling's "Open in browser" runs the S33 bound hand-off in the default browser:
  leg 1 and the minted URL both open there (`NSWorkspace.open`), and the callback comes
  back through `.onOpenURL`, as Wave 4 proved. iOS opens both in one in-app Safari sheet,
  which a Mac does not have, so the Mac cannot see leg 1 render a page or close; the
  flow's own timeout is the only signal (`SchedulingModel` has no `handOffStartLoaded`
  or `handOffStartClosed`).
- A recording plays in a sheet with a Done button (Esc), in the shape of a call
  recording's player; the iPad's is a bare full-height player dismissed by a swipe.
- Every scheduling write sheet is drawn by `SchedulingWriteSheet`, so the Mac sizes them
  there (520 by 600, the content scrolls) and turns their toggles into switches there,
  rather than at 29 presentation sites. Their Cancel already takes Esc and a non-destructive
  confirm ⌘↩, on iOS too (the iPad's keyboard); a destructive one takes no shortcut.
- The reschedule sheet's day is the graphical month calendar, where the iPad's compact
  picker opens one on a tap. The hours editor and the date overrides keep the iPad's text
  fields (zero-padded times and `YYYY-MM-DD` dates, which the diff and the server read).
- A booking's Cancel, Reschedule and Change host, which the iPad draws under every row,
  are drawn under the bookings table for the selected booking (a table row cannot hold
  them), with the same two gates. The booking's own screen keeps Cancel and Regenerate
  notes, as on the iPad.
- ⌘N runs the create of the screen on display when it has one (Create event type, Create
  team, Create key, Add webhook; the menu item takes the button's own words), and is New
  Message otherwise, where File > New Message stays without the shortcut
  (`ShellCommandCenter`, `districtCreateCommand`). iOS has no create for a booking (guests
  book), so there is none here.
- Connecting a Google or Microsoft calendar opens the provider's consent in the default
  browser (`BrowserHandOff`), where iOS uses an in-app Safari sheet; the providers refuse an
  embedded web view and a Mac has no in-app browser. The calendar list re-reads when the
  app becomes active again, where iOS re-reads when its sheet closes.
- A `Toggle` that the iPad draws as a switch gets `.toggleStyle(.switch)`: the macOS
  default is a checkbox, which beside a row reads as "select this" (Workflows, the Desk's
  settings, and Account's availability row). The Mac-only "Ring on this computer" and the
  Settings window's update check are switches too, so no setting is a checkbox.
- The persona audition (`PersonaPreviewEngine`) has no `setSpeakerphone`: iOS asks for the
  loudspeaker over the earpiece and a Mac has none; the engine applies the speaker picker's
  choice at the join, as a room does. A preview ended by sleep gets its own sentence.
- A list row (``DistrictListRow``) puts its badges under the text when the title does not
  fit beside them (``DistrictRowLayout``), where the iPad always puts them beside it and
  truncates the title; Support's and the Overview's rows also keep the date whole. In the
  contacts table a contact's badges sit under the name, a transfer outcome stacks over the
  status in the call log, and the Added column shows the day (Sean's first build, 20019).
- Four Mac-only differences in what a screen shows, each from that build: an avatar takes
  initials from letters only and draws a person glyph for a number or no name (the iPad
  draws "+" or "·"); Rooms offers "Read the minutes" only when the meeting has minutes (the
  iPad offers it under "No minutes were saved", and the cost is that a transcript whose
  minutes failed to generate is not reachable from the row); Devices names the platform
  ("macOS", not "macos") and formats "Last active" as a date (the iPad prints both as
  sent); the booking link's `ShareLink` takes its sibling's button style.
- Em and en dashes are taken out of comments (the public-hygiene check forbids them). A
  string the user reads that holds one keeps it as an escape (`"\u{2014}"`), so the copy
  stays byte-identical to iOS. Inside a raw JSON test string the escape is JSON's
  (`\u2014`), because Swift does not interpret `\u{...}` there.

## Two settings surfaces, split by owner

The iPad has one settings surface, the workspace hub. The Mac has two, and they do not
overlap:

- **Workspace settings** (the sidebar section) is the iPad's hub, ported whole. Everything
  on it is stored by the server for one workspace and is the same on every device signed
  in to it: persona, capabilities, how calls are answered, the transfer directory, the
  dynamic persona rules, the knowledge base, messaging and members.
- **The Settings window** (District AI > Settings..., Cmd-,; Wave 6) holds this
  installation's preferences, kept in this Mac's defaults: "Ring on this computer", the
  microphone and speaker, the notifications line and, in the Developer ID build, updates.

Account's "Calls to you" stays in Account, as on the iPad: it is whether this PERSON can
be rung (a server-side membership flag), while "Ring on this computer" is whether this Mac
rings when they can.

## The brand tint

iOS publishes the District tint once, at its root (`.districtTheme()` in `RootView`). The
Mac does the same at `RootView`, and again at the roots of the two other windows (the
Settings window and the ring panel), because a window is its own root and does not inherit
the main window's environment. Without it, SwiftUI's own controls (switches, prominent
buttons, progress, the sidebar's symbols) drew the system accent beside correctly themed
custom components.

## The sidebar on a Mac

The shell keeps the iPad's shape: a three-column `NavigationSplitView` for a list section
and a two-column one for everything else, swapped by an `if`. Sean's first real build
(20019) showed what that costs in a real Mac window, and each point below was read off the
live `NSSplitView` and `NSToolbar` with the harness described in the next paragraph:

- **The sidebar vanished in every list section, with no way back.** The shell reset the
  visibility to `.automatic` on every change of column count. On macOS `.automatic` is
  `.doubleColumn` (it prints as `kind: doubleColumn, isAutomatic: true`, and `==` compares
  the kind alone), and in three columns `.doubleColumn` is content and detail with no
  sidebar. The shell now stores the person's choice as a `Bool` (`@SceneStorage`) and
  `ShellColumns` translates it for each split view: shown is `.all`, hidden is
  `.doubleColumn` in three columns and `.detailOnly` in two.
- **The window keeps one `NSToolbar` across the swap.** After the first swap the split
  view's own sidebar button was an empty 10pt item, and the title sat over the collapsed
  sidebar in a box of its colour. The system button is removed
  (`.toolbar(removing: .sidebarToggle)`, which must come before the sidebar's column width
  or the width is lost) and the shell draws its own, and View > Show Sidebar (Control-
  Command-S) is the shell's command rather than `SidebarCommands`.
- **A stack replaced by a non-stack leaves its pushed screen on display.** A contact
  opened from a call stayed beside the Contacts table after switching section (this was
  on `main` too). The open-row column is now always a `NavigationStack`, the placeholder
  included, identified by section and row.
- **One two-column split view with an `HSplitView` for the list and the open row was
  built and rejected**: the split view adopts every `NavigationStack` in its detail column,
  so a screen pushed in the open row covered the list.

The tables' widths are measured the same way (`ListColumnWidth`): a table needs its
columns' minimums plus 17pt of cell spacing each and 15pt of row inset, or it scrolls
sideways, and it does not shrink its columns to the frame it is first drawn in.

These were verified with a temporary harness (never committed) that draws the real
`ShellView` in the app's real `WindowGroup`, fed by the core's contract fixtures, launched
in the background (`open -g`) so it never takes focus, and captured with
`screencapture -l`. The offscreen harness of Waves 5 to 9 rendered the shell into a
window of its own outside the scene, and saw none of this.

## A list section reads once

With no workspace yet, the shell draws a list section (Desk, Support, and the three tabs)
in its whole-column layout behind the workspace gate. The update that resolves the
workspace also flips the shell to three columns, and the gate used to build the section's
screen in that same update, so a second Desk or Support existed for a moment and its
`.task` loaded too. That happened in the real app on every reload of the workspace list
while one of them was open (choosing a workspace in the picker, a new sign-in), and in the
screenshot harness on every shot, which opens a section before the list arrives. The gate
now draws nothing for a list section, and `MacListSectionLoadTests` renders the shell with
a delayed workspace list and counts the requests (it reads two without the fix).

## Billing and Phone numbers: no purchase, no way out, in both Mac builds (and Scheduling)

The iOS billing screen states what is billed and offers nothing else: no upgrade, no plan
picker, no cancel, no card editor, no Stripe portal and no hosted-invoice link (App Store
Review Guideline 3.1.3(b)), and no sentence that names somewhere else to go (3.1.1's
anti-steering clause; `StoreCopyTests` reads every string literal under `Features` and
`Navigation`). The Mac keeps exactly that behaviour, and keeps it in the Developer ID build
too: both builds compile the same `App/Sources` under the same bundle id, so a hand-off
added "for the .dmg only" would ship to App Review as well. A Mac has one-line ways out of
the app that iOS does not (`NSWorkspace.open`, `BrowserHandOff`, `Link`), so
`MacBillingReadOnlyTests` fails on any of them under `Features/Billing`. The app is free;
no copy says "on sale".

Phone numbers follows iOS exactly. Releasing, reconfiguring, the paperwork (brand,
campaign, toll-free verification), the carrier account and the billed lookup are in the
app behind confirmations; buying a number is absent, because it is a recurring charge for a
service used in the app (3.1.1), and the core has no purchase method to call. The one
sentence about it (`MarketplaceCopy.purchaseElsewhere`) states the limit and names nowhere.
`MacBillingReadOnlyTests` applies the same no-URL rule to every file under
`Features/Marketplace`, not only its read tabs: a hand-off from any of them would be the
purchase path iOS leaves out. The Mac additions are a Close button (Esc) on a number's
sheet and Esc on a confirmation's Cancel; no submit there takes a shortcut.

Scheduling gets the same rule with the two exceptions iOS also takes out of the app (both
into a Safari sheet there, the default browser here): nothing under `Features/Scheduling`
(its subfolders included) may open a URL except the hub's hand-off into our own scheduler,
which opens exactly twice (leg 1 and the minted URL) from one function, and the calendar
connect, which opens the minted provider hand-off once. The booking link's `ShareLink` is
allowed (a share picker, as iOS's share sheet), and so are three `URL(string:)` parses that
open nothing. Nothing on the surface is a purchase. Scheduling is exempt from
`StoreCopyTests`, as on iOS.

The `StoreCopyTests` allowlist is iOS's minus the sign-in button's "Opens your browser"
disclosure, which the Mac sign-in screen does not carry. Its file-count floor is a ratchet
raised as sections land (180 with all of Wave 8; Scheduling is exempt, so Wave 9 leaves
it there).

## Tests never touch an installed copy

The test host is the app itself, launched in full: at launch it reads and writes the
standard defaults (the device id, the fresh-install ledger, the selected workspace, the
push token) and asks the keychain for a session. Under `com.distronode.district` that is
the sandbox container of an installed release copy, so a local `xcodebuild test` (or any
Debug run, or the screenshot harness) could read and rewrite a real installation's state.

The Debug configuration therefore builds `com.distronode.district.dev` (project.yml,
`settings.configs.Debug`), for both targets; the scheme tests in Debug, so the host gets a
container of its own. This was chosen over injecting an isolated `UserDefaults` suite into
every test because the risk is the launch itself, not only what a test persists: the app
delegate, the container and the revoke drain all run before any test can inject anything.
Nothing a test relies on reads the bundle id (the keychain service and defaults keys are
literals, and the ad-hoc test signature carries no keychain group). Release is unchanged:
both lanes archive `-configuration Release`, and `ExportOptions-AppStore.plist`,
`archive.sh` (its profile map is keyed by the release id) and `direct-package.sh` never
see a Debug build. The cost: a Debug build signed with a team gets no push and no Sign in
with Apple (the APNs topic and the Apple audience are the release id), so those are proved
on Release builds, as Wave 4.2 did. `MacTestIsolationTests` pins the id and the container.

## How the call path is adapted

iOS rings with a VoIP push and draws the ring with CallKit; this Mac rings over the
telemetry socket while the app is open and draws the ring itself. So, on top of the rules
above:

- **No CallKit.** `CallStack` keeps the engine (one LiveKit `Room` per call) and the mutual
  call and room claims, and loses the `CXProvider` and the `AVAudioSession` coordinator. The
  call claim (`claimCall` and `releaseCall`) is the model's lifetime anchor, where iOS uses the
  closure it installs in `CallKitBridge.onSystemRequest`. `CallKitRequest` has no Mac
  counterpart: mute goes straight to the reducer, the notification's buttons reach the
  incoming model through the app delegate, and sleep, quit and sign-out end a call through
  `CallStack.endEverything(_:)`.
- **The reducers are unchanged.** `SoftphoneSession` and `IncomingCallController` in
  district-core-swift decide everything, as on iOS. The commands that tell CallKit something
  (`reportCallEnded`, `reportCallActive`) are no-ops here, and `startRinging` and
  `stopRinging` drive the Mac's own ring.
- **The ring's source is `DistrictLive.DesktopRingGate`.** A gate `stopRinging` ends only a
  ring that is still ringing. A ring the call ended (`call_ended`, or a `call_updated` the
  answer route would refuse) goes through the reducer's timeout exit, which sends nothing,
  and is worded as the caller hanging up (iOS never learns this; CallKit rings on).
- **No speaker toggle.** A Mac has no earpiece. The output and input pickers go through
  LiveKit's `AudioManager` (`AudioDevices`); `CallEngine.setSpeakerphone` is a no-op and no
  control sends it.
- **No microphone question at landing.** Every Mac answer is a press with the app running,
  so the question is asked at the press (dial or Answer), never at the first signed-in
  screen.
- **The dial goes out after the microphone answer.** iOS places it only once CallKit has
  performed its start action, with a ten-second watchdog for a start that never comes; the
  Mac has neither, so `DialerModel` has no `startTimeoutSeconds`, no `notStarted` sentence
  and no `endedReason(for:)`. The carrier hang-up is unchanged and also kept by `CallStack`,
  so quitting mid-call waits up to three seconds for it.
- **Rooms without the audio session, the flip or the speaker.** iOS hands `AVAudioSession`
  back to LiveKit when a room joins; a Mac has none. A Mac has one camera facing the person,
  so there is no Flip camera, and no earpiece, so the room's Speaker on/off is replaced by
  the microphone and speaker pickers. The video tile is an `NSViewRepresentable` over the
  same `VideoView`. Sleep yields a room like a call does (`RoomAudioYield.sleep`).
- **One sandbox key iOS does not need: `com.apple.security.network.server`.** WebRTC binds
  its own UDP sockets for ICE and the macOS sandbox grants `bind` only with it; LiveKit's own
  sandboxed test host claims it too. It is a sandbox entitlement, not a profile-granted one.

## Copy

Every user-visible string is the iOS app's, word for word. The iOS app is English only:
its one `Localizable.strings` holds the six notification strings, which this app already
carries, and there are no other localisations to port. Where a sentence has to differ on
a Mac, the line carries a `⚠️` comment saying why, and the matching test is changed with
it. So far: the notifications line and the dialler's microphone refusal say "System
Settings" where iOS says "iOS Settings" or "Settings"; the emergency-number hand-off says
"Use a phone to call for help." where iOS names "the Phone app" (a Mac has none); and the
call-backs' empty state says "one click" where iOS says "one tap". Wave 7's screens needed
no change of words; its one Mac-only string is the Desk logo's "Choose file". Wave 8 adds
one: the persona preview's "This Mac went to sleep, so the preview was ended.", in the
shape of its "A call arrived on this device" line.
Wave 9 changes no words; its Mac-only strings are the scheduling tables'
column headings, which are the web dashboard's (`BookingsTable`, `EventTypesTable`), and
the recording player's "Done", which the call recording's player already says. The ⌘N
menu items reuse their buttons' titles. "Finish in the browser, then come back" (the
calendar connect's note) is iOS's sentence and is true on the Mac as written.

Mac-only copy (no iOS original) comes from district-linux where it has one, and is in the
iOS sentences' shape otherwise (a room left because the Mac went to sleep): "Ring on this
computer" and its caption (adapted to name the "Calls to you" card), the "Calls cannot ring
here right now." line, and the ring window's "Incoming call" title. The app's own ring
notification uses the APNs alert's strings (`push.call.title` and `push.call.body`), so the
two notifications a Mac can show for a call read the same. The device pickers say
"Microphone", "Speaker", "System default" and "Not connected".

## Parity checklist

The sixteen sidebar sections against the iPad app, all copied from district-ios `4777c40`
(Wave 9 completes the list). "Gaps" are the intentional differences recorded above; a
section with none is the iPad's screen with only the adaptations in "How a file is adapted".

| # | Section | Wave | Gaps (intentional) |
|---|---|---|---|
| 1 | Overview | 5 | The tab rows the Mac sidebar already offers are hidden (`hidingEntryPoints`), as on the iPad's sidebar. |
| 2 | Inbox | 5 | A tapped message notification does not open its thread (push taps not ported). |
| 3 | Calls | 5 | None (a sortable table where the iPad has rows). |
| 4 | Contacts | 5 | None (a sortable table); the Video call row is Wave 6. |
| 5 | District HQ | 7 | None. |
| 6 | Analytics | 7 | None. |
| 7 | Phone numbers | 8 | No purchase, as on iOS (Guideline 3.1.1); nothing opens a URL. |
| 8 | Billing | 7 | Read-only, as on iOS (3.1.3(b)); nothing opens a URL, in both Mac builds. |
| 9 | Rooms | 6 | No Flip camera and no speaker toggle (one camera, no earpiece); device pickers instead. "Read the minutes" only for a meeting with minutes. |
| 10 | Workflows | 7 | None. |
| 11 | Desk | 7 | No "New ticket" entry point, as on iOS (unreachable there too). |
| 12 | Dial | 6 | No CallKit; the emergency hand-off says "Use a phone to call for help." |
| 13 | Scheduling | 9 | Both hand-offs (the scheduler, a calendar provider's consent) open the default browser where iOS uses a Safari sheet; scheduling links (`SchedulingRoutingTests` `_01` to `_09`) wait for app links. |
| 14 | Support | 7 | None (reporting a message or a call came in Wave 5). |
| 15 | Workspace settings | 8 | The persona audition has no loudspeaker request (no earpiece). |
| 16 | Account | 5 | "Ring on this computer" added (Wave 6); devices are Wave 5, with platform names and dates where the iPad prints the wire values. |

Across every section: no CallKit or VoIP push (the Mac rings over the telemetry socket while
open), and app links and push taps do not open a section yet (see "Left out on purpose").

