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

`4777c40` is district-ios commit `4777c40b032ecb437ede22060b71b754cebe6610` ("Adopt
district-core-swift 2.0.0").

Wave 6 also adds Mac-only parts with no iOS original: ringing over the telemetry socket
(`App/Sources/Platform/Live/`: the `URLSessionWebSocketTask` adapter for district-core-swift's
`DistrictLive`, the live session and its lifecycle, "Ring on this computer"), the ring panel,
sound and notification (`RingPanelController`, `RingPresenter`, `RingNotifications`), and the
microphone and speaker pickers (`AudioDevices`, `AudioDevicePickers`). Their behaviour follows
district-linux's desktop ringing, the one client that rang a desktop before this one.

The sections not listed here are still placeholders (`ComingLaterView`); the wave that
ports each one is `SidebarItem.portedInWave`.

Wave 7 adds Mac-only tests with no iOS original: `MacBillingReadOnlyTests` (nothing under
`Features/Billing` may open a URL, see "Billing" below), `MacAnalyticsBillingFormatTests`
(the figures a bill is read in), `MacDeskSupportWorkflowsTests` (status wording, the
support write states, trigger labels) and `MacTestIsolationTests` (see "Tests never touch
an installed copy").

Wave 8 adds Mac-only tests with no iOS original: `MacListSectionLoadTests` (see "A list
section reads once" below).

## Left out on purpose, and where it goes

- **The settings hub's Scheduling row** pushes `Route.scheduling`, as on iOS. Until Wave 9
  ports Scheduling, that route shows the same hand-off screen the sidebar's Scheduling row
  does (`SchedulingHandoffView`), not a placeholder.
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
- A `Toggle` that the iPad draws as a switch gets `.toggleStyle(.switch)`: the macOS
  default is a checkbox, which beside a row reads as "select this" (Workflows, the Desk's
  settings, and Account's availability row).
- The persona audition (`PersonaPreviewEngine`) has no `setSpeakerphone`: iOS asks for the
  loudspeaker over the earpiece and a Mac has none; the engine applies the speaker picker's
  choice at the join, as a room does. A preview ended by sleep gets its own sentence.
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

## Billing: read-only, in both Mac builds

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

The `StoreCopyTests` allowlist is iOS's minus the entries for files not ported yet (the
Marketplace's A2P website field, Wave 8; the Desk's logo sentence arrives with the Desk) and
minus the sign-in button's "Opens your browser" disclosure, which the Mac sign-in screen
does not carry. Its file-count floor is a ratchet below iOS's 150, raised as sections land.

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

Mac-only copy (no iOS original) comes from district-linux where it has one, and is in the
iOS sentences' shape otherwise (a room left because the Mac went to sleep): "Ring on this
computer" and its caption (adapted to name the "Calls to you" card), the "Calls cannot ring
here right now." line, and the ring window's "Incoming call" title. The app's own ring
notification uses the APNs alert's strings (`push.call.title` and `push.call.body`), so the
two notifications a Mac can show for a call read the same. The device pickers say
"Microphone", "Speaker", "System default" and "Not connected".
