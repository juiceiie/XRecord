import Foundation
import CryptoKit
import CommonCrypto
import Security

// MARK: - 数据加密服务（Keychain 主密钥 + AES-256-GCM，支持同步与恢复口令）

/// 用同步与恢复口令包装后的主密钥（密文，可安全存储）
struct KeyWrap: Codable, Equatable {
    var salt: Data
    var iterations: Int
    var data: Data
}

/// 解析出的文件结构
struct ParsedEncryptedFile {
    let salt: Data
    let keyWrap: KeyWrap?
    let payload: Data
    let isModern: Bool
}

final class EncryptionService {
    static let shared = EncryptionService()

    private let keyStore: MasterKeyStoring
    private let defaults: UserDefaults
    private var inMemoryMasterKey: Data?

    /// 现代文件格式的魔数："XRC2"
    static let fileMagic = Data([0x58, 0x52, 0x43, 0x32])

    private let keyLength = 32
    private let kdfInfo = Data("XRecord-DataKey-v2".utf8)
    private let legacySeed = "XRecord-MasterKey-2024"
    private let wrapperIterations = 210_000
    private let legacyIterations = 100_000

    private let storedWrapKey = "xrecord_key_wrap_v2"

    init(keyStore: MasterKeyStoring = KeychainMasterKeyStore(),
         defaults: UserDefaults = .standard) {
        self.keyStore = keyStore
        self.defaults = defaults
    }

    // MARK: - 主密钥（钥匙串）

    /// 只读取已存在的主密钥，不创建
    func cachedMasterKey() -> Data? {
        if let key = inMemoryMasterKey, key.count == keyLength {
            return key
        }
        guard let key = keyStore.loadMasterKey(), key.count == keyLength else { return nil }
        inMemoryMasterKey = key
        return key
    }

    /// 读取主密钥，不存在则随机生成并写入钥匙串
    @discardableResult
    func loadOrCreateMasterKey() -> Data? {
        if let key = cachedMasterKey() { return key }
        let key = Self.randomData(count: keyLength)
        guard keyStore.storeMasterKey(key) else { return nil }
        inMemoryMasterKey = key
        return key
    }

    /// 写入主密钥（同步与恢复口令解锁后使用）
    @discardableResult
    func storeMasterKey(_ key: Data) -> Bool {
        guard key.count == keyLength, keyStore.storeMasterKey(key) else { return false }
        inMemoryMasterKey = key
        return true
    }

    // MARK: - 同步与恢复口令包装

    var storedKeyWrap: KeyWrap? {
        guard let data = defaults.data(forKey: storedWrapKey) else { return nil }
        return try? JSONDecoder().decode(KeyWrap.self, from: data)
    }

    func setStoredKeyWrap(_ wrap: KeyWrap?) {
        if let wrap, let data = try? JSONEncoder().encode(wrap) {
            defaults.set(data, forKey: storedWrapKey)
        } else {
            defaults.removeObject(forKey: storedWrapKey)
        }
    }

    /// 用同步与恢复口令包装主密钥，便于跨设备迁移
    func makeKeyWrap(masterKey: Data, passphrase: String) -> KeyWrap? {
        do {
            let salt = Self.randomData(count: 16)
            let wrappingKey = deriveKey(password: passphrase, salt: salt, iterations: wrapperIterations)
            guard let wrapped = try AES.GCM.seal(masterKey, using: wrappingKey).combined else { return nil }
            return KeyWrap(salt: salt, iterations: wrapperIterations, data: wrapped)
        } catch {
            print("生成同步与恢复口令失败: \(error)")
            return nil
        }
    }

    /// 用同步与恢复口令解开主密钥
    func unwrapMasterKey(from wrap: KeyWrap, passphrase: String) -> Data? {
        do {
            let wrappingKey = deriveKey(password: passphrase, salt: wrap.salt, iterations: wrap.iterations)
            let box = try AES.GCM.SealedBox(combined: wrap.data)
            let keyData = try AES.GCM.open(box, using: wrappingKey)
            guard keyData.count == keyLength else { return nil }
            return keyData
        } catch {
            return nil
        }
    }

    // MARK: - 文件格式

