import Foundation
import CryptoKit
import CommonCrypto

/// Per-note encryption. Each note is encrypted independently with a key derived
/// from whatever passcode the user enters plus that note's own random salt — the
/// app never stores the passcode (or a hash of it) anywhere. A wrong passcode
/// simply fails AES-GCM's built-in authentication check, so there's nothing
/// separate to verify.
enum LockManager {
    enum LockError: Error {
        case decryptionFailed
    }

    private static let pbkdf2Iterations: UInt32 = 200_000
    private static let keyLength = 32
    private static let saltLength = 16

    static func encrypt(_ plainText: String, passcode: String) throws -> EncryptedPayload {
        let salt = randomBytes(count: saltLength)
        let key = deriveKey(passcode: passcode, salt: salt)
        let sealedBox = try AES.GCM.seal(Data(plainText.utf8), using: key)
        guard let combined = sealedBox.combined else { throw LockError.decryptionFailed }
        return EncryptedPayload(ciphertext: combined, salt: salt)
    }

    static func decrypt(_ payload: EncryptedPayload, passcode: String) throws -> String {
        let key = deriveKey(passcode: passcode, salt: payload.salt)
        let sealedBox = try AES.GCM.SealedBox(combined: payload.ciphertext)
        let data = try AES.GCM.open(sealedBox, using: key)
        guard let text = String(data: data, encoding: .utf8) else { throw LockError.decryptionFailed }
        return text
    }

    private static func deriveKey(passcode: String, salt: Data) -> SymmetricKey {
        var derivedKeyData = Data(count: keyLength)
        let passwordLength = passcode.utf8.count
        _ = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes -> Int32 in
            salt.withUnsafeBytes { saltBytes -> Int32 in
                passcode.withCString { passwordPointer -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer, passwordLength,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress, keyLength
                    )
                }
            }
        }
        return SymmetricKey(data: derivedKeyData)
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

struct EncryptedPayload: Codable {
    var ciphertext: Data
    var salt: Data
}
