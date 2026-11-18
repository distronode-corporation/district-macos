# Roadmap

The near-term plan for District AI for Mac. This repository has no open issues, so the list is
taken from its open pull request and its own unfinished items, each named with where it comes
from. It has no dates: an item is done when the change that does it is merged and released, and
it then leaves this list for [CHANGELOG.md](CHANGELOG.md). Anything here can change; open an
issue to discuss an item or to propose a new one.

## Near term

- **Release what is merged.** Account deletion in the app, two-step verification settings and
  the setup wizard in the app are merged and listed under `[Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md), with DistrictCore 8.6.0. The plan is to ship them in the next
  release, on Releases, Homebrew and the Mac App Store.
- **Hardening from the deep security scan.** One open pull request: ending a room join that a
  leave or an audio yield lands inside
  ([#115](https://github.com/distronode-corporation/district-macos/pull/115)).
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
