import Foundation
import CryptoKit
import CommonCrypto

// MARK: - 数据加密服务（AES-256-GCM，密钥随文件迁移）

class EncryptionService {
    static let shared = EncryptionService()

    /// 当前文件的盐值（存储在 UserDefaults，随文件绑定切换）
    private let saltKey = "xrecord_encryption_salt"

    private var salt: Data? {
        get { UserDefaults.standard.data(forKey: saltKey) }
        set { UserDefaults.standard.set(newValue, forKey: saltKey) }
    }

    /// 生成随机盐值
    private func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// 从密码派生密钥（PBKDF2）
    private func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let keyData = pbkdf2(password: passwordData, salt: salt, iterations: 100000, keyLength: 32)
        return SymmetricKey(data: keyData)
    }

    /// 为新文件设置盐值
    func setupForNewFile() -> Bool {
        let newSalt = generateSalt()
        self.salt = newSalt
        return true
    }

    /// 为已有文件设置盐值
    func setupForExistingFile(salt: Data) {
        self.salt = salt
    }

    // MARK: - 加密/解密

    /// 加密数据
    func encrypt(_ data: Data) -> Data? {
        guard let salt = salt else { return nil }

        // 使用固定种子 + salt 派生密钥
        let seed = "XRecord-MasterKey-2024"
        let key = deriveKey(from: seed, salt: salt)

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let encrypted = sealedBox.combined else { return nil }

            // 格式：salt（32字节）+ 加密数据
            var result = Data()
            result.append(salt)
            result.append(encrypted)
            return result
        } catch {
            print("加密失败: \(error)")
            return nil
        }
    }

    /// 解密数据
    func decrypt(_ data: Data) -> Data? {
        // 提取盐值（前32字节）
        guard data.count > 32 else { return nil }
        let fileSalt = data.prefix(32)
        let encryptedData = data.dropFirst(32)

        // 派生密钥
        let seed = "XRecord-MasterKey-2024"
        let key = deriveKey(from: seed, salt: Data(fileSalt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: Data(encryptedData))
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            print("解密失败: \(error)")
            return nil
        }
    }

    /// 解密字符串
    func decryptString(_ data: Data) -> String? {
        guard let decrypted = decrypt(data) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    /// 提取文件中的盐值
    static func extractSalt(from data: Data) -> Data? {
        guard data.count > 32 else { return nil }
        return Data(data.prefix(32))
    }

    /// 检查数据是否已加密（大于32字节）
    static func isEncrypted(_ data: Data) -> Bool {
        return data.count > 32
    }
}

// MARK: - PBKDF2 实现

private func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
    var derivedKey = [UInt8](repeating: 0, count: keyLength)

    password.withUnsafeBytes { passwordPtr in
        salt.withUnsafeBytes { saltPtr in
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

    return Data(derivedKey)
}
