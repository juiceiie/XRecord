import XCTest

final class EncryptionServiceTests: XCTestCaseBase {

    func testLoadOrCreateMasterKeyIsStableAnd32Bytes() {
        let store = InMemoryMasterKeyStore()
        let encryption = makeEncryption(store: store)

        let first = encryption.loadOrCreateMasterKey()
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(encryption.cachedMasterKey(), first)

        let second = encryption.loadOrCreateMasterKey()
        XCTAssertEqual(first, second)
        XCTAssertEqual(store.key, first)
    }

    func testEncryptDecryptRoundTrip() throws {
        let encryption = makeEncryption()
        let key = encryption.loadOrCreateMasterKey()
        let plaintext = Data("机密数据 secret payload".utf8)

        let blob = try XCTUnwrap(encryption.encrypt(plaintext, masterKey: key, wrap: nil))
        XCTAssertTrue(EncryptionService.hasModernHeader(blob))

        let parsed = try XCTUnwrap(encryption.parse(blob))
        XCTAssertTrue(parsed.isModern)
        XCTAssertNil(parsed.keyWrap)
        XCTAssertEqual(encryption.decryptPayload(parsed, masterKey: key), plaintext)

        // 错误的主密钥无法解密
        let wrongKey = Data(repeating: 0xAB, count: 32)
        XCTAssertNil(encryption.decryptPayload(parsed, masterKey: wrongKey))
    }

    func testEncryptWithMigrationWrapRoundTrip() throws {
        let encryption = makeEncryption()
        let key = encryption.loadOrCreateMasterKey()
        let wrap = try XCTUnwrap(encryption.makeKeyWrap(masterKey: key, passphrase: "passphrase123"))
        let plaintext = Data("cross-device".utf8)

        let blob = try XCTUnwrap(encryption.encrypt(plaintext, masterKey: key, wrap: wrap))
        let parsed = try XCTUnwrap(encryption.parse(blob))
        XCTAssertEqual(parsed.keyWrap, wrap)

        // 模拟新设备：无缓存主密钥，用口令解出
        let recovered = try XCTUnwrap(encryption.unwrapMasterKey(from: try XCTUnwrap(parsed.keyWrap), passphrase: "passphrase123"))
        XCTAssertEqual(recovered, key)
        XCTAssertEqual(encryption.decryptPayload(parsed, masterKey: recovered), plaintext)
    }

    func testWrongPassphraseFailsToUnwrap() throws {
        let encryption = makeEncryption()
        let key = encryption.loadOrCreateMasterKey()
        let wrap = try XCTUnwrap(encryption.makeKeyWrap(masterKey: key, passphrase: "correct-pass"))

        XCTAssertNil(encryption.unwrapMasterKey(from: wrap, passphrase: "wrong-pass"))
        XCTAssertEqual(encryption.unwrapMasterKey(from: wrap, passphrase: "correct-pass"), key)
    }

    func testParseRejectsGarbageAndShortData() {
        let encryption = makeEncryption()

        XCTAssertNil(encryption.parse(Data([0x00, 0x01, 0x02])))
        XCTAssertNil(encryption.parse(TestCipher.randomSalt(count: 16)))

        // 有 XRC2 魔数但头部损坏
        var truncated = Data("XRC2".utf8)
        truncated.append(Data([0x00, 0x00, 0x00, 0x10]))
        XCTAssertNil(encryption.parse(truncated))
    }

    func testLegacyDecryptReadsOldFormat() throws {
        let encryption = makeEncryption()
        let appData = AppData(groups: [Group(name: "旧分组", colorHex: "#4f6ef7")], cards: [], appTitle: "旧标题")
        let salt = TestCipher.randomSalt(count: 32)
        let legacyBlob = TestCipher.legacyEncrypt(TestCipher.json(appData), salt: salt)

        let parsed = try XCTUnwrap(encryption.parse(legacyBlob))
        XCTAssertFalse(parsed.isModern)

        let decrypted = try XCTUnwrap(encryption.legacyDecrypt(parsed))
        XCTAssertEqual(decrypted, TestCipher.json(appData))
    }
}
