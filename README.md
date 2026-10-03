# District AI for Mac

The native macOS client for [District AI](https://www.distronode.com/district-ai), the AI
receptionist service by Distronode. It is being built to match the iPad app section for
section: calls placed and answered on the Mac, the inbox, contacts, meeting rooms and the
settings of a District AI workspace.

**Status: in development, not released.** This build signs in and shows the Overview and
your Account and devices; the other sections say which later wave ports them. Nothing
is on the Mac App Store or in a GitHub Release yet. See [CHANGELOG.md](CHANGELOG.md).

This repository is the client's complete source, under the Apache License 2.0. The
District AI service it talks to is not open source; signing in needs a District AI
account. Without one you can still build the app and run its unit tests.

**Without an account with us.** Today this app needs a District AI account to sign in. We
want the District AI apps to work without an account with us too. We have not worked out
what that looks like or whether it can work, and the answer depends on what people would
use them with, so we are asking before we build anything:
[tell us what you would connect them to](https://github.com/distronode-corporation/.github/discussions/1).

SwiftUI, Swift 6 language mode, macOS 14 Sonoma and later, one universal app for Apple
silicon and Intel Macs.

## Two ways to install it, once released

- **The Mac App Store.** The Mac app shares its App Store record with District AI for
  iPhone and iPad, so it is one purchase across all three, and the App Store updates it.
- **A direct download.** A Developer ID signed and notarised `.dmg` on this repository's
  GitHub Releases, which keeps itself up to date with
  [Sparkle](https://sparkle-project.org). The same build is in our Homebrew tap:

  ```sh
  brew install distronode-corporation/tap/district-ai
  ```

**Install one, not both.** The two builds are the same app (one bundle identifier), so
they share their settings, their saved session and the `districtai://` links; installed
side by side, either one may answer a link or a notification. Neither is available yet.

## Requirements

- macOS with **Xcode 26.3** (CI selects exactly this version)
- **XcodeGen 2.46** or newer (the Xcode project is generated from `project.yml`)
- Deployment target **macOS 14.0**
- For linting: **SwiftFormat 0.63.0** and **SwiftLint 0.65.1**, the versions CI pins

The models, API client, repositories and auth logic live in
[district-core-swift](https://github.com/distronode-corporation/district-core-swift),
the core shared with the iOS app, which builds and tests on Linux too.

## Build and test

```sh
xcodegen generate --spec project.yml

# The Mac App Store target, and the Developer ID target (the same app plus Sparkle).
# Signed ad hoc: the project carries no team, certificate or provisioning profile.
for scheme in DistrictMac DistrictMacDirect; do
  xcodebuild build -project DistrictMac.xcodeproj -scheme "$scheme" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
done

# The unit tests, with the ad-hoc entitlements (see below).
xcodebuild test -project DistrictMac.xcodeproj -scheme DistrictMac \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS="$PWD/App/AdHoc.entitlements"
```

Two things that are expected, not broken:

- **An ad-hoc build carrying the real entitlements will not launch.** Push, Sign in with
  Apple, associated domains and the keychain group must come from a provisioning
  profile, and macOS refuses to start an ad-hoc signed app that claims them. To run the
  app or its tests without our signing team, sign it with
  [`App/AdHoc.entitlements`](App/AdHoc.entitlements) (the sandbox and device keys only),
  as the test command above does. The absolute path matters: a relative one is resolved
  inside each Swift package too.
- **Such a build stops at "Try again", not "Sign in".** Without the keychain group the
  app cannot read the keychain, so it cannot tell whether a session exists.

### Lint and hygiene

From the repository root:

```sh
swiftformat --lint .
swiftlint --strict
python3 scripts/check-public-hygiene.py --self-test
python3 scripts/check-public-hygiene.py
```

The hygiene check fails on an em or en dash, an internal host name or a GitLab URL
anywhere in the tree.

## Repository layout

```
App/
  Sources/              The SwiftUI app, compiled into both targets: Navigation/ (the
                        sidebar), Features/<Name>/, Session/, Platform/ (push, Sentry)
  Direct/               Sparkle. Compiled into DistrictMacDirect only
  Resources/            The notification strings
  Tests/                DistrictMacTests
  PrivacyInfo.xcprivacy The App Store privacy manifest
  AdHoc.entitlements    The entitlements an ad-hoc build is signed with
project.yml             The XcodeGen spec: this is the project; the .xcodeproj is
                        generated and never committed
scripts/                The public-hygiene check
```

`App/DistrictMac.entitlements` and `App/DistrictMacDirect.entitlements` are written by
`xcodegen generate` from `project.yml`; edit the spec, not the files.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` and
every pull request, and uses no secrets:

- **lint** (Linux): SwiftFormat and SwiftLint.
- **hygiene** (Linux): the public-hygiene check and its self-test, and the licence files.
- **gitleaks** (Linux): the full git history, with [`.gitleaks.toml`](.gitleaks.toml).
- **zizmor** (Linux): static analysis of the workflows.
- **app** (macOS, Xcode 26.3): generates the project, builds both targets for testing and
  runs `DistrictMacTests`. While the repository is private it runs only when started by
  hand, because private macOS minutes are billed at ten times the Linux rate.

[`codeql.yml`](.github/workflows/codeql.yml) and
[`scorecard.yml`](.github/workflows/scorecard.yml) run once the repository is public.

## Releases

Not yet. Releases will be built from a protected `v*` tag on GitHub-hosted macOS
runners, with no signing key or store credential stored in this repository or in
GitHub, and submitted to the App Store and published here only with the maintainers'
explicit approval. Builds from a fork report no crashes: crash reporting (Sentry) starts
only when a DSN is supplied at build time, and `project.yml` ships it empty.

## Contributing, security and conduct

- [CONTRIBUTING.md](CONTRIBUTING.md): the local gate and the rules CI enforces.
- [SECURITY.md](SECURITY.md): report vulnerabilities privately, not in an issue.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- [SUPPORT](.github/SUPPORT.md): where questions, bugs and account problems go.

Questions about a District AI account, number or bill go to
[District AI support](https://www.distronode.com/support).

## License and trademarks

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

District AI, Distronode and the District AI and Distronode logos and app icons are
trademarks of Distronode Corporation. They are not licensed under the Apache License 2.0:
a build you distribute must use its own name, icon and bundle identifier.
