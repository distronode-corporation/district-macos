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

## Left out on purpose, and where it goes

- **`SettingsChrome.swift`**: only `SettingsField` came over, because the compose sheet
  uses it. Wave 8 ports the rest of that file without it (or deletes
  `SettingsField.swift`), so there is one definition.
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
  button (the Finder's open panel) beside the Photos picker in a reply.
- Em and en dashes are taken out of comments (the public-hygiene check forbids them). A
  string the user reads that holds one keeps it as an escape (`"\u{2014}"`), so the copy
  stays byte-identical to iOS.

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

## Copy

Every user-visible string is the iOS app's, word for word. The iOS app is English only:
its one `Localizable.strings` holds the six notification strings, which this app already
carries, and there are no other localisations to port. Where a sentence has to differ on
a Mac, the line carries a `⚠️` comment saying why, and the matching test is changed with
it. So far: the notifications line and the dialler's microphone refusal say "System
Settings" where iOS says "iOS Settings" or "Settings"; the emergency-number hand-off says
"Use a phone to call for help." where iOS names "the Phone app" (a Mac has none); and the
call-backs' empty state says "one click" where iOS says "one tap".

Mac-only copy (no iOS original) comes from district-linux where it has one, and is in the
iOS sentences' shape otherwise (a room left because the Mac went to sleep): "Ring on this
computer" and its caption (adapted to name the "Calls to you" card), the "Calls cannot ring
here right now." line, and the ring window's "Incoming call" title. The app's own ring
notification uses the APNs alert's strings (`push.call.title` and `push.call.body`), so the
two notifications a Mac can show for a call read the same. The device pickers say
"Microphone", "Speaker", "System default" and "Not connected".