    private struct FileHeader: Codable {
        var version: Int
        var salt: Data
        var wrap: KeyWrap?
    }

    /// 加密数据（现代格式）
    func encrypt(_ data: Data, masterKey: Data, wrap: KeyWrap?) -> Data? {
        do {
            let salt = Self.randomData(count: keyLength)
            let dataKey = deriveKey(masterKey: masterKey, salt: salt)
            guard let payload = try AES.GCM.seal(data, using: dataKey).combined else { return nil }

            let header = FileHeader(version: 2, salt: salt, wrap: wrap)
            let headerData = try JSONEncoder().encode(header)

            var result = Data()
            result.append(Self.fileMagic)
            result.append(Self.uint32BE(UInt32(headerData.count)))
            result.append(headerData)
            result.append(payload)
            return result
        } catch {
            print("加密失败: \(error)")
            return nil
        }
    }

    static func hasModernHeader(_ data: Data) -> Bool {
        data.count > fileMagic.count && data.prefix(fileMagic.count) == fileMagic
    }

    /// 解析文件结构（不校验密钥）
    func parse(_ data: Data) -> ParsedEncryptedFile? {
        if Self.hasModernHeader(data) {
            let magicLength = Self.fileMagic.count
            guard data.count >= magicLength + 4 else { return nil }

            let headerLength = Int(Self.readUInt32BE(data.subdata(in: magicLength..<(magicLength + 4))))
            let headerStart = magicLength + 4
            guard headerLength > 0, data.count >= headerStart + headerLength else { return nil }

            let headerData = data.subdata(in: headerStart..<(headerStart + headerLength))
            guard let header = try? JSONDecoder().decode(FileHeader.self, from: headerData) else { return nil }

            let payload = data.subdata(in: (headerStart + headerLength)..<data.count)
            return ParsedEncryptedFile(salt: header.salt, keyWrap: header.wrap, payload: payload, isModern: true)
        }

        guard data.count > 32 else { return nil }
        return ParsedEncryptedFile(
            salt: Data(data.prefix(32)),
            keyWrap: nil,
            payload: Data(data.dropFirst(32)),
            isModern: false
        )
    }

    /// 用主密钥解密现代格式数据
    func decryptPayload(_ parsed: ParsedEncryptedFile, masterKey: Data) -> Data? {
        do {
            let key = deriveKey(masterKey: masterKey, salt: parsed.salt)
            let box = try AES.GCM.SealedBox(combined: parsed.payload)
            return try AES.GCM.open(box, using: key)
        } catch {
            print("解密失败: \(error)")
            return nil
        }
    }

    /// 解密旧版（硬编码种子）格式
    func legacyDecrypt(_ parsed: ParsedEncryptedFile) -> Data? {
        do {
            let key = deriveKey(password: legacySeed, salt: parsed.salt, iterations: legacyIterations)
            let box = try AES.GCM.SealedBox(combined: parsed.payload)
            return try AES.GCM.open(box, using: key)
        } catch {
            print("旧格式解密失败: \(error)")
            return nil
        }
    }

    // MARK: - 密钥派生

    private func deriveKey(masterKey: Data, salt: Data) -> SymmetricKey {
        let ikm = SymmetricKey(data: masterKey)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: kdfInfo,
            outputByteCount: keyLength
        )
    }

    private func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let derived = pbkdf2(
            password: Data(password.utf8),
            salt: salt,
            iterations: iterations,
            keyLength: keyLength
        )
        return SymmetricKey(data: derived)
    }

    // MARK: - 工具

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            for index in 0..<count { bytes[index] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    private static func uint32BE(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    private static func readUInt32BE(_ data: Data) -> UInt32 {
        guard data.count >= 4 else { return 0 }
        let bytes = [UInt8](data.prefix(4))
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}

// MARK: - PBKDF2 实现

private func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
    var derivedKey = [UInt8](repeating: 0, count: keyLength)

    let status = password.withUnsafeBytes { passwordPtr -> Int32 in
        salt.withUnsafeBytes { saltPtr -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                password.count,
                saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derivedKey,
                keyLength
            )
        }
    }

    if status != kCCSuccess {
        print("PBKDF2 失败: \(status)")
    }
    return Data(derivedKey)
}
