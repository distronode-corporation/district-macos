import DistrictAuthCore
import DistrictNetwork
import Foundation

/// The native-auth client, with both of its seams pinned to the auth layer's types.
///
/// Ported from district-ios unchanged. ⛔ THE EXTENSIONS BELOW ARE EMPTY BY DESIGN:
/// ``NativeAuthClient`` lives in the shared core's `DistrictNetwork`, which cannot name
/// `DistrictAuthCore`'s types, so it takes them as generic parameters and these lines
/// supply them. A mapping function written here would put a security-relevant status
/// map on the one tier with no Linux tests.
///
/// ⛔ ITS TWO SIGN-IN EXCHANGES SEND WHATEVER PLATFORM THE REQUEST NAMES, AND THE CORE
/// DEFAULTS IT TO `.ios`. The Mac builds both requests in one place each,
/// ``WebAuthLoginController/codeExchangeRequest(code:verifier:deviceId:deviceName:)``
/// and ``AppleSignInController/signInRequest(identityToken:nonce:deviceId:deviceName:)``,
/// with `.macos`.
///
/// ⚠️ `@retroactive` BECAUSE BOTH SIDES OF EVERY CONFORMANCE BELOW ARE IMPORTED (the
/// types from one core module, the protocols from another). It silences Swift 6's
/// warning and records the deliberate choice: if the core ever declares one of these
/// conformances itself, delete the line here.
typealias AppNativeAuthClient = NativeAuthClient<NativeTokenResponse, RefreshResult, RevokeOutcome>
extension NativeTokenResponse: @retroactive NativeAuthTokenWire {}

extension RefreshResult: @retroactive NativeRefreshOutcome {}

extension RevokeDeferral: @retroactive NativeRevokeDeferral {}

extension RevokeOutcome: @retroactive NativeRevokeOutcome {}

extension NativeAuthClient: @retroactive RefreshClient where Refresh == RefreshResult {}

extension NativeAuthClient: @retroactive RevokeClient where Revoke == RevokeOutcome {}
