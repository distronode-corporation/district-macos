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
/// ⚠️ ONLY ``NativeAuthClient/refresh(refreshToken:)`` AND
/// ``NativeAuthClient/revoke(refreshToken:)`` ARE USED ON THE MAC. Its two sign-in
/// exchanges hard-code `platform: "ios"`; the Mac sends `"macos"` through
/// ``MacNativeAuthExchange`` until the core takes a platform parameter (Wave 2).
typealias AppNativeAuthClient = NativeAuthClient<NativeTokenResponse, RefreshResult, RevokeOutcome>
extension NativeTokenResponse: NativeAuthTokenWire {}

extension RefreshResult: NativeRefreshOutcome {}

extension RevokeDeferral: NativeRevokeDeferral {}

extension RevokeOutcome: NativeRevokeOutcome {}

extension NativeAuthClient: RefreshClient where Refresh == RefreshResult {}

extension NativeAuthClient: RevokeClient where Revoke == RevokeOutcome {}
