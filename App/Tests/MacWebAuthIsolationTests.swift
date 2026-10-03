@testable import DistrictMac
import XCTest

/// ⛔ THE WEB SIGN-IN'S COMPLETION HANDLER RUNS OFF THE MAIN THREAD WITHOUT TRAPPING.
///
/// AuthenticationServices calls `ASWebAuthenticationSession`'s completion handler on its
/// own XPC reply queue. Build 20012 created that closure inside the `@MainActor`
/// `WebAuthLoginController`, so Swift 6 made it main-actor isolated and every sign-in
/// ended in SIGILL (`dispatch_assert_queue`). These tests call the handler from a
/// background queue, the way the SDK does: an isolated closure would crash the test host.
final class MacWebAuthIsolationTests: XCTestCase {
    func testTheCallbackResumesFromABackgroundQueue() async throws {
        let callback = try XCTUnwrap(URL(string: "districtai://auth?code=c&state=s"))
        let result = await Self.callHandlerOffMain(callback, nil)
        XCTAssertEqual(try result.get(), callback)
    }

    func testAnErrorResumesFromABackgroundQueue() async {
        let result = await Self.callHandlerOffMain(nil, WebAuthLoginError.couldNotStart)
        guard case let .failure(error) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(error is WebAuthLoginError)
    }

    func testNoCallbackAndNoErrorIsNoCallback() async {
        let result = await Self.callHandlerOffMain(nil, nil)
        guard case let .failure(error) = result, case .noCallback = error as? WebAuthLoginError else {
            return XCTFail("expected noCallback")
        }
    }

    /// ⚠️ A SECOND CALL IS IGNORED, not a second resume (which a checked continuation traps on).
    func testASecondCallIsIgnored() async throws {
        let callback = try XCTUnwrap(URL(string: "districtai://auth?code=c&state=s"))
        let result = await withCheckedContinuation { continuation in
            let handler = WebAuthLoginController.completionHandler(SingleResume(continuation))
            DispatchQueue.global().async {
                handler(callback, nil)
                handler(nil, WebAuthLoginError.noCallback)
            }
        }
        XCTAssertEqual(try result.get(), callback)
    }

    private static func callHandlerOffMain(_ url: URL?, _ error: (any Error)?) async -> Result<URL, any Error> {
        await withCheckedContinuation { continuation in
            let handler = WebAuthLoginController.completionHandler(SingleResume(continuation))
            DispatchQueue.global().async {
                XCTAssertFalse(Thread.isMainThread)
                handler(url, error)
            }
        }
    }
}
