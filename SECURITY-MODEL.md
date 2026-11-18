# Security model

District AI for Mac holds a District AI session and shows a workspace's calls, messages and
contacts; it rings for calls handed to you, places and answers calls, and joins rooms. It ships
two ways: a Developer ID `.dmg` that updates itself with Sparkle, and the Mac App Store. This
document says what it protects, who it defends against, what it trusts, and how the code holds
each line. The control-by-control summary is "What the app does to protect you" in
[SECURITY.md](SECURITY.md#what-the-app-does-to-protect-you).

Much of what follows is enforced in
[district-core-swift](https://github.com/distronode-corporation/district-core-swift), the
DistrictCore package this app pins by `exactVersion` in `project.yml` (8.6.0 as of this
writing), which has its own
[SECURITY-MODEL.md](https://github.com/distronode-corporation/district-core-swift/blob/main/SECURITY-MODEL.md).
Where a test lives there, the table says "core:" before its path.

## Assets

- **The session**: the access and refresh tokens, in the data-protection keychain only.
- **Customer data**: callers' numbers, transcripts, messages and contacts, which belong to the
  workspace and its customers.
- **Billed and destructive actions**: placing or answering a call, sending a message, deleting
  the account.
- **The microphone and camera**, and a call's media.
- **The update path**: the `.dmg`, its Sparkle signature, the appcast and the Homebrew cask, and
  the keys that sign them.

## Threat model

| Actor | What they can do | What stops them |
|---|---|---|
| A web page or another app | Open a `districtai://` link or try to finish a sign-in it did not start. | Sign-in in `ASWebAuthenticationSession` with PKCE (S256) and a fresh `state` per attempt; a callback with a foreign `state` is refused without spending the code; a sign-in completes once, and a second completion is ignored. |
| A thief of a refresh token, or a quit mid-refresh | Present a token that was already spent. | One refresh coordinator per process; a quit waits, up to a deadline, for a rotated token to be stored. |
| A later install, or a sign-out racing a refresh | Inherit an old session, or keep a working token. | A fresh install wipes any session left in the keychain and queues its revoke; a refresh that lands after sign-out writes nothing and its successor is revoked. |
| A tampered download or update | Install code this project did not build. | The `.dmg` is Developer ID signed and notarised, with checksums and a build provenance attestation; Sparkle verifies each update against the EdDSA key built into the app, and the app refuses updates while that key is the placeholder. |
| Other programs on the Mac | Read the app's files. | The app is sandboxed in both builds; its files are in its own container. |
| A hostile or compromised server response | Return any shape. | Strict decoding against the server's recorded responses. |
| Someone who reads crash reports | Read whatever the app sent. | Crash reporting is off in any build without a DSN; when on, `sendDefaultPii` is false and tracing is off. |
| Someone who ships a modified release | Sign and publish a build as Distronode. | No signing key or store credential in this repository or in GitHub; each release run borrows them for its own length; publishing and submission run only with the maintainers' approval. |

Out of scope, as [SECURITY.md](SECURITY.md#scope) lists: the District AI service itself, and an
attacker who already controls the Mac or the user's account on it.

## Trust boundaries

| Party | Trusted? | Why |
|---|---|---|
| The person at the keyboard | **Yes** | Every billed or destructive action waits for their click. |
| macOS, the keychain and the sandbox | **Yes** | They hold the tokens and confine the app. |
| The District AI service | Yes, for what it answers about the account | It authorises every request; the app's role checks are a courtesy. |
| Other apps, web pages and links | **No** | Sign-in needs PKCE and `state`. |
| Updates and the appcast | **No**, until verified | Sparkle checks the EdDSA signature against the key in the app. |
| Customers, callers and model output | **No** | Shown as text. |
| The network | **No** | App Transport Security's defaults (HTTPS only). |

## Secure design principles applied

- **Least privilege.** The sandbox grants the network, the microphone, the camera and reading
  the files you pick, nothing else (`project.yml`, `entitlements`); no file you chose is ever
  written. Sparkle is compiled into the Developer ID build only (`App/Direct`).
- **Fail closed.** A callback with a foreign `state` is refused before the code is spent; the
  app refuses updates while the Sparkle key is the placeholder, and the release preflight
  refuses to build with it; an archive whose binary carries the UI-test hooks is refused.
- **Complete mediation.** Every request goes through DistrictCore's one client and one refresh
  coordinator; the service authorises each one.
- **Economy of mechanism.** DistrictCore holds the logic; this repository adds the AppKit and
  SwiftUI layer and the Darwin adapters behind the core's protocols.
- **Safe defaults.** A build from a plain checkout reports no crashes; the UI-test session hook
  compiles only in Debug and keeps its session in memory, never in the keychain.
- **Separation of secrets.** The session only in the keychain, never synchronised; release
  credentials only borrowed by the release jobs.

## Assurance case

Each control is held by a test CI runs on every pull request
([.github/workflows/ci.yml](.github/workflows/ci.yml)), a test the release workflow runs before
it builds, a test in DistrictCore's CI at the pinned release, or, where no test can hold it,
says so. Weaknesses are mapped to the CWE Top 25 and the OWASP Top 10.

| Weakness | How it is countered | Tests |
|---|---|---|
| Authentication bypass by a forged callback (CWE-287, CWE-352) | PKCE (S256), a fresh verifier and `state` per attempt, a foreign `state` refused before the code is spent, a sign-in completed once. | core: `Tests/DistrictAuthCoreTests/PKCETests.swift` (`testEveryAttemptGetsFreshSecrets`), core: `PKCEVectorTests.swift` (`testFixtureIncludesTheRFC7636ReferenceVector`), `App/Tests/ReauthSheetControllerTests.swift` (`testAForeignStateIsRefusedWithoutSpendingTheCode`), `App/Tests/MacWebAuthIsolationTests.swift` (`testASecondCallIsIgnored`) |
| Replay of a spent refresh token (CWE-294) | One refresh at a time; a quit waits for the rotated token to be stored. | core: `Tests/DistrictAuthCoreTests/TokenRefreshConcurrencyTests.swift` (`testNoTokenIsEverPresentedTwiceUnderRepeatedRaces`), `App/Tests/MacQuitRefreshTests.swift` (`test_MAC_QUIT_01_aQuitWaitsForTheRotatedTokenToBeStored`) |
| A session surviving sign-out or an uninstall (CWE-613) | A refresh landing after sign-out writes nothing and is revoked; a fresh install wipes an old session. | core: `Tests/DistrictAuthCoreTests/SignOutRaceTests.swift` (`testARefreshLandingAfterSignOutWritesNothingAndRevokesItsSuccessor`), core: `FreshInstallTokenStoreTests.swift` (`testAnOwedWipeHidesTheOldSessionAndQueuesItsRevoke`) |
| Cleartext storage of credentials (CWE-312, CWE-922) | Data-protection keychain, this device only, never synchronised. | Mechanism only: `App/Sources/KeychainTokenStore.swift`; the keychain group cannot be used by CI's ad-hoc build. |
| Download of code without an integrity check (CWE-494) | Sparkle EdDSA signature against the key in the app; the placeholder key is refused by the app and by the release preflight; publishing checks the checksums, the Sparkle signature and the attestation. | `scripts/release-preflight.test.sh` ("the scaffold's placeholder is refused", run by `release.yml` before it builds), `scripts/release-publish.test.sh` and `scripts/appcast_test.py` (CI) |
| Debug code in a release (CWE-489) | The UI-test session hook compiles in Debug only, needs both its launch argument and a session payload, and `scripts/archive.sh` refuses an archive whose binary carries it. | `App/Tests/UITestSessionTests.swift` (`testTheArgumentAloneIsNotEnough`, `testNoArgumentMeansNoSessionEvenWithAValidPayloadPresent`) |
| A server shape the client does not expect (CWE-20) | Strict decoding of the server's recorded responses. | core: `Tests/ContractFixtureTests/ContractFixtureTests.swift` (`testEveryImplementedFixturePassesTheStrictGate`) |
| A request that misnames the client (CWE-20) | Every request that names the platform says `.macos`, pinned byte for byte. | `App/Tests/MacClientPlatformTests.swift` (`testCodeExchangeSendsMacosToTheTokenRoute`) |
| Personal data in crash reports (CWE-532, OWASP A09) | No DSN, no reporting; `sendDefaultPii` false; tracing off. | Mechanism only: `App/Sources/Platform/DistrictSentry.swift`; `project.yml` ships the DSN empty. |
| Committed secrets (CWE-798) | gitleaks over the full history on every push to `main` and every pull request, with `.gitleaks.toml`. | `.github/workflows/ci.yml` (**gitleaks**) |
| Vulnerable and outdated components (OWASP A06) | Every package pinned `exactVersion`; dependency review on pull requests; the dependency graph; CodeQL over the workflows and the app's Swift; zizmor over the workflows. | `.github/workflows/ci.yml`, `codeql.yml`, `codeql-swift.yml` |
| Release credential theft (CWE-522) | No stored credential; per-run borrowing; publishing and submission need the maintainers' approval. | Mechanism only: `.github/workflows/release.yml`, `publish.yml` and `submit.yml`. |
| Improper certificate validation (CWE-295) | App Transport Security's defaults. | Mechanism only. |

## How the project is run

Who decides, who can merge and release, and how the project continues are in the
organization's
[GOVERNANCE.md](https://github.com/distronode-corporation/.github/blob/main/GOVERNANCE.md).
