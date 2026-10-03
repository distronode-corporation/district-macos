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
| 5 | Design system | `4777c40` | `App/Sources/DesignSystem/` |
| 5 | Routes, role gates, list/detail paths, menu commands | `4777c40` | `App/Sources/Navigation/` |
| 5 | Accessibility identifiers | `4777c40` | `App/Sources/Accessibility/` |
| 5 | Tests for the above | `4777c40` | `App/Tests/`, under the iOS file names; Mac-only tests are named `Mac*` or `test_MAC_*` |

`4777c40` is district-ios commit `4777c40b032ecb437ede22060b71b754cebe6610` ("Adopt
district-core-swift 2.0.0").

The sections not listed here are still placeholders (`ComingLaterView`); the wave that
ports each one is `SidebarItem.portedInWave`.

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
- Mac idioms are added where they are natural: `Table` with sortable columns for long
  lists, menu commands with keyboard shortcuts (File > New Message, Edit > Search
  Messages, View > Refresh, Go), and a toolbar Refresh button standing in for
  pull-to-refresh.
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
