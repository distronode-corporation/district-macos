# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions
are the app's version (`MARKETING_VERSION` in `project.yml`), the same on the Mac App
Store and the direct download.

⚠️ A version's `## [x.y]` section is its App Store release notes, word for word:
`scripts/asc_release.py` sends that section and nothing else (never `[Unreleased]`, never
the development history), and refuses one over 4000 characters. Write it for App Store
readers: what changed for them, with no Sparkle, direct-download or build details. Detail
for this repository goes under `[Unreleased]` or the history below. App Store Connect
takes no release notes for a platform's first version, so 1.0's section is checked but
not sent.

## [Unreleased]

### Fixed

- 3.0.3 (tests only): `MacDesktopLiveSessionTests` 03 and 04 wait for the socket's close
  instead of asserting it the moment `stop()` or `signOut()` returns. DistrictLive's runner
  fires the close in a task of its own, so the assertion raced it and failed CI now and then
  (main run 38858412617 on 2026-10-16, and the Sentry 9.30.1 pull request #69). The app's
  behaviour is unchanged.
- 3.0.3: a room or a persona preview that ends on its own no longer shows LiveKit's own
  text. A meeting whose room was deleted read "You were disconnected from this room. (Room
  deleted)", and the preview "The preview ended without being stopped here. Room deleted":
  the SDK's English error description passed through as the reason, English on a French
  screen too. A failed join showed the SDK's message the same way. The banner and the
  preview now always say the catalog's sentence (`rooms.state_dropped`,
  `rooms.state_failed`, `settings.preview_dropped`), and `RoomEngine` logs the SDK's text
  (`Logger`, category `Rooms`), as the call screens have done since 3.0.1. The two
  catalog entries that carried the reason (`rooms.state_dropped_because`,
  `settings.preview_dropped_because`) are removed; no string is added. Tested in
  `RoomEndWordingTests` and `PersonaPreviewStateTests`.
- 3.0.2: APNs delivery to the Mac can be diagnosed from the Mac itself. No APNs alert has
  ever reached the QA iMac, with the app running or quit: APNs answered 200 to every one
  (production, `com.distronode.district`), and apsd logged none arriving (2026-10-15 and
  10-16, 3.0.0 and 3.0.1). The app's push lifecycle is now logged under subsystem
  `com.distronode.district`, category `push`, at the default level, so `log show` keeps it.
  The log covers the authorization answer, the APNs registration, the token's length (never
  the token), the service's answer to the register, APNs and authorization failures (domain
  and code), the unregister on sign-out, and each push the running app receives (its `type`
  only). The cause of the non-delivery is not fixed here; it is still being traced.
- An answered call joins before its microphone starts. The softphone joined with LiveKit's
  concurrent microphone mode (`ConnectOptions(enableMicrophone: true)`), which starts Core
  Audio on the SDK's one serial WebRTC queue while the join builds its peer connections on
  that same queue. A slow start (VoiceProcessingIO building its aggregate device, about 5 s
  on the first answer after a launch) held the join past its 10 s transport wait: the server
  saw the session start and never become active, and the call ended "the call could not be
  connected" (3.0.1 build 20058, 2026-10-16, 05:46:05Z). `LiveKitCallEngine.connect` now
  joins with nothing published (`LiveKitCallRoom`) and then calls `setMicrophone(enabled: true)`
  once; `CallJoinGate` still holds the reducers' unmute until that publish is done, so a call
  still has exactly one microphone track. A microphone that cannot start after the join no
  longer ends anything: the call stays connected and shows muted, and Unmute tries again.
  3.0.0 joined the same way. Tested at the engine seam (`CallRoom`,
  `LiveKitCallEngineJoinTests`).
- The end screen no longer shows LiveKit's own text. A caller hanging up read "Call ended ·
  Room deleted" (the SDK's English error description, passed through as the end reason), and
  a failed join could show the SDK's message the same way. `InCallCopy.word(for:)` now always
  says the catalog's sentence for both (`wordRemoteEnded`, `wordFailed`, English and French);
  the SDK's text goes to the log (`Logger`, category `Call`). No new strings.

### Added

