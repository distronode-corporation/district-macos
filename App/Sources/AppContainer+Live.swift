import DistrictAuthCore
import DistrictNetwork
import Foundation

extension AppContainer {
    /// The container the app runs on.
    ///
    /// ⚠️ THE PRODUCTION ANSWER IS THE DEFAULT AND THE ONLY ONE IN RELEASE: `AppContainer()`,
    /// the keychain store and this installation's device id. The `#if DEBUG` below is the
    /// security boundary (see ``UITestSession``): a Release build has no branch that can reach
    /// an injected session.
    ///
    /// ⚠️ ITS OWN FILE BECAUSE `AppContainer.swift` IS LONG and its initialiser sits near the
    /// function-length limit; the seam costs the app one call.
    static func live() -> AppContainer {
        #if DEBUG
            if let injected = UITestSession.current() {
                // ⚠️ IN MEMORY, NEVER THE KEYCHAIN, so a UI-test run leaves no credential on
                // the Mac. ⛔ ONE mint, ONE launch: rotation is single-use, and a replay is
                // read as theft and revokes the whole family.
                let container = AppContainer(
                    baseURL: injected.baseURL ?? ApiClient.productionBaseURL,
                    tokenStore: InMemoryTokenStore()
                )
                let coordinator = container.coordinator
                // ⚠️ THE COORDINATOR IS AN ACTOR: this adopt is queued during the app's
                // `init`, before the first view's `.task` asks it for an access token.
                Task { await coordinator.adopt(injected.tokens, deviceId: injected.deviceId) }
                return container
            }
            if UITestSession.isArmed() {
                // ⚠️ ARMED, NO SESSION: an EMPTY in-memory store, a fresh install's state.
                return AppContainer(tokenStore: InMemoryTokenStore())
            }
        #endif
        return AppContainer()
    }
}
