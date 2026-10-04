@testable import DistrictMac
import XCTest

/// Ported from district-ios with the window-size cases added.
///
/// ⛔ THIS PINS PROOF (b) OF THREE THAT THE UI-TEST SEAM CANNOT ARM ITSELF BY
/// ACCIDENT. (a) is structural: the whole of `UITestSession` is inside `#if DEBUG`,
/// and `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` is set on the Debug
/// configuration only, verified against the generated pbxproj rather than assumed.
/// (c) is `scripts/archive.sh` refusing an archive whose binary contains the string
/// `DISTRICT_UITEST`. This file covers the middle: that BOTH halves are required at
/// runtime, so neither a stray launch argument nor a stray environment variable is
/// enough on its own.
///
/// ⚠️ THE TWO-HALVES RULE IS NOT BELT-AND-BRACES. Each half occurs by accident in
/// the wild: CI images carry unrelated variables, and a scheme can keep an argument
/// somebody added months ago. Requiring the pair is what makes an accident inert.
final class UITestSessionTests: XCTestCase {
    private static let validPayload = """
    {"tokenType":"Bearer","accessToken":"a","accessTokenExpiresAt":1,\
    "refreshToken":"r","refreshTokenExpiresAt":2,"deviceId":"dev-1"}
    """

    func testNoArgumentMeansNoSessionEvenWithAValidPayloadPresent() {
        XCTAssertNil(UITestSession.current(
            arguments: ["District AI"],
            environment: [UITestSession.sessionVariable: Self.validPayload]
        ))
    }

    /// The unauthenticated UI lane: armed, no session. `current()` stays nil so
    /// nothing is adopted; `isArmed` is what lets the container hand that lane an
    /// empty in-memory store instead of an unreadable Keychain.
    func testArmedWithoutASessionIsArmedButYieldsNoSession() {
        let arguments = ["District AI", UITestSession.launchArgument]
        XCTAssertTrue(UITestSession.isArmed(arguments: arguments))
        XCTAssertNil(UITestSession.current(arguments: arguments, environment: [:]))
    }

    func testNoArgumentIsNotArmed() {
        XCTAssertFalse(UITestSession.isArmed(arguments: ["District AI"]))
    }

    func testTheArgumentAloneIsNotEnough() {
        XCTAssertNil(UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [:]
        ))
    }

    func testAnEmptyPayloadIsTreatedAsAbsentRatherThanAsAnError() {
        XCTAssertNil(UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [UITestSession.sessionVariable: ""]
        ))
    }

    /// ⚠️ MALFORMED JSON IS nil, NOT A CRASH. A runner that exports a truncated
    /// value must leave the app signing in normally, not take the process down.
    func testMalformedJsonYieldsNoSession() {
        XCTAssertNil(UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [UITestSession.sessionVariable: "{not json"]
        ))
    }

    /// ⛔ `deviceId` IS REQUIRED. The server's push and session rows are keyed on the
    /// installation, so a session adopted without one would claim a different row
    /// from the one the operator minted it for.
    func testAPayloadMissingDeviceIdIsRejected() {
        let noDevice = """
        {"tokenType":"Bearer","accessToken":"a","accessTokenExpiresAt":1,\
        "refreshToken":"r","refreshTokenExpiresAt":2}
        """
        XCTAssertNil(UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [UITestSession.sessionVariable: noDevice]
        ))
    }

    func testBothHalvesPresentYieldsTheSession() {
        let session = UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [UITestSession.sessionVariable: Self.validPayload]
        )
        XCTAssertEqual(session?.deviceId, "dev-1")
        XCTAssertEqual(session?.tokens.accessToken, "a")
        XCTAssertEqual(session?.tokens.refreshToken, "r")
        XCTAssertNil(session?.baseURL, "no base-URL override was supplied")
    }

    func testTheBaseUrlOverrideIsOptionalAndParsed() {
        let session = UITestSession.current(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [
                UITestSession.sessionVariable: Self.validPayload,
                UITestSession.baseURLVariable: "https://review.example.com",
            ]
        )
        XCTAssertEqual(session?.baseURL?.absoluteString, "https://review.example.com")
    }

    // MARK: - The screenshot window size

    func testTheWindowSizeNeedsTheArgument() {
        XCTAssertNil(UITestSession.windowPoints(
            arguments: ["District AI"],
            environment: [UITestSession.windowVariable: "1440x900"]
        ))
    }

    func testTheWindowSizeIsParsedWhenArmed() {
        let size = UITestSession.windowPoints(
            arguments: ["District AI", UITestSession.launchArgument],
            environment: [UITestSession.windowVariable: "1440x900"]
        )
        XCTAssertEqual(size, CGSize(width: 1440, height: 900))
    }

    /// ⚠️ BELOW THE WINDOW'S MINIMUM, OR MALFORMED, IS IGNORED rather than fought over with
    /// the `.frame(minWidth:minHeight:)` the shell sets.
    func testAMalformedOrTooSmallWindowSizeIsIgnored() {
        let armed = ["District AI", UITestSession.launchArgument]
        for raw in ["", "1440", "1440x", "x900", "wide x tall", "800x600", "1440x900x2"] {
            XCTAssertNil(
                UITestSession.windowPoints(arguments: armed, environment: [UITestSession.windowVariable: raw]),
                raw
            )
        }
    }
}