- New ticket on District Desk, as on iPhone and iPad (district-ios #37): a New ticket button
  in the Desk toolbar, and File > New Ticket, open the form that raises a ticket on a
  customer's behalf (a walk-in, an email), as Android, Linux and Windows already offer. It
  is offered on the same rule as theirs: a role that may write, a desk that is on and a
  queue that loaded (`DeskModel.canStartTicket`). The menu command is enabled wherever Desk
  is offered to a role that may write; it opens Desk and then the form once the desk has
  loaded, and nothing if the desk turns out to be off or unreadable. A failed submit is now
  said in the form rather than on the queue behind it.
- A live transcript on a call in progress, as on iPhone and iPad: a call's screen shows the
  conversation as it happens, then the full transcript in the same place once the call
  ends. It rides the telemetry socket the Mac already holds for ringing, as one
  subscription per watched call, sent again on every reconnect and renewal; the socket
  keeps the workspace's events, which ringing needs. With Ring on this computer off,
  watching a call runs that socket without ringing, and it stops when no call is watched.
  ⚠️ When the assistant fails mid-call (`agent_error`) the pane says "Reconnecting…" rather
  than "Call ended", also when a snapshot says so (`endedReason`), and goes live again if a
  fresh assistant takes the call. After `not_live` the screen keeps hearing the call (its
  `call_started` and `call_updated` status, its end) with no subscription, and subscribes
  again only when a signal or a load of the call row shows it in progress, at most once
  per 30 s, never on a timer. A
  second screen on a call already watched sends the subscribe again, for the fresh snapshot
  it needs.
- Read a text file into a knowledge document, as on Windows (and district-ios #38).
  Knowledge's add form has a Read a text file button that fills the title (when it is
  empty) and the text from a plain text file (.txt or .md) of up to 1 MB. Nothing is added
  until Add document. The same files are refused for the same reasons as on Windows: too
  large, empty, no text, or not plain text by its bytes (UTF-8, or UTF-16 with its mark, is
  read). `KnowledgeFileReader` is iOS's file unchanged.
- Sign in with Apple (Mac App Store build) asks for the authenticator code when the account
  has one turned on: a sheet takes the 6-digit code or a recovery code, keeps the sheet open
  for a wrong code, and sends a timed-out step back to the Apple button. The Developer ID
  build has no native Apple door, so it never shows the sheet.
- App links and notification clicks open the right section, as on iPhone and iPad. A
  `www.distronode.com/dashboard/district/...` link (through `onOpenURL` or a continued
  browsing-web `NSUserActivity`; `applinks:www.distronode.com` was already in both
  entitlements files) opens its section, switching workspace when the link names another
  one, and a page this app does not draw opens in the default browser. Clicking a message
  notification opens its conversation beside the Inbox and refreshes the list; clicking a
  call notification opens the call log. `AppLinkRouting` and `PushRouting` are iOS's,
  driven by DistrictCore's `AppLinkResolver` and `PushDeepLinks`; the scheduling link cases
  of `SchedulingRoutingTests` are ported with them.

### Changed

- Crash reporting runs on Sentry 9.30.1 (was 9.29.2), the same as District AI for iOS.
- 3.0.2, the Apple batch after 3.0.1 (the 3.0.1 visual QA's MEDIUM and LOW findings, the
  queued contrast and type items, and the French notes from the 3.0.1 round):
  - Every tinted badge clears WCAG AA. A badge's label (and an avatar's initials, and a
    desk chip's) is drawn in a chip ink, its tone moved a fifth of the way towards
    `foreground`, on the same 12% tint: the six pairs that sat between 3.91:1 and 4.44:1
    now measure 4.71:1 or better, and `DistrictContrastTests` asserts all fifty instead of
    pinning the gap. The destructive button's label takes the same ink (it was 4.20:1 on
    its own 10% tint in dark).
  - Section and field labels (`DistrictEyebrow`) are sentence case in the system face,
    with no capitals and no letter spacing, as the design system now asks (AP-011).
  - Text fields take the site's field grammar, a `card` ground inside an `input` edge,
    instead of a grey `input` fill on which the dark placeholder was 4.34:1; a field whose
    label is drawn above it no longer repeats that label as its placeholder (AP-021).
  - An empty Calls, Contacts or Inbox list fills its column instead of drawing a grey band
    across it (AP-022). Revoke key, Revoke access and Delete webhook look destructive
    rather than like plain text (AP-023). A workspace name that ends in a period no longer
    closes the Account sentence twice (AP-024). The Numbers footnote drops the second
    sentence that contradicted the first (AP-031). Every item the app adds to a system
    menu carries a symbol, as macOS 26 draws on its own items (AP-032).
  - Working hours: the two buttons say what they do (Edit working hours, Edit date
    overrides) in one style, so they no longer read as tabs.
  - French: a call length never wraps between its minutes and seconds (« 3 min 4 s »);
    the contact dossier heads the keys the vocabulary lists in the portal's words
    (« Enjeux CRM déduits », not « Core pain points »); the Inbox search field says
    « Rechercher », which fits (AP-025). A test holds every French ellipsis to U+2026
    attached to its word (« Sonnerie… » already was).
  - Sign in, Decline, Answer and the app's icon buttons carry a plain accessibility
    label, so AXDescription names them for AppleScript and other AX clients, not only
    AXAttributedDescription. VoiceOver and the visible text are unchanged.
