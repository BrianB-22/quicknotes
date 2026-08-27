import Foundation
import Security

/// Stores a per-note passcode in the macOS Keychain so Touch ID can stand in for
/// typing it. The Keychain item itself isn't biometry-gated — the Touch ID prompt
/// (see `BiometricAuth`) is what stands between a user and reading it back.
enum KeychainStore {
    private static let service = "com.quicknotes.notepasscode"

    static func save(passcode: String, for noteID: UUID) {
        let account = noteID.uuidString
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(passcode.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadPasscode(for noteID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: noteID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasPasscode(for noteID: UUID) -> Bool {
        loadPasscode(for: noteID) != nil
    }

    static func deletePasscode(for noteID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: noteID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
