# Architecture

District AI for Mac is a SwiftUI app. `project.yml` (XcodeGen) is the project:
the `.xcodeproj` is generated and never committed.

## Layers

```
App/Sources            SwiftUI app: screens, navigation, session, platform glue
  |  Swift packages, pinned exactVersion in project.yml
  v
DistrictCore           district-core-swift: DistrictModel, DistrictAuthCore,
                       DistrictNetwork, DistrictData, DistrictCall, DistrictLive,
                       DistrictL10n (shared with district-ios, tested on Linux there)
LiveKit                calls (WebRTC)
Sparkle                updates, DistrictMacDirect only
```

The app holds UI and macOS-specific code. Models, the API client, repositories,
auth, call state and localization live in DistrictCore.

## Targets

| Target | Type | What it is |
| --- | --- | --- |
| `DistrictMac` | application | The Mac App Store build. Never links Sparkle. |
| `DistrictMacDirect` | application | The Developer ID build (notarised .dmg, Homebrew). Adds `App/Direct/` and Sparkle. |
| `DistrictMacTests` | unit-test bundle | `App/Tests/`, hosted by `DistrictMac` (`@testable import`). |
| `DistrictMacUITests` | UI-test bundle | `App/UITests/`. CI runs only `LaunchSmokeTests`; the store screenshots run by hand. |

Both app targets come from one template (`DistrictMacApp` in `project.yml`), so
they share sources, resources, packages and settings, and both build
`District AI.app`. Schemes: `DistrictMac` (build and unit tests),
`DistrictMacDirect` (build only), `DistrictMacScreenshots` (UI tests).

## App/Sources

| Directory | What it holds |
| --- | --- |
| `DistrictMacApp.swift`, `RootView.swift` | Entry point (`@main`) and the root view. |
| `AppContainer*.swift` | The object graph, wired by hand. Holds the one `TokenRefreshCoordinator`. |
| `Session/` | Signed-in session and workspace selection models. |
| `Navigation/` | Routes, sidebar, the shell's columns and commands, push and app-link routing. |
| `Features/` | One folder per area (Inbox, Calls, Scheduling, Settings, ...). |
| `DesignSystem/` | Shared views, type, theme and layout helpers. |
| `Platform/` | macOS glue: app delegate, push registration, menu bar, call engine (LiveKit), live telemetry. |
| `Accessibility/` | Accessibility identifiers, shared with the UI tests. |
| `L10n/` | App language, plus `Generated/Copy.swift` from `l10n/` by `scripts/gen-l10n.py`. |

Auth entry points sit at the top level: `WebAuthLoginController.swift`,
`AppleSignInController.swift`, `KeychainTokenStore.swift`,
`URLSessionHTTPTransport.swift`.

## Other directories

- `App/Resources/`, `App/Localization/fr-CA.lproj/`, `App/PrivacyInfo.xcprivacy`:
  bundle resources.
- `App/*.entitlements`: per-target entitlements (`AdHoc` for CI and local builds).
- `scripts/`: release lane (archive, notarise, appcast, App Store submit) and
  repository checks, each with its test.
- `PORTING.md`: how screens are ported from district-ios.
