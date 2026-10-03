<!-- Thanks for the contribution. Delete any section that genuinely does not apply. -->

## What changed

<!-- One or two sentences. The diff says what; this says it in words. -->

## Why

<!-- The problem, not the patch. If it fixes an issue, link it (Fixes #123). If you saw
     it in the running app rather than reading the code, say what you saw. -->

## How it was tested

<!-- Commands you actually ran, and what they said. "Should work" is not a test.
     CI runs the same gates; see CONTRIBUTING.md for the full list. -->

- [ ] `swiftformat --lint .` (SwiftFormat 0.63.0) and `swiftlint --strict` (SwiftLint 0.65.1)
- [ ] `python3 scripts/check-public-hygiene.py`
- [ ] `xcodegen generate --spec project.yml`, then both targets built for `platform=macOS`
- [ ] `DistrictMacTests`

## Screenshots

<!-- For a visible change: before and after, in light and dark appearance where it
     differs. Use test data only; no real names, phone numbers or messages. -->

## Anything a reviewer should know

<!-- A decision you were unsure about, something you deliberately left out, or what you
     could not test (a real call, push delivery, a signed build). Saying so is useful,
     not a problem. -->
