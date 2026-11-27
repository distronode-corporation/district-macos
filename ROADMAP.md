# Roadmap

The near-term plan for District AI for Mac. The list is taken from this repository's open issues
and pull requests and its own unfinished items, each named with where it comes from. This roadmap covers the next twelve months, to November 2027. Items have no dates of
their own: an item is done when the change that does it is merged and released, and it then
leaves this list for [CHANGELOG.md](CHANGELOG.md). Anything here can change; open an issue to
discuss an item or to propose a new one.

## Near term

- **Release what is merged.** Account deletion in the app, two-step verification settings,
  the setup wizard, the hardening from the deep security scan (ending a room join that a leave
  or an audio yield lands inside,
  [#115](https://github.com/distronode-corporation/district-macos/pull/115)), the fixes from
  [#129](https://github.com/distronode-corporation/district-macos/issues/129) (the reschedule
  calendar in French, the month and minutes written out in English, HQ's Markdown, a release's
  warnings) and the repeatable build are merged and listed under `[Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md). The plan is to ship them in the next release, on Releases,
  Homebrew and the Mac App Store.
- **DistrictCore 9.0.0.** One open pull request moves the app to the shared core's 9.0.0 release,
  with its sign-in fixes and the server's updated contracts
  ([#119](https://github.com/distronode-corporation/district-macos/pull/119)).
- **A serialised keychain token store.** `KeychainTokenStore` does not yet serialise its
  operations, which the shared core's `TokenStore` contract requires, so two writes can reach
  the keychain out of order. The plan is to put one serialisation around every member
  ([#118](https://github.com/distronode-corporation/district-macos/issues/118)).
- **Crash reporting after launch.** Crash reporting is off in this build: the Sentry SDK could
  not be made repeatable (its static framework changed the app binary from one link to the next,
  and its dynamic one adds about 47 MB), so it was removed until after launch. The plan and the
  options for bringing it back are in
  [#146](https://github.com/distronode-corporation/district-macos/issues/146).
- **The Intel slice on the default linker again.** The repeatable build links the Intel slice
  with the classic linker, because the default one (Xcode 26.3) ordered two equal GOT entries
  differently from one link to the next. The classic linker is deprecated; the plan is to move
  back once a new Xcode's linker passes the repeatable job twice in a row
  ([#153](https://github.com/distronode-corporation/district-macos/issues/153)).
- **Snapshot tests that settle before they draw.** Three snapshot tests can catch a screen
  before it settles: the supervise note box
  ([#149](https://github.com/distronode-corporation/district-macos/issues/149)), the
  authenticator code sheet's verifying state
  ([#154](https://github.com/distronode-corporation/district-macos/issues/154)) and the ring's
  end racing its caller lookup
  ([#156](https://github.com/distronode-corporation/district-macos/issues/156)). The plan is to
  make each one wait for its state, so a red run always means a changed screen.
- **Coverage kept at 80 percent or more.** The app's own code measures 81.57 percent line
  coverage (xccov, [#155](https://github.com/distronode-corporation/district-macos/pull/155)),
  and CI's floor is raised to 80
  ([#157](https://github.com/distronode-corporation/district-macos/pull/157)). The screens and
  paths still untested are filed as issues #133 to #136, #139 to #141 and #151, and two limits of
  the snapshot harness as #137 and #147.
- **Screenshots in the README.** The README has a marked place for a screenshot of the app; it
  is to be captured on a Mac the way [docs/screenshots.md](docs/screenshots.md) describes.

## Known limits, not planned

- **A number typed without its trunk prefix in Dial** can lose a leading digit when that digit
  equals the prefix. Only Belarus, the UK and Lithuania check a prefix against libphonenumber's
  number patterns; modelling every country's pattern is left out, and the line under the field
  shows the whole number before Call ("Known limits" under `[Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md)).

## Open questions

- **Using the app without a District AI account.** Today the app needs a District AI account to
  sign in. Whether it can work without one, and what that would look like, is an open question
  we are asking about before building anything (README, "Without an account with us";
  [the discussion](https://github.com/distronode-corporation/.github/discussions/1)).

## Where the rest of the work is

The models, API client, repositories and auth logic live in
[district-core-swift](https://github.com/distronode-corporation/district-core-swift), and a
change there arrives here as a pinned release; its own plan is in that repository. The Mac app
follows the iPad app section for section ([PORTING.md](PORTING.md)), so new sections usually
land in [district-ios](https://github.com/distronode-corporation/district-ios) first.

## How the project is run

Who decides what goes on this list, and how, is in the organization's
[GOVERNANCE.md](https://github.com/distronode-corporation/.github/blob/main/GOVERNANCE.md).
