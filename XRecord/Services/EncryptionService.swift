import Foundation
import CryptoKit
import Security

// MARK: - 数据加密服务（AES-256-GCM）

class EncryptionService {
    static let shared = EncryptionService()

    private let keychainService = "com.xrecord.encryption"
    private let keychainAccount = "masterKey"

    // MARK: - Keychain 操作

    /// 从 Keychain 获取或生成密钥
    private func getOrCreateKey() -> SymmetricKey? {
        // 尝试从 Keychain 获取
        if let keyData = loadFromKeychain() {
            return SymmetricKey(data: keyData)
        }

        // 生成新密钥并存储
        let newKey = SymmetricKey(size: .bits256)
        if saveToKeychain(newKey) {
            return newKey
        }
        return nil
    }

    private func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        return nil
    }

    private func saveToKeychain(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }

        // 先删除旧条目
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 添加新条目
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - 加密/解密

    /// 加密数据
    func encrypt(_ data: Data) -> Data? {
        guard let key = getOrCreateKey() else { return nil }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            print("加密失败: \(error)")
            return nil
        }
    }

    /// 解密数据
    func decrypt(_ encryptedData: Data) -> Data? {
        guard let key = getOrCreateKey() else { return nil }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            print("解密失败: \(error)")
            return nil
        }
    }

    /// 解密字符串
    func decryptString(_ encryptedData: Data) -> String? {
        guard let data = decrypt(encryptedData) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
