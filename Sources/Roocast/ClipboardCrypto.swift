import CryptoKit
import Foundation
import Security

/// AES-GCM encryption for clipboard history, keyed from the macOS Keychain.
///
/// ## Threat model (accepted)
/// - **Protects:** file-at-rest — copying `clipboard-history.enc` to another Mac / user
///   yields ciphertext without the Keychain key (`WhenUnlockedThisDeviceOnly`, no iCloud sync).
/// - **Does not protect:** another process running as the *same* logged-in user that knows
///   service `com.roocast.app.clipboard` / account `history-aes-key` can `SecItemCopyMatching`
///   and decrypt. App-bound Keychain ACL needs a stable code signature (not adhoc).
/// - **Also note:** any app can already read the *current* pasteboard via `NSPasteboard`;
///   this only covers persisted history on disk.
enum ClipboardCrypto {
    /// File magic — distinguishes encrypted blobs from legacy plaintext JSON.
    static let magic = Data("ROOCST01".utf8)

    private static let keychainService = "com.roocast.app.clipboard"
    private static let keychainAccount = "history-aes-key"
    private static let keyByteCount = 32

    enum Error: Swift.Error, LocalizedError {
        case keychainFailed(OSStatus)
        case invalidKeyLength
        case sealFailed
        case openFailed
        case truncatedCiphertext

        var errorDescription: String? {
            switch self {
            case .keychainFailed(let status):
                return "Keychain error (\(status))"
            case .invalidKeyLength:
                return "Clipboard key has unexpected length"
            case .sealFailed:
                return "Failed to encrypt clipboard history"
            case .openFailed:
                return "Failed to decrypt clipboard history"
            case .truncatedCiphertext:
                return "Encrypted clipboard file is truncated"
            }
        }
    }

    /// Returns true when `data` starts with the Roocast encrypted-history magic.
    static func isEncryptedBlob(_ data: Data) -> Bool {
        data.count >= magic.count && data.prefix(magic.count) == magic
    }

    /// Load the existing Keychain key or create a fresh 256-bit key (ThisDeviceOnly).
    static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKeyFromKeychain() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try storeKeyInKeychain(key)
        return key
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw Error.sealFailed }
            var out = Data()
            out.reserveCapacity(magic.count + combined.count)
            out.append(magic)
            out.append(combined)
            return out
        } catch let error as ClipboardCrypto.Error {
            throw error
        } catch {
            throw Error.sealFailed
        }
    }

    static func open(_ blob: Data, using key: SymmetricKey) throws -> Data {
        guard isEncryptedBlob(blob) else { throw Error.truncatedCiphertext }
        let combined = blob.dropFirst(magic.count)
        guard combined.count > 12 + 16 else { throw Error.truncatedCiphertext }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(combined))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Error.openFailed
        }
    }

    // MARK: - Keychain

    private static func readKeyFromKeychain() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw Error.keychainFailed(status)
        }
        guard let data = item as? Data else {
            throw Error.invalidKeyLength
        }
        guard data.count == keyByteCount else {
            throw Error.invalidKeyLength
        }
        return SymmetricKey(data: data)
    }

    private static func storeKeyInKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Replace — rare race if two processes create simultaneously.
            let update: [String: Any] = [kSecValueData as String: keyData]
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Error.keychainFailed(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw Error.keychainFailed(status)
        }
    }
}