- Calls ring with the window closed. Closing the window no longer quits District AI: it
  stays in the menu bar (Open District AI, Open at Login, Quit) and its telemetry socket
  keeps ringing. `SessionModel` checks the session and starts the ringing when the app
  finishes launching, not from a view, so a launch at login with no window rings too, and
  the app delegate takes the registrar and the call objects at launch rather than from the
  window. Open at Login (`SMAppService.mainApp`) is off until you turn it on. The app's own
  ring notification is Time Sensitive (the new
  `com.apple.developer.usernotifications.time-sensitive` entitlement, in both
  distributions), and `ring.wav` (25 s) is bundled for the server's APNs incoming-call alert,
  which since the server's 3.0 batch is Time Sensitive and names that sound. Whether that
  alert reaches a Mac where the app has quit is under investigation: in the 3.0.1 round,
  APNs accepted the pushes to the Mac's token (200) and the Mac never received them. A
  native Mac app has no VoIP push or CallKit provider, which is why the app stays running.
  Ring on this computer says so.
- Every sentence the `*Copy` enums say comes from one catalog, `l10n/macos.toml` (1,286
  entries), with English and room for Canadian French side by side, keyed as district-ios's
  `l10n/ios.toml` wherever the two apps share a sentence. `scripts/gen-l10n.py` writes
  `App/Sources/L10n/Generated/Copy.swift` from it with the vendored tools in `tools/l10n/`,
  as extensions of the hand-written enums, so every call site reads as before; the enums
  keep only their logic, which builds its text from catalog entries. CI's `l10n` job fails
  on a stale generated file or a broken catalog rule, and `StoreCopyTests` scans the
  catalog as well as the sources. English is unchanged and nothing is French: `AppL10n`
  keeps the language English until a build ships French.
- Two CalDAV sentences lose their em dash, the one deliberate change to English in 3.0's
  catalog work: "The server address must start with https://, because an app password sent
  over http:// travels in the clear." and "Finish in the browser, then come back: this page
  re-reads itself." (the same change in district-ios). The public-hygiene dash rule no
  longer exempts `l10n/` and the generated Swift, which now hold no dash.
- The rest of the app's own words joined the catalog: the inline `Text`, `Button`, `Label`,
  alert and empty-state literals of the views (new `*Copy` namespaces in
  `App/Sources/L10n/CopyNamespaces.swift` for the screens that had none), the Mac's own
  tables' column headings, menu bar commands, sidebar and Settings window, sentences that
  were joined from two pieces as whole entries with placeholders, the English plural
  ternaries as catalog plurals, and the month abbreviations from the core's calendar
  words. Money stays exactly as English shows it today; in French it goes through the
  core's `L10nFormat`. Copy read from a stored `static let` is computed now, so it follows
  the language.
