# Security Policy

## Reporting a vulnerability

Please report privately, not in a public issue.

- **Preferred:** GitHub's private vulnerability reporting. Open the repository's
  **Security** tab and choose **Report a vulnerability**, or go straight to
  <https://github.com/distronode-corporation/district-macos/security/advisories/new>.
- **Fallback:** email **opensource@distronode.com** if you cannot use GitHub.

Include what you did, what happened, and what you expected, with the app version (or
commit) and the macOS version. A proof of concept is welcome but not required. Never
include a real token, session or anyone's personal data; if one is part of the problem,
say where it appeared, not what it was. Test only against accounts and workspaces that
are yours.

Expect an acknowledgement within a few working days. There is no paid bug bounty; what
you get is credit in the changelog entry for the fix, if you want it.

## Supported versions

Version 1.0 is submitted to the Mac App Store and in review; the direct download arrives
with this repository's first GitHub Release. Only the current release is supported, on
both distributions (the Mac App Store and the direct download), and fixes ship in a new
release rather than being backported.

## What the app does to protect you

So a report can say which of these it breaks:

- **Sign-in** runs in `ASWebAuthenticationSession`, not an embedded web view, with PKCE
  (S256), or through Sign in with Apple.
- **Tokens** are stored only in the data-protection keychain, as
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and never synchronised, under one
  keychain access group. One refresh coordinator exists per process, because the service
  treats a refresh token presented twice as stolen.
- **The app is sandboxed**, in both distributions: network client, microphone, camera
  and files the user picks, nothing else.
- **Role checks in the app are a courtesy.** The service authorises every request.
- **No crash reporting unless configured.** Sentry starts only when a DSN is supplied at
  build time, and `project.yml` ships it empty.
- **Updates are signed.** The direct download's Sparkle updates are verified against an
  EdDSA public key built into the app, and the app refuses updates while that key is
  the placeholder in `project.yml`.

## Scope

In scope, in rough order of damage:

- A token or session reaching a log, the pasteboard, a crash report, a notification, a
  file outside the keychain, or any host other than the District AI service.
- A `districtai://` link or notification that makes the app act (place or answer a call,
  open the microphone or camera, send a message, change a setting) without the user
  doing it.
- One workspace's data shown under another workspace, or after sign-out.
- The microphone or camera staying live after the user ended a call or left a room.
- An update path (Sparkle, the appcast, the Homebrew cask) that installs code not built
  and signed by this project.

Out of scope for this repository:

- The District AI service itself. Its vulnerabilities are still welcome at the address
  above, but its code is not here.
- Anything that needs an attacker who already has the unlocked Mac and the user's
  account password.
- A control the app shows to a role that the service then refuses (see above).
