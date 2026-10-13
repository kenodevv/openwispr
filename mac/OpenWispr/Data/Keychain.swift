import Foundation
import Security

/// Thin wrapper around the macOS Keychain for the API credentials.
enum Keychain {
    static let service = "de.keno.openwispr"
    static let apiKeyAccount = "anthropic-api-key"
    static let workspaceAccount = "anthropic-workspace-id"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        delete(account)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// One-time import: a JSON file {"apiKey": "...", "workspaceId": "..."} dropped into the app's
    /// Application Support folder is moved into app-owned Keychain items (no Keychain dialog) and deleted.
    static func importPendingCredentials() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenWispr", isDirectory: true)
        let file = dir.appendingPathComponent("pending-credentials.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        if let key = json["apiKey"], !key.isEmpty {
            write(key, account: apiKeyAccount)
            write(json["workspaceId"] ?? "", account: workspaceAccount)
            UserDefaults.standard.set(true, forKey: "keychainMigrated")
        }
        try? FileManager.default.removeItem(at: file)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
