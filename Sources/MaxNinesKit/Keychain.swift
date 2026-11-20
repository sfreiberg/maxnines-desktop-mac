import Foundation
import Security

/// Keeps the refresh token of the app's sign in in the user's Keychain, never in
/// a file or the defaults, with the address of the server it's for. The access
/// token is only ever kept in memory.
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

    /// The sign in kept, if there is one.
    public static func signIn() -> KeptSignIn? {
        var query = query(refreshAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
            let data = found as? Data
        else {
            return nil
        }
        return KeptSignIn(data)
    }

    /// Keeps the sign in, or forgets it when it's nil. Returns whether that worked.
    @discardableResult
    public static func keep(_ signIn: KeptSignIn?) -> Bool {
        let query = query(refreshAccount)
        guard let signIn else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // Changed in place where there's one, so there's never a moment with none.
        let changes = [kSecValueData as String: signIn.data]
        let changed = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if changed != errSecItemNotFound {
            return changed == errSecSuccess
        }
        var item = query
        item[kSecValueData as String] = signIn.data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Forgets the API key earlier versions of the app kept.
    public static func forgetAPIKey() {
        SecItemDelete(query(apiKeyAccount) as CFDictionary)
    }
}

/// A sign in as the Keychain keeps it: the refresh token, and the server it's for,
/// in one item, so one is never kept without the other. The token is only ever
/// sent to that server, even if the settings, kept apart, name another.
public struct KeptSignIn: Equatable, Sendable {
    /// The server's address, as it was typed. Nil for a token kept by an earlier
    /// version of the app, which kept only the token, for the server in the settings.
    public let address: String?
    public let refreshToken: String

    public init(address: String?, refreshToken: String) {
        self.address = address
        self.refreshToken = refreshToken
    }

    private struct Stored: Codable {
        let address: String?
        let refreshToken: String
    }

    var data: Data {
        // Encoding two strings can't fail.
        (try? JSONEncoder().encode(Stored(address: address, refreshToken: refreshToken))) ?? Data()
    }

    /// Reads what `data` kept, or nil if it's nothing a sign in was kept as.
    init?(_ data: Data) {
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            self.init(address: stored.address, refreshToken: stored.refreshToken)
        } else if let token = String(data: data, encoding: .utf8), !token.isEmpty {
            // As earlier versions kept it.
            self.init(address: nil, refreshToken: token)
        } else {
            return nil
        }
    }
}
