import XCTest
import UniformTypeIdentifiers

final class DataServiceTests: XCTestCaseBase {

    func testCreateFileWritesModernEncryptedFile() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        let url = tempURL("XRecord.xrecord")

        service.createFile(at: url)

        XCTAssertTrue(service.hasBoundFile)
        XCTAssertEqual(service.currentFileURL, url)
        XCTAssertFalse(service.isLocked)

        let blob = try Data(contentsOf: url)
        XCTAssertTrue(EncryptionService.hasModernHeader(blob))
    }

    func testXRecordDocumentTypeUsesCustomExtension() {
        XCTAssertTrue(UTType.xrecordDocument.conforms(to: .data))
        XCTAssertEqual(UTType.xrecordDocument.preferredFilenameExtension, "xrecord")
    }

    func testRenameBoundTXTFilePreservesContentsAndUpdatesBinding() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        let oldURL = tempURL("我的密码本.txt")
        service.createFile(at: oldURL)
        let originalContents = try Data(contentsOf: oldURL)

        XCTAssertTrue(service.renameBoundFileToXRecord())

        let newURL = tempURL("我的密码本.xrecord")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL), originalContents)
        XCTAssertEqual(service.currentFileURL, newURL)
        XCTAssertEqual(defaults.string(forKey: "xrecord_file_path"), newURL.path)
        XCTAssertTrue(service.hasBoundFile)
        XCTAssertFalse(service.isLocked)
    }

    func testRenameBoundTXTFileNeverOverwritesExistingXRecordFile() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        let oldURL = tempURL("密码本.txt")
        let existingURL = tempURL("密码本.xrecord")
        service.createFile(at: oldURL)
        let originalContents = try Data(contentsOf: oldURL)
        let existingContents = Data("existing-file".utf8)
        try existingContents.write(to: existingURL)

        XCTAssertFalse(service.renameBoundFileToXRecord())

        XCTAssertEqual(try Data(contentsOf: oldURL), originalContents)
        XCTAssertEqual(try Data(contentsOf: existingURL), existingContents)
        XCTAssertEqual(service.currentFileURL, oldURL)
        XCTAssertEqual(defaults.string(forKey: "xrecord_file_path"), oldURL.path)
        XCTAssertEqual(alerts.last?.title, "无法修改文件名")
    }

    func testSetAndClearMigrationPassphrase() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        service.createFile(at: tempURL("new.txt"))

        XCTAssertTrue(service.setMigrationPassphrase("secret-pass"))
        XCTAssertTrue(service.hasMigrationPassphrase)
        XCTAssertNotNil(encryption.storedKeyWrap)

        // 口令可解回当前主密钥
        let recovered = try XCTUnwrap(
            encryption.unwrapMasterKey(from: try XCTUnwrap(encryption.storedKeyWrap), passphrase: "secret-pass")
        )
        XCTAssertEqual(recovered, encryption.cachedMasterKey())

        service.clearMigrationPassphrase()
        XCTAssertFalse(service.hasMigrationPassphrase)
        XCTAssertNil(encryption.storedKeyWrap)
    }

    func testLegacyFileIsBackedUpBeforeUpgrade() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)

        let appData = AppData(
            groups: [Group(name: "旧分组", colorHex: "#4f6ef7")],
            cards: [],
            appTitle: "旧数据"
        )
        let url = tempURL("legacy.txt")
        let legacyBlob = TestCipher.legacyEncrypt(TestCipher.json(appData), salt: TestCipher.randomSalt())
        try legacyBlob.write(to: url)

        service.bind(to: url)

        XCTAssertTrue(service.hasBoundFile)
        XCTAssertFalse(service.isLocked)
        XCTAssertEqual(service.data.appTitle, "旧数据")
        XCTAssertEqual(service.data.groups.count, 1)

        // 只读加载不能改写旧文件。
        XCTAssertEqual(try Data(contentsOf: url), legacyBlob)

        // 首次保存时先创建原始备份，再升级为现代格式。
        XCTAssertTrue(service.save())
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("xrecord-v1-backup")), legacyBlob)

        let upgraded = try Data(contentsOf: url)
        XCTAssertTrue(EncryptionService.hasModernHeader(upgraded))
        let upgradedParsed = try XCTUnwrap(encryption.parse(upgraded))
        XCTAssertTrue(upgradedParsed.isModern)

        // 升级写回的内容必须仍是原始数据，绝不能被空数据覆盖
        let masterKey = try XCTUnwrap(encryption.cachedMasterKey())
        let decrypted = try XCTUnwrap(encryption.decryptPayload(upgradedParsed, masterKey: masterKey))
        let restored = try XCTUnwrap(TestCipher.decode(decrypted))
        XCTAssertEqual(restored.appTitle, "旧数据")
        XCTAssertEqual(restored.groups.count, 1)
        XCTAssertEqual(restored.groups.first?.name, "旧分组")
    }

    func testBindFailureRollsBackToPreviousBinding() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)

        // 先绑定一个有效文件
        let goodData = AppData(
            groups: [],
            cards: [Card(groupId: "g", name: "条目", url: "", username: "u", password: "p", note: "")],
            appTitle: "有效"
        )
        let goodURL = tempURL("good.txt")
        let blob = try XCTUnwrap(
            encryption.encrypt(
                TestCipher.json(goodData),
                masterKey: try XCTUnwrap(encryption.loadOrCreateMasterKey()),
                wrap: nil
            )
        )
        try blob.write(to: goodURL)
        service.bind(to: goodURL)
        XCTAssertTrue(service.hasBoundFile)
        XCTAssertEqual(service.data.cards.count, 1)

        // 再绑定一个无法解密的文件
        let badURL = tempURL("bad.txt")
        try TestCipher.randomSalt(count: 64).write(to: badURL)
        service.bind(to: badURL)

        // 应回滚到原来的有效绑定，数据未被清空
        XCTAssertTrue(service.hasBoundFile)
        XCTAssertEqual(service.currentFileURL, goodURL)
        XCTAssertEqual(service.data.cards.count, 1)
        XCTAssertFalse(service.isLocked)
        XCTAssertFalse(alerts.isEmpty)
    }

    func testBindFailureFromUnboundKeepsUnbound() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        XCTAssertFalse(service.hasBoundFile)

        let badURL = tempURL("bad.txt")
        try TestCipher.randomSalt(count: 64).write(to: badURL)
        service.bind(to: badURL)

        XCTAssertFalse(service.hasBoundFile)
        XCTAssertNil(service.currentFileURL)
        XCTAssertFalse(service.isLocked)
        XCTAssertFalse(alerts.isEmpty)
    }

    func testLockedFileIsNotOverwrittenBySave() throws {
        let badURL = tempURL("locked.txt")
        let original = TestCipher.randomSalt(count: 64)
        try original.write(to: badURL)

        // 模拟上次运行遗留的绑定路径
        defaults.set(badURL.path, forKey: "xrecord_file_path")

        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)

        XCTAssertTrue(service.hasBoundFile)
        XCTAssertTrue(service.isLocked)
        XCTAssertFalse(alerts.isEmpty)

        // 锁定时修改内存数据并保存，不应写回磁盘
        service.data.appTitle = "被篡改"
        service.save()

        XCTAssertEqual(try Data(contentsOf: badURL), original)
    }

    func testUnbindForReselectClearsBinding() throws {
        let encryption = makeEncryption()
        let service = makeDataService(encryption: encryption)
        service.createFile(at: tempURL("new.txt"))
        XCTAssertTrue(service.hasBoundFile)

        service.unbindForReselect()

        XCTAssertFalse(service.hasBoundFile)
        XCTAssertNil(service.currentFileURL)
        XCTAssertFalse(service.isLocked)
    }

    func testCreateFileDoesNotBindOrWriteWhenKeychainStoreFails() {
        let store = InMemoryMasterKeyStore()
        store.shouldFailStore = true
        let encryption = makeEncryption(store: store)
        let service = makeDataService(encryption: encryption)
        let url = tempURL("must-not-exist.txt")

        service.createFile(at: url)

        XCTAssertFalse(service.hasBoundFile)
        XCTAssertNil(service.currentFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(alerts.last?.title, "无法保存数据")
    }
}
