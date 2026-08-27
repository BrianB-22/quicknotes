import Foundation
import Security
import os

/// Stores a per-note passcode in the macOS Keychain so Touch ID can stand in for
/// typing it. The item itself is biometry-gated via `SecAccessControl` — reading
/// it back (`loadPasscode`) requires the OS's own Touch ID prompt, enforced by
/// the Secure Enclave, not just an app-side check before the read.
enum KeychainStore {
    private static let service = "com.quicknotes.notepasscode"
    private static let logger = Logger(subsystem: "com.quicknotes", category: "keychain")

    static func save(passcode: String, for noteID: UUID) {
        let account = noteID.uuidString
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            let description = accessError?.takeRetainedValue().localizedDescription ?? "unknown error"
            logger.error("SecAccessControlCreateWithFlags failed for \(noteID, privacy: .public): \(description, privacy: .public)")
            return
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(passcode.utf8)
        attributes[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("SecItemAdd failed for \(noteID, privacy: .public): OSStatus \(status, privacy: .public)")
        }
    }

    /// Triggers the system Touch ID prompt as part of the Keychain read itself
    /// (enforced by the item's access control) — callers should not also
    /// perform their own `BiometricAuth` check first, or the user would see
    /// two prompts back to back.
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
        guard status == errSecSuccess, let data = result as? Data else {
            logger.error("loadPasscode failed for \(noteID, privacy: .public): OSStatus \(status, privacy: .public)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Existence check only — deliberately does NOT go through `loadPasscode`,
    /// since that would trigger a Touch ID prompt just to decide whether to
    /// show the "Unlock with Touch ID" button, before the user has asked for
    /// anything. Omitting `kSecReturnData` means only metadata is matched, not
    /// the protected secret, so this doesn't touch the access-control gate.
    static func hasPasscode(for noteID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: noteID.uuidString,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("hasPasscode query failed for \(noteID, privacy: .public): OSStatus \(status, privacy: .public)")
        }
        return status == errSecSuccess
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
