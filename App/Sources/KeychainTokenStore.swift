import DistrictAuthCore
import Foundation
import Security

/// The production ``TokenStore``: one keychain item for the session, one for the
/// pending-refresh marker, one for the revoke outbox.
///
/// Ported from district-ios, with one macOS difference that matters.
///
/// ⛔ THE DATA-PROTECTION KEYCHAIN (`kSecUseDataProtectionKeychain: true`), NEVER THE
/// LEGACY FILE KEYCHAIN. On macOS a `SecItem` call without it writes to the login
/// keychain, whose items are owned by an ACL naming the CODE SIGNATURE that created them:
/// the App Store build and the Developer ID build are signed differently, so each would
/// prompt for the other's items, and a Sparkle update re-signed differently would prompt
/// on every launch. The data-protection keychain is the iOS model instead: items belong
/// to the `keychain-access-groups` entitlement, which both builds carry with the same
/// value (project.yml), so either reads the session silently.
/// ⚠️ WITHOUT THAT ENTITLEMENT (an ad-hoc local or CI build) EVERY CALL ANSWERS
/// `errSecMissingEntitlement` (-34018). The coordinator reports that as the store being
/// unavailable, so an unsigned build lands on "Try again" rather than "Sign in", which is
/// the iOS app's unsigned behaviour too.
///
/// ⛔ `kSecAttrSynchronizable = false` IS LOAD-BEARING: a synced item puts the same
/// single-use refresh token on two devices, and the second one to present it is read as
/// a replay that revokes the whole token family.
///
/// ⛔ `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: never restored to another Mac
/// from a backup, and readable by a launch-at-login or background start.
struct KeychainTokenStore: TokenStore {
    static let defaultService = "com.distronode.district.session"

    private static let sessionAccount = "native-session"
    private static let pendingAccount = "native-refresh-pending"
    private static let revokeAccount = "native-revoke-pending"

    let service: String

    init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    // MARK: - Session

    func read() async throws -> PersistedSession? {
        guard let data = try load(account: Self.sessionAccount) else { return nil }
        let stored = try decode(data)
        return PersistedSession(
            refreshToken: stored.refreshToken,
            refreshTokenExpiresAt: stored.refreshTokenExpiresAt,
            deviceId: stored.deviceId
        )
    }

    func write(_ session: PersistedSession) async throws {
        let stored = StoredSession(
            refreshToken: session.refreshToken,
            refreshTokenExpiresAt: session.refreshTokenExpiresAt,
            deviceId: session.deviceId
        )
        let data = try JSONEncoder().encode(stored)
        try save(data, account: Self.sessionAccount)
    }

    /// ⚠️ Clears the session AND the pending marker, never the revoke outbox: that entry
    /// outlives the session on purpose, so a sign-out whose revoke failed is retried.
    func clear() async throws {
        try delete(account: Self.sessionAccount)
        try delete(account: Self.pendingAccount)
    }

    // MARK: - Pending-refresh marker

    func pendingRefreshToken() async throws -> String? {
        guard let data = try load(account: Self.pendingAccount) else { return nil }
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.unreadableItem
        }
        return token
    }

    func markRefreshPending(_ refreshToken: String) async throws {
        try save(Data(refreshToken.utf8), account: Self.pendingAccount)
    }

    func clearRefreshPending() async throws {
        try delete(account: Self.pendingAccount)
    }

    // MARK: - Revoke outbox

    func pendingRevokeToken() async throws -> String? {
        guard let data = try load(account: Self.revokeAccount) else { return nil }
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.unreadableItem
        }
        return token
    }

    func markRevokePending(_ refreshToken: String) async throws {
        try save(Data(refreshToken.utf8), account: Self.revokeAccount)
    }

    func clearRevokePending() async throws {
        try delete(account: Self.revokeAccount)
    }

    // MARK: - Keychain plumbing

    /// ⛔ `kSecUseDataProtectionKeychain` IS ON EVERY QUERY, the reads and deletes too: a
    /// query without it searches the file keychain and finds nothing, which reads as "no
    /// session" rather than as a misconfigured query.
    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func load(account: String) throws -> Data? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainTokenStoreError.unreadableItem }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.status(status)
        }
    }

    private func save(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updated = SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess {
            return
        }
        guard updated == errSecItemNotFound else { throw KeychainTokenStoreError.status(updated) }

        var request = query(account: account)
        request.merge(attributes) { _, new in new }
        let added = SecItemAdd(request as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainTokenStoreError.status(added) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.status(status)
        }
    }

    private func decode(_ data: Data) throws -> StoredSession {
        do {
            return try JSONDecoder().decode(StoredSession.self, from: data)
        } catch {
            throw KeychainTokenStoreError.unreadableItem
        }
    }

    private struct StoredSession: Codable {
        let refreshToken: String
        let refreshTokenExpiresAt: Int64
        let deviceId: String
    }
}

enum KeychainTokenStoreError: Error {
    case status(OSStatus)
    case unreadableItem
}
