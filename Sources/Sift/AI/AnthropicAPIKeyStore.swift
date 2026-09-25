import Foundation
import Security

/// Stores the user's own Anthropic API key in the macOS Keychain -- never in
/// UserDefaults (plaintext) or committed anywhere. Sift never ships with a key of its
/// own; the Vibe feature is unavailable until the person using the app enters theirs.
enum AnthropicAPIKeyStore {
    private static let service = "com.sift.anthropic-api-key"
    private static let account = "anthropic"

    static func load() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeAll()
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Simplest correct way to "upsert" a Keychain item: delete whatever's there
        // first (a no-op if nothing is), then add the new value.
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