- French is ready to switch on and stays off, in both builds. `project.fr.yml`, included
  only when `DISTRICT_FRENCH` is set for `xcodegen generate`, adds
  `App/Localization/fr-CA.lproj` to the Mac App Store and the Developer ID targets alike;
  the push loc-keys (`Localizable.strings`, from `l10n/push.toml`) moved from the bundle
  root, where they would shadow every `.lproj`, into `en.lproj`, beside an
  `InfoPlist.strings` for the permission prompts (`l10n/infoplist.toml`, held equal to
  project.yml). `scripts/check-bundle-l10n.sh` refuses an app with a root table, with
  `fr-CA.lproj` while French is off, or with any `fr.lproj`: CI runs it on both targets,
  `scripts/archive.sh` on both lanes' archives (deleting a refused one) and
  `scripts/direct-package.sh` before notarising. The unit tests run pinned to English,
  the Overview and settings rows, the report's Done and the block confirmations carry
  identifiers that are the same in every language, and `StoreCopyTests` scans the
  catalog's French too.
- DistrictCore 7.0.3 (district-core-swift 6b32120, tag 7.0.3), pinned by its tag: the i18n
  contracts from monorepo ac4071d14. A call's Outcome reads the portal's disposition labels
  (`callback` "Callback requested" « Rappel demandé », `escalated` "Passed to a person"
  « Transmis à une personne », `info` "Information only", `booked` « Rendez-vous pris » in
  French), and in French a workflow action's team-push and signing reasons (`no-devices`,
  `no-message`, `push-lookup-failed`, `push-not-delivered`, `signing-unavailable`) read their
  own label where they read « Autre ». swift-asn1 stays 1.7.3.
- DistrictCore 7.0.2 (district-core-swift 5d03f80, tag 7.0.2), pinned by its tag: the i18n
  contracts from monorepo ecf098046 (in French, the number status `in-use` reads « Actif »,
  the research keys `estimatedValue`, `person` and `callerIntel` take the portal's headings
  « Évaluation DGI », « Profil du contact » and « Renseignements sur l'appelant », the skip
  reasons `email-misconfigured` and `ses-missing` have labels, and the error
  `sending_domain_provider_changed` its sentence), and a French call length that never
  breaks (« 1 min 5 s », every space U+00A0). swift-asn1 stays 1.7.3. district-ios
  names the same release.
- DistrictCore 7.0.1 (district-core-swift d7bf46d, tag 7.0.1), pinned by its tag. 3.0.1 was
  built and reviewed against the 7.0.1 pull request's head, 1972dc9, by revision; the tag's
  tree is the same tree, so nothing in the app changes.
- DistrictCore 7.0.0 (district-core-swift 1292c25), the release of the three betas below
  with the reviewed v3.0 French in the core's catalog: in French, a cancelled-bookings
  view reads « Annulés » and the scheduling team roles « Administrateur » and « Membre ».
  English is unchanged.
- DistrictCore 7.0.0-beta.3: the contracts from monorepo 43eed5fd6 (French API errors,
  masculine desk statuses), the billing currency, and the portal's four booking webhook
  events. Billing amounts come from its `BillingMoneyFormat`: English exactly as before
  ("$249.00"), French naming the currency (« 249,00 $ CA », « 249,00 $ US »); the five
  billing sentences that placed a "$" around the amount no longer do. The webhook editor
  offers the four booking events, and a save keeps an event already subscribed that the
  form no longer offers. 7.0.0-beta.2: the scheduling formatters write French dates and times as the
  website does (« 12 sept. 2026, 15 h 04 », « 9 h 05 », « 1er août »), and a French range
  inside one year drops its first year; English is unchanged. 7.0.0-beta.1: the core's
  sentences come from its catalogs, every request
  sends `Accept-Language` (`en`), and errors are shown through `ApiError.localizedMessage`
  (the same sentence in English).
- DistrictCore 6.0.0: 5.0.0 (the live transcript's models, ops and reducer, and `send` on
  the socket adapter) plus `CodeExchangeResult.mfaRequired`, the Apple door's authenticator
  code step.
- DistrictCore 4.0.0. Nothing changes in the app: this Mac build handles no web links, so the
  new District Studio link section is not used here.
