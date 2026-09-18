import Foundation
import AppKit

// MARK: - 数据持久化服务（读写本地 record.txt）

class DataService: ObservableObject {
    static let shared = DataService()

    @Published var data: AppData = AppData()
    @Published var isLoaded: Bool = false

    /// 是否已绑定数据文件
    @Published var hasBoundFile: Bool = false

    /// 文件无法解密时为 true，此时禁止写回以免覆盖数据
    @Published private(set) var isLocked: Bool = false

    /// 是否已设置迁移口令
    @Published private(set) var hasMigrationPassphrase: Bool = false

    /// 加密服务（可注入以便测试）
    let encryption: EncryptionService

    /// 展示提示弹窗；测试时可替换为无操作实现
    var presentAlert: (_ title: String, _ message: String) -> Void

    // 绑定的文件路径（UserDefaults 持久化）
    private let savedPathKey = "xrecord_file_path"
    private let defaults: UserDefaults
    @Published private(set) var currentFileURL: URL?

    /// 默认路径：~/Desktop/xrecord/record.txt
    private var defaultFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Desktop/xrecord")
        return dir.appendingPathComponent("record.txt")
    }

    /// 当前文件路径（优先用绑定的，否则用默认）
    private var fileURL: URL {
        currentFileURL ?? defaultFileURL
    }

    /// 显示给用户的路径字符串
    var filePathDisplay: String {
        if let url = currentFileURL {
            return url.path
        }
        return "未绑定数据文件"
    }

    private init() {
        encryption = .shared
        defaults = .standard
        presentAlert = DataService.defaultAlertPresenter
        hasMigrationPassphrase = encryption.storedKeyWrap != nil
        loadSavedPath()
    }

    /// 可注入依赖的构造器（测试使用）
    init(encryption: EncryptionService,
         defaults: UserDefaults = .standard,
         presentAlert: ((String, String) -> Void)? = nil) {
        self.encryption = encryption
        self.defaults = defaults
        self.presentAlert = presentAlert ?? DataService.defaultAlertPresenter
        hasMigrationPassphrase = encryption.storedKeyWrap != nil
        loadSavedPath()
    }

    // MARK: - 路径持久化
    private func loadSavedPath() {
        guard let path = defaults.string(forKey: savedPathKey) else {
            hasBoundFile = false
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            defaults.removeObject(forKey: savedPathKey)
            hasBoundFile = false
            return
        }

        currentFileURL = url
        hasBoundFile = true
        _ = loadFromDisk()
    }

    private func savePath(_ url: URL?) {
        if let url = url {
            defaults.set(url.path, forKey: savedPathKey)
        } else {
            defaults.removeObject(forKey: savedPathKey)
        }
        currentFileURL = url
    }

    // MARK: - 文件选择
    func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 record.txt 数据文件"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        bind(to: url)
    }

    /// 绑定文件；若无法解密则回滚绑定，避免误覆盖
    func bind(to url: URL) {
        let previousURL = currentFileURL
        let previousBound = hasBoundFile
        let previousLocked = isLocked
        let previousData = data

        savePath(url)
        hasBoundFile = true
        isLocked = false

        if !loadFromDisk() {
            savePath(previousURL)
            hasBoundFile = previousBound
            isLocked = previousLocked
            data = previousData
        }
    }

    func createNewFile() {
        let panel = NSSavePanel()
        panel.title = "创建新的数据文件"
        panel.nameFieldStringValue = "record.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        createFile(at: url)
    }

    /// 在指定位置创建新的数据文件（供文件面板与测试复用）
    func createFile(at url: URL) {
        savePath(url)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        data = AppData()
        isLocked = false
        hasBoundFile = true
        isLoaded = true
        saveData(data, to: url)
    }

    // MARK: - 加载（解密）
    func load() {
        _ = loadFromDisk()
    }

    /// 解锁已绑定的文件（供加锁界面重试）
    func retryUnlock() {
        isLocked = false
        _ = loadFromDisk()
    }

    /// 解除绑定，回到绑定文件界面
    func unbindForReselect() {
        savePath(nil)
        hasBoundFile = false
        isLocked = false
        data = AppData()
        isLoaded = false
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard hasBoundFile, currentFileURL != nil else { return false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            data = AppData()
            isLocked = false
            isLoaded = true
            return true
        }

        do {
            let blob = try Data(contentsOf: fileURL)
            if blob.isEmpty {
                data = AppData()
                isLocked = false
                isLoaded = true
                return true
            }

            if let decoded = decode(blob) {
                data = decoded
                isLocked = false
                isLoaded = true
                return true
            }

            // 解密/解析失败：保留现有内存数据并加锁，绝不写回覆盖
            isLocked = true
            isLoaded = true
            presentUnlockFailure()
            return false
        } catch {
            print("读取失败: \(error)")
            isLocked = true
            isLoaded = true
            presentUnlockFailure()
            return false
        }
    }

    /// 将磁盘内容解码为 AppData；失败返回 nil（不清空数据）
    private func decode(_ blob: Data) -> AppData? {
        // 1) 旧版本的明文 JSON
        if let plain = decodePlainJSON(blob) {
            return plain
        }

        guard let parsed = encryption.parse(blob) else { return nil }

        if parsed.isModern {
            // 1) 本机钥匙串已有主密钥
            if let key = encryption.cachedMasterKey(),
               let decrypted = encryption.decryptPayload(parsed, masterKey: key),
               let appData = decodePlainJSON(decrypted) {
                return appData
            }

            // 2) 用迁移口令解出主密钥
            if let wrap = parsed.keyWrap ?? encryption.storedKeyWrap,
               let key = promptForMasterKey(wrap: wrap),
               let decrypted = encryption.decryptPayload(parsed, masterKey: key),
               let appData = decodePlainJSON(decrypted) {
                encryption.setStoredKeyWrap(wrap)
                hasMigrationPassphrase = true
                return appData
            }
            return nil
        }

        // 旧版加密格式：解密后自动升级为现代格式
        guard let decrypted = encryption.legacyDecrypt(parsed),
              let appData = decodePlainJSON(decrypted) else {
            return nil
        }
        _ = encryption.loadOrCreateMasterKey()
        // 显式写回解码结果；此刻 self.data 尚未更新，不能调用 save()
        saveData(appData, to: fileURL)
        return appData
    }

    private func decodePlainJSON(_ data: Data) -> AppData? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: Data(trimmed.utf8))
    }

    // MARK: - 保存（加密）
    func save() {
        guard hasBoundFile, currentFileURL != nil, !isLocked else { return }
        saveData(data, to: fileURL)
    }

    /// 保存数据到指定路径（加密）
    private func saveData(_ appData: AppData, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(appData)

            let masterKey = encryption.loadOrCreateMasterKey()
            guard let encrypted = encryption.encrypt(
                jsonData,
                masterKey: masterKey,
                wrap: encryption.storedKeyWrap
            ) else {
                print("加密失败")
                return
            }

            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            try encrypted.write(to: url, options: .atomic)
        } catch {
            print("保存失败: \(error)")
        }
    }

    // MARK: - 迁移口令

    @discardableResult
    func setMigrationPassphrase(_ passphrase: String) -> Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let masterKey = encryption.loadOrCreateMasterKey()
        guard let wrap = encryption.makeKeyWrap(masterKey: masterKey, passphrase: trimmed) else {
            return false
        }
        encryption.setStoredKeyWrap(wrap)
        hasMigrationPassphrase = true
        save()
        return true
    }

    func clearMigrationPassphrase() {
        encryption.setStoredKeyWrap(nil)
        hasMigrationPassphrase = false
        save()
    }

    // MARK: - 重置
    func resetAll() {
        let target = currentFileURL ?? defaultFileURL
        try? FileManager.default.removeItem(at: target)
        data = AppData()
        savePath(nil)
        hasBoundFile = false
        isLocked = false
        isLoaded = false
    }

    // MARK: - 分组操作
    func addGroup(_ group: Group) {
        data.groups.append(group)
        save()
    }

    func updateGroup(_ group: Group) {
        if let idx = data.groups.firstIndex(where: { $0.id == group.id }) {
            data.groups[idx] = group
            save()
        }
    }

    func deleteGroup(id: String) {
        data.groups.removeAll { $0.id == id }
        data.cards.removeAll { $0.groupId == id }
        save()
    }

    func groupCount(for groupId: String) -> Int {
        data.cards.filter { $0.groupId == groupId }.count
    }

    // MARK: - 卡片操作
    func addCard(_ card: Card) {
        data.cards.append(card)
        save()
    }

    func updateCard(_ card: Card) {
        if let idx = data.cards.firstIndex(where: { $0.id == card.id }) {
            data.cards[idx] = card
            save()
        }
    }

    func deleteCard(id: String) {
        data.cards.removeAll { $0.id == id }
        save()
    }

    func cards(for groupId: String) -> [Card] {
        data.cards.filter { $0.groupId == groupId }
    }

    // MARK: - 工具
    func shortDomain(of url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - 弹窗

    private func promptForMasterKey(wrap: KeyWrap) -> Data? {
        let alert = NSAlert()
        alert.messageText = "需要迁移口令"
        alert.informativeText = encryption.cachedMasterKey() != nil
            ? "该数据文件来自其他设备。输入迁移口令后，本机钥匙串中的密钥会被替换；若本机其他数据文件未设置迁移口令，将无法再解锁。"
            : "该数据文件使用迁移口令保护，请输入口令以解锁。"
        alert.addButton(withTitle: "解锁")
        alert.addButton(withTitle: "取消")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "迁移口令"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let passphrase = field.stringValue
        guard let key = encryption.unwrapMasterKey(from: wrap, passphrase: passphrase) else {
            presentMessage("迁移口令不正确", "无法解锁数据文件，请重试。")
            return nil
        }
        encryption.storeMasterKey(key)
        return key
    }

    private func presentUnlockFailure() {
        presentMessage(
            "数据文件已锁定",
            "无法解密当前数据文件。为保护数据，编辑已暂时禁用，不会写回覆盖。请确认迁移口令，或重新绑定正确的数据文件。"
        )
    }

    private func presentMessage(_ title: String, _ message: String) {
        presentAlert(title, message)
    }

    static func defaultAlertPresenter(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
