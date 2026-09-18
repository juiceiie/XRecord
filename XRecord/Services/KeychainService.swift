import Foundation
import Security

// MARK: - 主密钥存储抽象（便于测试注入）

protocol MasterKeyStoring {
    func loadMasterKey() -> Data?
    @discardableResult func storeMasterKey(_ key: Data) -> Bool
    @discardableResult func deleteMasterKey() -> Bool
}

// MARK: - 钥匙串实现（保存本机数据密钥）

struct KeychainMasterKeyStore: MasterKeyStoring {
    static let defaultService = "com.xrecord.XRecord"
    static let defaultAccount = "xrecord.masterKey"

    var service: String = Self.defaultService
    var account: String = Self.defaultAccount

    func loadMasterKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    func storeMasterKey(_ key: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: key]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = key
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func deleteMasterKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - 兼容旧调用方式

enum KeychainService {
    static func loadMasterKey() -> Data? {
        KeychainMasterKeyStore().loadMasterKey()
    }

    @discardableResult
    static func storeMasterKey(_ key: Data) -> Bool {
        KeychainMasterKeyStore().storeMasterKey(key)
    }

    @discardableResult
    static func deleteMasterKey() -> Bool {
        KeychainMasterKeyStore().deleteMasterKey()
    }
}