- The settings hub groups the receptionist's settings under District Studio, in the web's
  order, and the Voice screen is called Voice everywhere, its title before the read lands
  included. The [2.0] notes below say so for App Store readers.
- Release notes per language: What's New for every App Store localization other than English
  comes from `release-notes/<locale>/<version>.txt`, as on district-android, and a
  localization with no notes in its language stops the submission rather than showing
  English.
- The repository meets the public-repo standard: a Scorecard badge, the README and
  SECURITY.md describe the real release state, CodeQL runs one at a time per ref, pull
  requests get dependency review, and a test uses a fictional email address.
- The catalogs carry their reviewed Canadian French (fr-CA): 1,753 entries in
  `l10n/macos.toml`, `l10n/push.toml` and `l10n/infoplist.toml`, regenerated into `Copy.swift`
  and the `fr-CA.lproj` strings, so `FR_COMPLETE` is true.
- French is on, in both builds (3.0.0). `project.fr.yml` is gone: project.yml copies
  `App/Localization/fr-CA.lproj` into the Mac App Store and the Developer ID apps alike, so
  a Mac whose languages put any French first (fr-CA, fr-FR, fr-BE, fr-CH) reads Canadian
  French, and any other Mac reads English. `AppL10n` decides, as before; nothing else
  changes in English.
- The server learns the app's language. Every request says it as `Accept-Language` (`fr-CA`
  or `en`), the scheduler hand-off included, and `AccountLanguageSync` stores it as the
  account's language (`POST /api/settings` with `{"profile":{"locale":"fr"}}` or `"en"`,
  nothing else) on every completed sign-in, at a launch whose language differs from the one
  last stored, and when the language changes while the app runs, so email and the server's
  own text match the app. The last writer wins against the website's language menu. A
  failed write is tried again at the next of those, never on a timer, and a sign-out
  forgets what was stored.
- Placeholder titles never break inside a word: beside the call log at the smallest window
  the detail column is about 160 points wide, and a long French word was hyphenated.
  `WholeWordTitle` picks the largest of five fonts at which every word fits on its line.
  The sign-in screen's and the placeholder's symbols are hidden from VoiceOver, which read
  their names aloud.

### Release process

- The Mac App Store can have its own What's New for a version:
  `release-notes/<locale>/<version>-mas.txt`, English in `release-notes/en-US/`, replaces the
  CHANGELOG section and every `<version>.txt` for the store when it exists, in every language
  or none (a missing language stops the run before anything is written). The GitHub Release
  keeps the CHANGELOG section. 3.0.1 uses it: Mac 3.0.0 never reached the store, so store
  readers go from 2.0.1 to 3.0.1, and their notes open with what 3.0.0 brought. `whats-new`
  and `submit` print which source they used.
