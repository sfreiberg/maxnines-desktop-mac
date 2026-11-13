import Foundation
import Security

/// Keeps the API key in the user's Keychain, never in a file or the defaults.
public enum Keychain {
    private static let service = "com.maxnines.menubar"
    private static let account = "api-key"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func apiKey() -> String? {
        var query = query
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

    /// Saves the key, or forgets it when it's empty. Returns whether that worked.
    @discardableResult
    public static func setAPIKey(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
