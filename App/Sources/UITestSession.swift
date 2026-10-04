#if DEBUG

    import DistrictAuthCore
    import Foundation

    /// A session handed to the app by a UI-test runner, instead of a sign-in.
    ///
    /// Ported from district-ios (`App/Sources/UITestSession.swift`), which feeds it from
    /// `mint-native-session.ts` in the same way. It exists so `DistrictMacUITests` can
    /// capture the Mac App Store screenshots from the review workspace (docs/screenshots.md).
    ///
    /// ⛔ THE WHOLE FILE IS INSIDE `#if DEBUG`, AND THAT IS THE SECURITY BOUNDARY RATHER
    /// THAN A TIDINESS ONE. `DEBUG` is set on the Debug configuration only and every archive
    /// is Release, so these symbols do not exist in a shipped binary. `scripts/archive.sh`
    /// re-proves it per archive by refusing a binary whose strings contain `DISTRICT_UITEST`.
    ///
    /// ⛔ IT GRANTS NOTHING THE TOKEN DOES NOT ALREADY GRANT. The runner supplies a real
    /// session minted server-side for the review account, and the app then behaves exactly
    /// as it would for that account signed in by hand.
    ///
    /// ⛔ ONE MINT, ONE LAUNCH. Refresh rotation is single-use: a replayed refresh token is
    /// treated as theft and revokes the whole family. The operator revokes after the run.
    ///
    /// ⚠️ IN MEMORY, NEVER THE KEYCHAIN. Nothing this seam introduces survives the process.
    struct UITestSession {
        let tokens: NativeTokens
        let deviceId: String
        let baseURL: URL?

        /// The launch argument that arms the seam. ⚠️ Both halves are required: the argument
        /// alone does nothing, so an app launched with it by accident still signs in normally.
        static let launchArgument = "-UITestSession"
        static let sessionVariable = "DISTRICT_UITEST_SESSION"
        static let baseURLVariable = "DISTRICT_UITEST_BASE_URL"
        /// The window's frame in points, `<width>x<height>`, for a screenshot of a fixed size.
        static let windowVariable = "DISTRICT_UITEST_WINDOW_POINTS"

        /// Whether a UI-test runner launched this process at all, session or not.
        static func isArmed(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
            arguments.contains(launchArgument)
        }

        /// The injected session, or nil.
        ///
        /// ⚠️ THE ENVIRONMENT IS READ ONLY WHEN THE ARGUMENT IS PRESENT, and the argument is
        /// honoured only when the environment parses: either half alone occurs by accident.
        static func current(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> UITestSession? {
            guard arguments.contains(launchArgument) else { return nil }
            guard let raw = environment[sessionVariable], !raw.isEmpty else { return nil }
            guard let data = raw.data(using: .utf8) else { return nil }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
            return UITestSession(
                tokens: payload.response.tokens,
                deviceId: payload.deviceId,
                baseURL: environment[baseURLVariable].flatMap(URL.init(string:))
            )
        }

        /// The window size a screenshot run asks for, or nil. Armed runs only, and only a
        /// well-formed `<width>x<height>` of at least the window's minimum size.
        static func windowPoints(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> CGSize? {
            guard isArmed(arguments: arguments), let raw = environment[windowVariable] else { return nil }
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, parts[0] >= 1000, parts[1] >= 560 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        }

        /// ⚠️ THE FIVE `/api/auth/native/token` KEYS PLUS `deviceId`, decoded as the SAME
        /// `NativeTokenResponse` the real exchange decodes, so the token contract has one
        /// reading.
        private struct Payload: Decodable {
            let response: NativeTokenResponse
            let deviceId: String

            init(from decoder: Decoder) throws {
                response = try NativeTokenResponse(from: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                deviceId = try container.decode(String.self, forKey: .deviceId)
            }

            private enum CodingKeys: String, CodingKey { case deviceId }
        }
    }

#endif
