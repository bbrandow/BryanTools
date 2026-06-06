import CryptoKit
import Foundation
import Security

public enum ClipStoreEncryptionKey {
    public static let byteCount = 32

    public static func deterministicTestKey() -> Data {
        Data((0..<byteCount).map { UInt8($0) })
    }
}

final class ClipStoreCipher {
    private static let dataPrefix = Data("BTENC1\n".utf8)
    private static let textPrefix = "btenc:v1:"

    private let key: SymmetricKey

    init(keyData: Data) throws {
        guard keyData.count == ClipStoreEncryptionKey.byteCount else {
            throw ClipboardHistoryError.storage("Clipboard History encryption key must be 32 bytes.")
        }
        self.key = SymmetricKey(data: keyData)
    }

    func encryptData(_ data: Data) throws -> Data {
        if isEncryptedData(data) {
            return data
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw ClipboardHistoryError.storage("Unable to create encrypted clipboard data.")
        }
        return Self.dataPrefix + combined
    }

    func decryptDataIfNeeded(_ data: Data) throws -> Data {
        guard isEncryptedData(data) else {
            return data
        }
        let encryptedBytes = data.dropFirst(Self.dataPrefix.count)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedBytes)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func isEncryptedData(_ data: Data) -> Bool {
        data.starts(with: Self.dataPrefix)
    }

    func encryptText(_ text: String) throws -> String {
        if isEncryptedText(text) {
            return text
        }
        let encryptedData = try encryptData(Data(text.utf8))
        return Self.textPrefix + encryptedData.base64EncodedString()
    }

    func decryptTextIfNeeded(_ text: String) throws -> String {
        guard isEncryptedText(text) else {
            return text
        }
        let encodedData = String(text.dropFirst(Self.textPrefix.count))
        guard let encryptedData = Data(base64Encoded: encodedData) else {
            throw ClipboardHistoryError.storage("Unable to decode encrypted clipboard metadata.")
        }
        let decryptedData = try decryptDataIfNeeded(encryptedData)
        guard let decryptedText = String(data: decryptedData, encoding: .utf8) else {
            throw ClipboardHistoryError.storage("Encrypted clipboard metadata was not valid UTF-8.")
        }
        return decryptedText
    }

    func isEncryptedText(_ text: String) -> Bool {
        text.hasPrefix(Self.textPrefix)
    }
}

enum ClipStoreKeychain {
    private static let service = "com.local.BryanTools.clipboardHistory.storageKey"
    private static let account = "default"

    static func loadOrCreateKey() throws -> Data {
        if let existingKey = try loadKey() {
            return existingKey
        }

        var keyData = Data(count: ClipStoreEncryptionKey.byteCount)
        let result = keyData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, ClipStoreEncryptionKey.byteCount, bytes.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw ClipboardHistoryError.storage("Unable to generate Clipboard History encryption key.")
        }

        do {
            try saveKey(keyData)
            return keyData
        } catch {
            if let existingKey = try loadKey() {
                return existingKey
            }
            throw error
        }
    }

    private static func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ClipboardHistoryError.storage("Clipboard History encryption key was not readable.")
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw ClipboardHistoryError.storage("Unable to read Clipboard History encryption key from Keychain: \(status).")
        }
    }

    private static func saveKey(_ keyData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ClipboardHistoryError.storage("Unable to save Clipboard History encryption key to Keychain: \(status).")
        }
    }
}
