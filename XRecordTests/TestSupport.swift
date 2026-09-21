import Foundation
import Security
import CryptoKit
import CommonCrypto
import XCTest

// MARK: - 测试替身

/// 内存版主密钥存储，避免测试触碰真实钥匙串
final class InMemoryMasterKeyStore: MasterKeyStoring {
    private(set) var key: Data?
    private(set) var loadCallCount = 0
    var shouldFailStore = false

    func loadMasterKey() -> Data? {
        loadCallCount += 1
        return key
    }

    @discardableResult
    func storeMasterKey(_ key: Data) -> Bool {
        guard !shouldFailStore else { return false }
        self.key = key
        return true
    }

    @discardableResult
    func deleteMasterKey() -> Bool {
        key = nil
        return true
    }
}

// MARK: - 旧版格式加密（复刻 v1.x 的硬编码种子实现）

enum TestCipher {
    static let legacySeed = "XRecord-MasterKey-2024"
    static let legacyIterations = 100_000

    static func randomSalt(count: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func json(_ data: AppData) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(data)) ?? Data()
    }

    static func decode(_ data: Data) -> AppData? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: data)
    }

    /// 旧格式：salt(32) + AES-GCM(combined)，密钥由硬编码种子 + PBKDF2 派生
    static func legacyEncrypt(_ plaintext: Data, salt: Data) -> Data {
        let key = pbkdf2(
            password: Data(legacySeed.utf8),
            salt: salt,
            iterations: legacyIterations,
            keyLength: 32
        )
        guard let sealed = try? AES.GCM.seal(plaintext, using: SymmetricKey(data: key)).combined else {
            return Data()
        }
        return salt + sealed
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        password.withUnsafeBytes { passwordPtr in
            salt.withUnsafeBytes { saltPtr in
                _ = CCKeyDerivationPBKDF(
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
}

// MARK: - 测试基类

class XCTestCaseBase: XCTestCase {
    private(set) var tempDir: URL!
    private(set) var defaults: UserDefaults!
    private var suiteName: String!
    private(set) var alerts: [(title: String, message: String)] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "XRecordTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        alerts = []
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        if let suiteName { defaults?.removePersistentDomain(forName: suiteName) }
        try super.tearDownWithError()
    }

    /// 创建注入测试替身的加密服务
    func makeEncryption(store: InMemoryMasterKeyStore = InMemoryMasterKeyStore()) -> EncryptionService {
        EncryptionService(keyStore: store, defaults: defaults)
    }

    /// 创建注入测试替身的数据服务
    func makeDataService(encryption: EncryptionService) -> DataService {
        DataService(encryption: encryption, defaults: defaults) { [weak self] title, message in
            self?.alerts.append((title, message))
        }
    }

    func tempURL(_ name: String) -> URL {
        tempDir.appendingPathComponent(name)
    }
}
