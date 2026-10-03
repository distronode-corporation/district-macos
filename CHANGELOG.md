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
