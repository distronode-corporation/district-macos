# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions
are the app's version (`MARKETING_VERSION` in `project.yml`), the same on the Mac App
Store and the direct download.

## [Unreleased]

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
  types, hours, bookings with each booking's answers, notes and transcript, calendar
  connections, the team, recordings with their consent, settings and the developer tab.
  Bookings and event types are tables you can sort by any column, and the week's hours
  are laid out as a week. "Open in browser" opens the scheduler in your browser, signed
  in.
- Menu commands: File > New Message (Command-N) and New Contact (Shift-Command-N),
  Edit > Search Messages (Command-F), View > Refresh (Command-R) and a Refresh button in
  the toolbar, and the Go menu follows the sidebar.

### Changed

- Both builds are now named District AI.app.

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
