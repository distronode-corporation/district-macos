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

### Added

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
- Sign in with Apple (Mac App Store build) asks for the authenticator code when the account
  has one turned on: a sheet takes the 6-digit code or a recovery code, keeps the sheet open
  for a wrong code, and sends a timed-out step back to the Apple button. The Developer ID
  build has no native Apple door, so it never shows the sheet.

### Changed

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

### Release process

- The Developer ID build can be published: `publish.yml` (called by `release.yml` on an
  approved tag, or dispatched for a tag built earlier) makes it an immutable GitHub
  Release with its Sparkle signature, checksums and provenance attestation, and adds it
  to the appcast in distronode-corporation/updates. A `dry_run` checks all of it and
  publishes nothing.

## [2.0]

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

## [1.0]

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
