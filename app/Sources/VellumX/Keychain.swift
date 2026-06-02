import Foundation
import Security

/// Read-only Keychain helper used only for one-time migration of the API key
/// from the old Keychain-backed storage to settings.json.
/// New code should not write to the Keychain; use AppSettings.apiKey instead.
enum Keychain {
    private static let service = "com.ailurus.vellumx"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}
