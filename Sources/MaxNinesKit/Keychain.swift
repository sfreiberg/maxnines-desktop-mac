import Foundation
import Security

/// Keeps the refresh token of the app's sign in in the user's Keychain, never in
/// a file or the defaults. The access token is only ever kept in memory.
public enum Keychain {
    private static let service = "com.maxnines.menubar"
    private static let refreshAccount = "refresh-token"
    /// Where earlier versions of the app kept an API key.
    private static let apiKeyAccount = "api-key"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func refreshToken() -> String? {
        var query = query(refreshAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
            let data = found as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the token, or forgets it when it's nil. Returns whether that worked.
    @discardableResult
    public static func setRefreshToken(_ token: String?) -> Bool {
        let query = query(refreshAccount)
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // Changed in place where there's one, so there's never a moment with none.
        let changes = [kSecValueData as String: Data(token.utf8)]
        let changed = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if changed != errSecItemNotFound {
            return changed == errSecSuccess
        }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Forgets the API key earlier versions of the app kept.
    public static func forgetAPIKey() {
        SecItemDelete(query(apiKeyAccount) as CFDictionary)
    }
}
