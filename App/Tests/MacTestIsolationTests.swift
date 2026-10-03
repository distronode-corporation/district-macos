@testable import DistrictMac
import XCTest

/// The test host is never the installed app.
///
/// ⛔ THE HOST IS `District AI.app` LAUNCHED IN FULL, and at launch it reads and writes the
/// standard defaults (the device id, the fresh-install ledger, the selected workspace) and
/// asks the keychain for a session. Those live in the sandbox container, which is keyed by
/// bundle id, so a host built as `com.distronode.district` shares the container of an
/// installed release copy. project.yml gives every Debug build (the configuration the
/// scheme tests) a `.dev` suffix; this pins it, so a spec edit that dropped the suffix
/// fails here instead of quietly running the suite against someone's real installation.
/// PORTING.md, "Tests never touch an installed copy".
final class MacTestIsolationTests: XCTestCase {
    func test_MAC_ISOLATION_1_theHostIsTheDebugBundleNotTheReleaseOne() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.distronode.district.dev")
    }

    /// ⚠️ THE CONTAINER, NOT ONLY THE IDENTIFIER: the sandbox gives the host the home
    /// directory of the container its bundle id names, and that is what the defaults and
    /// every file the app writes resolve against.
    func test_MAC_ISOLATION_2_theSandboxHomeIsTheDebugContainer() {
        let home = NSHomeDirectory()
        XCTAssertTrue(home.contains("/Containers/com.distronode.district.dev/"), home)
        XCTAssertFalse(home.contains("/Containers/com.distronode.district/"), home)
    }
}
