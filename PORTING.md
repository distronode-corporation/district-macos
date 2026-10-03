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

`4777c40` is district-ios commit `4777c40b032ecb437ede22060b71b754cebe6610` ("Adopt
district-core-swift 2.0.0").

The sections not listed here are still placeholders (`ComingLaterView`); the wave that
ports each one is `SidebarItem.portedInWave`.

## Left out on purpose, and where it goes

- **Contacts: the Video call row** (`ContactVideoCallModel`). It sends the contact a
  guest link (a metered message) and then opens the room; rooms are Wave 6, and
  inviting a customer to a room this app cannot open would strand them. It is ported
  with Rooms.
- **`SettingsChrome.swift`**: only `SettingsField` came over, because the compose sheet
  uses it. Wave 8 ports the rest of that file without it (or deletes
  `SettingsField.swift`), so there is one definition.
- **App links and push taps** (`AppLinkRouting`, `PushRouting`, `ShellView+Routing`):
  a tapped notification or a `www.distronode.com` link does not open a section yet.

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

## Copy

Every user-visible string is the iOS app's, word for word. The iOS app is English only:
its one `Localizable.strings` holds the six notification strings, which this app already
carries, and there are no other localisations to port. Where a sentence has to differ on
a Mac, the line carries a `⚠️` comment saying why, and the matching test is changed with
it. So far there is one: the notifications line says "System Settings" where iOS says
"iOS Settings".
