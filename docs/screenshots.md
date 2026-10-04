# Mac App Store screenshots

The Mac App Store listing needs screenshots at a 16:10 size; this project produces
2880x1800 PNGs, one per main section (Overview, Inbox, Calls, Contacts and, when the account
has it, Scheduling), captured from the app signed in to Distronode's review workspace.

They come from `StoreScreenshotTests` in the `DistrictMacUITests` target, the Mac twin of
district-ios's store screenshot tests, and they are taken by a maintainer on a Mac. **CI never
runs them**: the target is only in the `DistrictMacScreenshots` scheme, CI runs only
`LaunchSmokeTests` from it (the same launch on a made-up session and a closed loopback port,
so it reaches no server), and the screenshot case skips when the run carries no session.

## How the app is signed in

There is no password anywhere in this flow. A maintainer mints a session for the review
account with Distronode's internal tooling (`mint-native-session.ts`, the same mint the iOS
screenshots use) and the run hands it to the app through the environment:

- the app is launched with `-UITestSession` and `DISTRICT_UITEST_SESSION` set to the mint's
  JSON (the five `/api/auth/native/token` keys plus `deviceId`);
- `UITestSession` reads it, and the container adopts it into an **in-memory** token store,
  never the keychain;
- the seam is `#if DEBUG`, so it does not exist in a Release build, and `scripts/archive.sh`
  refuses an archive whose binary contains the string `DISTRICT_UITEST`.

⛔ **One mint, one run.** The refresh token is single-use; a second launch replays it and the
server revokes the whole session. Mint again for every run, and revoke afterwards.

## Steps (a Mac with a Retina display)

The frames are the app's window at 1440x900 points, so they are 2880x1800 only on a 2x
display (any Retina Mac, or an external display in a "looks like" mode at 2x). The case fails
on any other size rather than writing a wrong set.

1. Install the tools at the versions in the README (Xcode 26.3, XcodeGen), generate the
   project and resolve its packages:

   ```sh
   xcodegen generate --spec project.yml
   xcodebuild -resolvePackageDependencies -scmProvider system \
     -project DistrictMac.xcodeproj -scheme DistrictMacScreenshots
   ```

   ⚠️ `-scmProvider system` (here and in step 3) makes Xcode fetch packages with the
   system `git`. Without it, a run on a Mac has hung for over half an hour in Swift Package
   Manager's manifest loading before building anything.

2. Mint a session for the review account and save the JSON to a file outside the repository,
   readable only by you (`chmod 600`). Note its `deviceId` for step 5.

3. Run the screenshot scheme, with the session and an output folder exported to the test
   runner (`TEST_RUNNER_` is stripped on the way in). Export them as environment variables:
   a value passed as a trailing `NAME=value` build setting does not reach the runner.

   ```sh
   export TEST_RUNNER_DISTRICT_UITEST_SESSION="$(cat /path/to/session.json)"
   export TEST_RUNNER_DISTRICT_STORE_SCREENSHOTS_DIR="$HOME/Desktop/district-mac-screenshots"
   xcodebuild test \
     -project DistrictMac.xcodeproj \
     -scheme DistrictMacScreenshots \
     -destination 'platform=macOS' \
     -scmProvider system \
     -resultBundlePath "$HOME/Desktop/district-mac-screenshots.xcresult" \
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
     CODE_SIGN_ENTITLEMENTS="$PWD/App/AdHoc.entitlements"
   unset TEST_RUNNER_DISTRICT_UITEST_SESSION
   ```

   The first UI-test run on a Mac asks to allow UI automation (an administrator password in a
   system dialog, or `automationmodetool enable-automationmode-without-authentication` once).
   Leave the Mac alone while it runs: the case clicks the sidebar and captures the window.

   ⛔ Do not add `-ApplePersistenceIgnoreState YES` to the launch (`App/UITests/AppLaunch.swift`).
   With it the app opens no window, and the case fails after its timeout as if the session
   were bad. A run that fails with "the app opened no window" is a launch problem, not a
   session one.

4. The PNGs are in `$HOME/Desktop/district-mac-screenshots/mac-16x10/` (`1-overview.png` and
   so on). They are also attachments in the result bundle:

   ```sh
   xcrun xcresulttool export attachments \
     --path "$HOME/Desktop/district-mac-screenshots.xcresult" \
     --output-path "$HOME/Desktop/district-mac-screenshots-attachments"
   ```

   Check each one is 2880x1800 (`sips -g pixelWidth -g pixelHeight *.png`) and shows only the
   review workspace's fictional data.

5. Revoke the session with the same tooling and its `deviceId`, and delete the session file.

6. Upload the PNGs to the macOS version's en-US screenshot set (display type `APP_DESKTOP`)
   in App Store Connect.
