# Contributing to District AI for Mac

Thanks for helping. The [README](README.md) covers requirements, the layout and how to
build. This file is the rules a change has to meet.

## Where a change belongs

Most of the logic the Mac app runs (models, the API client, repositories, sign-in and
token refresh, the call state machines) lives in
[district-core-swift](https://github.com/distronode-corporation/district-core-swift),
shared with the iOS app and tested on Linux at 100% line coverage. If a change can live
there, it belongs there, with its test. This repository is the macOS shell: SwiftUI,
AppKit, the keychain, push, Sparkle and LiveKit.

## The whole local gate

This is what CI runs:

```sh
swiftformat --lint .                          # SwiftFormat 0.63.0
swiftlint --strict                            # SwiftLint 0.65.1
python3 scripts/check-public-hygiene.py --self-test
python3 scripts/check-public-hygiene.py
xcodegen generate --spec project.yml
# then both targets built, and DistrictMacTests run (the README has the commands)
```

CI also runs `gitleaks git .` (gitleaks 8.30.1) over the full history with
`.gitleaks.toml`, and zizmor over the workflows; run them locally if you have them.

## Rules CI enforces

**Style.** SwiftFormat and SwiftLint, at the versions above, from the repository root.
The two tools disagree by default about some constructs and are configured to agree;
another version can put them back at odds. SwiftLint runs with `--strict`, so a warning
is a failure, and there is no baseline file.

**No em or en dashes, internal host names or GitLab URLs**, anywhere in the tree. Use
commas, periods or parentheses. A string that must hold a dash at run time spells it as
an escape (`"\u{2014}"`).

**Tests.** A change in behaviour comes with a test that fails without it, in the core
when it can live there and in `App/Tests` when it cannot.

**The project is `project.yml`.** Never commit a `.xcodeproj`; it is generated. The two
`.entitlements` files are generated from it too: edit the spec.

**Sparkle stays out of the App Store build.** Code that imports Sparkle goes in
`App/Direct`, which only `DistrictMacDirect` compiles. Shared code that needs to know
which build it is in checks `#if DEVELOPER_ID`.

**Every request that names the client platform says `.macos`.** The core's clients take a
`ClientPlatform` that defaults to `.ios`, so a request built without one lists this Mac as
an iPhone. Each such request is built in one place in the app, with `.macos`, and
`App/Tests/MacClientPlatformTests.swift` pins its bytes: a new one gets a test there.

## Pull requests

Pull requests run [`.github/workflows/ci.yml`](.github/workflows/ci.yml), and all of it
must be green. The workflow reads no secrets, so a pull request from a fork runs exactly
the same checks.

Conventional Commits are not required. What is required is that the message says **why**:
the diff already says what.

Things CI cannot check (a real call, push delivery, a signed build) are fine to leave
untested; say so in the pull request.

## Reporting bugs and asking questions

Use the bug report form for a bug. Questions and ideas go to
[Discussions](https://github.com/distronode-corporation/district-macos/discussions), not
Issues. For anything security-relevant, do not open an issue; see
[SECURITY.md](SECURITY.md).

## Licence of contributions

By contributing you agree that your contribution is licensed under the Apache License
2.0, as section 5 of [the licence](LICENSE) provides. There is no CLA and no sign-off
requirement.