- The release guard requires the Canadian French: `DISTRICT_FRENCH` is `"YES"` for both
  lanes in `release.yml` (and for CI's own check of both targets), so
  `scripts/check-bundle-l10n.sh` refuses an app lacking `fr-CA.lproj`'s two tables, and
  any other French `.lproj` in `Contents/Resources` (`fr.lproj`, `fr_CA.lproj`,
  `fr-FR.lproj`, any case) is refused. Sparkle's own `fr.lproj`, under
  `Contents/Frameworks`, is not this app's French and is not checked.
- Submitting a version with no App Store Connect record of its own renames the platform's one
  editable version (a rejected version that was never approved, as Mac 1.0 is) rather than
  creating a second one, which App Store Connect refuses, and only upwards. A review
  submission in Unresolved Issues that carries the version is resubmitted (its rejected
  items marked resolved, then submitted again) instead of being reported as already
  submitted; when Apple refuses, the run stops with Apple's words and the App Store
  Connect step to take.
- The Developer ID build can be published: `publish.yml` (called by `release.yml` on an
  approved tag, or dispatched for a tag built earlier) makes it an immutable GitHub
  Release with its Sparkle signature, checksums and provenance attestation, and adds it
  to the appcast in distronode-corporation/updates. A `dry_run` checks all of it and
  publishes nothing.

## [3.0.2] - 2026-10-16

- Text on coloured badges, avatars and District Desk chips has more contrast and is easier
  to read.
- Section and field labels are in sentence case, no longer in spaced-out capitals.
- Text fields have a clear edge and easier-to-read placeholder text, and a field whose label
  is shown above it no longer repeats that label inside.
- An empty Calls, Contacts or Inbox list fills its column instead of showing a grey band.
- Revoke key, Revoke access and Delete webhook look like destructive actions instead of
  plain text.
- In Working hours, the Edit working hours and Edit date overrides buttons say what they do
  and no longer look like tabs.
- In French, a call's length is never split across two lines, the intelligence dossier's
  headings are in French, and the Inbox search prompt fits its field.

## [3.0.1]

- When a call is answered on another device, this Mac stops ringing and says so.
- Answering a call shows the call screen and keeps it while you are connected, instead of
  "Call ended".
- Answering a call no longer starts your microphone twice.
- Quitting District AI no longer signs you out the next time you open it.
- Once you are signed out, this Mac stops receiving that account's notifications.
- The open call or contact beside the list is wider and easier to read, and the labels on a
  selected row stay readable.
- A more compact reply box in conversations: Command-Return sends the message.

## [3.0.0]

District AI is now in Canadian French.

- Calls ring with the window closed: District AI stays in the menu bar (Open District AI,
  Open at Login, Quit) and keeps ringing. Open at Login is off until you turn it on.
- See a call's transcript live while it is in progress, then the full transcript in the same
  place once it ends.
- Raise a ticket on a customer's behalf from District Desk, with the New ticket button or
  File > New Ticket.
- Knowledge: Read a text file fills a new document's title and text from a plain text file
  (.txt or .md, up to 1 MB). Nothing is added until you click Add document.
- If your account has an authenticator app turned on, Sign in with Apple asks for its code.
- Clicking a notification opens the right place: a message opens its conversation, a call
  opens the call log.

## [2.0.1] - 2026-10-13

### Fixed

- The Billing page names your plan ("Voice Pro") instead of its internal key ("VoicePro").

## [2.0] - 2026-10-08

District Studio, Voice and live call transcripts come to the Mac.

- Your receptionist's settings are grouped under District Studio in workspace settings, in
  the same order and with the same names as on the web: Persona, Voice, call handling,
  Skills and Knowledge.
- Voice: start from a recipe, or build your receptionist's voice from its ear, turn-taking,
  brain and voice, each showing where it is processed and how quickly it answers.
- See how long your receptionist takes to say its first word before you save, from
  measured calls.
- Choose a voice, let your receptionist start speaking sooner, and fine-tune each step
  under Advanced.
- When you change your receptionist's language, a voice setup that no longer speaks it is
  adjusted to one that does, and you are told what changed.
- Persona keeps your receptionist's name, greeting, personality, language and answer
  length, with a link to Voice.
- See a call's transcript live while the call is in progress, then the full transcript in
  the same place once it ends.
- If your account has an authenticator app turned on, Sign in with Apple now asks for its
  code, as the website does. Enter the 6-digit code, or one of your recovery codes. A wrong
  code can be typed again, and if the step times out, start again with Sign in with Apple.

## [1.0] - 2026-10-04

The first release of District AI for Mac.

- Inbox: read and answer conversations, with search, drafts, image attachments, and
  reporting and blocking.
- Calls: the call log and each call's details and transcript. Calls handed to you ring
  on this Mac while the app is open, with Answer, Decline, Mute and Hang up.
- Dial: place calls from your Mac, with the country each number rings shown beside it
  and recent callers to call back.
- Rooms: start or join a meeting room with video, share a guest link, and read past
  meetings' minutes.
- Contacts: sortable tables, adding a contact, and each contact's details.
- Scheduling: your booking page, event types, hours, bookings, calendar connections and
  your team.
- Overview, Account, Workspaces and Devices, including signing devices out and deleting
  your account.
- Menu commands and keyboard shortcuts, and the unread count on the Dock icon.

## Development history before 1.0

### Added

- The Overview, Account, Workspaces and Devices screens of the iPad app, with the same
  words: the workspace header and switcher, the four headline figures and recent
  activity, Finish setting up, Calls to you, notifications status, signing devices out,
  and account deletion.
- The Inbox, Calls and Contacts screens of the iPad app: conversations, search, new
  messages, threads with drafts and image attachments, reporting and blocking; the call
  log and each call's detail; contacts, adding one, and each contact's dossier.
- The call log and contacts are tables you can sort by any column.
- The unread count on the Dock icon.
- The sidebar offers what your role can open, as on the iPad, and marks read-only
  sections.
- Calls handed to you ring on this Mac while the app is open: a small call window that
  floats above other apps, a notification with Answer and Decline, and a ring. Answer
  in either place joins the call; the call window has Mute and Hang up.
- Ring on this computer, in Account and in Settings, on by default. Ringing stops while
  the Mac sleeps, when the app quits and when you sign out, and starts again on wake.
- Choose the microphone and speaker for calls, in the call window and in Settings.
- Dial: place a call from the Mac, with the country the number rings shown beside it,
  recent callers to call back, and emergency numbers handed off rather than dialled.
- Rooms: start or rejoin a meeting room, with video tiles, your camera and microphone,
  the note-taking Companion shown, a guest link to share, and past meetings' minutes.
- A contact's Video call button, which sends them a guest link and opens the room.
- Scheduling, as on the iPad: the booking page's state and Enable, the register, event
  types, hours, bookings with each booking's answers, calendar connections, the team,
  settings and the developer tab.
  Bookings and event types are tables you can sort by any column, and the week's hours
  are laid out as a week. "Open in browser" opens the scheduler in your browser, signed
  in.
- Scheduling's editing, as on the iPad: cancel, reschedule or reassign a booking; create
  and edit event types, their hosts and questions; set weekly hours and date overrides;
  connect calendars; manage teams, branding, your profile and notifications,
  API keys and webhooks. Command-N creates on the screen that offers it (an event type, a
  team, a key or a webhook).
- Menu commands: File > New Message (Command-N) and New Contact (Shift-Command-N),
  Edit > Search Messages (Command-F), View > Refresh (Command-R) and a Refresh button in
  the toolbar, and the Go menu follows the sidebar.

### Changed

- Both builds are now named District AI.app.
- The sidebar stays on screen in every section (it vanished in Inbox, Calls, Contacts,
  Desk and Support), with a sidebar button in the toolbar and View > Show Sidebar /
  Hide Sidebar (Control-Command-S); your choice is kept as you move between sections.
- The call log and contacts tables show every column without scrolling sideways, at the
  default window size and at the smallest; the open row beside them gives way instead.
  A contact's badges sit under the name, and the Added column shows the day.
- Inbox, Support and recent-activity rows put their badges under the text when they do
  not fit beside it, so names and dates read in full.
- A caller known only by number, or with no caller ID, shows a person glyph rather than
  "+" or a dot.
- Ring on this computer, and the update check in Settings, are switches like every other
  setting.
- Rooms no longer offers "Read the minutes" for a meeting with no minutes.
- Call details no longer offer a recording, and Scheduling no longer has a Recordings
  section, a recording setting or booking notes: District AI keeps no call or meeting
  recordings, and the service no longer offers those features.
- The booking page's Share button matches Copy link beside it.
- Devices names each platform properly (macOS, iOS, Android, Linux) and shows when a
  device was last active as a date.
- A screen opened from one list section (a contact opened from a call) no longer stays
  beside another section's list.

- The app's first scaffold: a sidebar with all sixteen sections of the iPad app, sign-in
  through the website or with Apple, the Overview, and the Account page with this
  account's signed-in devices. The other sections are placeholders until they are
  ported.
- Notifications on this Mac: after sign-in the app asks for permission and registers
  with District AI as a Mac.
- Opening the scheduler's admin in your browser, already signed in.
- Two builds of the same app: one for the Mac App Store, and one for direct download
  that updates itself with Sparkle.
- The app icon, the District AI mark from the iPhone and iPad app on the Mac's icon shape.
- In the direct download, Sign in with Apple is offered on the website's sign-in page
  (beside Google and Microsoft) rather than as a button in the app.
