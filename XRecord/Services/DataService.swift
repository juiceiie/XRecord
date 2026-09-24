import Foundation
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let xrecordDocument = UTType(filenameExtension: "xrecord")
        ?? UTType(exportedAs: "com.xrecord.document", conformingTo: .data)
}

enum BoundFileAvailability: Equatable {
    case unbound
    case local
    case iCloudAvailable
    case downloading
    case unavailable(String)

    var blocksAccess: Bool {
        switch self {
        case .downloading, .unavailable:
            return true
        case .unbound, .local, .iCloudAvailable:
            return false
        }
    }

    var description: String {
        switch self {
        case .unbound:
            return "未绑定数据文件"
        case .local:
            return "本地文件可用"
        case .iCloudAvailable:
            return "iCloud 文件已同步"
        case .downloading:
            return "正在从 iCloud 下载数据文件…"
        case .unavailable(let message):
            return message
        }
    }
}

private final class BoundFilePresenter: NSObject, NSFilePresenter {
    private(set) var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.xrecord.bound-file-presenter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    var onChange: (() -> Void)?
    var onMove: ((URL) -> Void)?
    var onDeletion: (() -> Void)?

    init(url: URL) {
        presentedItemURL = url
        super.init()
    }

    func updateURL(_ url: URL) {
        presentedItemURL = url
    }

    func presentedItemDidChange() {
        onChange?()
    }

    func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
        onMove?(newURL)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onDeletion?()
        completionHandler(nil)
    }
}

// MARK: - 数据持久化服务（读写本地 XRecord 密码本）

class DataService: ObservableObject {
    static let shared = DataService()

    @Published var data: AppData = AppData()
    @Published var isLoaded: Bool = false

    /// 是否已绑定数据文件
    @Published var hasBoundFile: Bool = false

    /// 文件无法解密时为 true，此时禁止写回以免覆盖数据
    @Published private(set) var isLocked: Bool = false

    /// 绑定文件的本地/iCloud 可用状态
    @Published private(set) var fileAvailability: BoundFileAvailability = .unbound

    /// 最近一次冲突保护结果；保留到用户重新绑定文件或下次冲突。
    @Published private(set) var conflictNotice: String?

    /// 最近一次从磁盘接收外部变更的时间。
    @Published private(set) var lastExternalRefreshDate: Date?

    /// 是否已设置同步与恢复口令
    @Published private(set) var hasMigrationPassphrase: Bool = false

    /// 加密服务（可注入以便测试）
    let encryption: EncryptionService

    /// 展示提示弹窗；测试时可替换为无操作实现
    var presentAlert: (_ title: String, _ message: String) -> Void

    // 绑定的文件路径（UserDefaults 持久化）
    private let savedPathKey = "xrecord_file_path"
    private let defaults: UserDefaults
    @Published private(set) var currentFileURL: URL?

    /// 旧格式首次写成新格式前保留原始字节，确保迁移始终可回退。
    private var pendingMigrationBackup: Data?

    /// 用于区分自己的写入和其他设备/进程写入，并保护未成功落盘的数据。
    private var lastKnownFileData: Data?
    private var lastSyncedData: AppData?
    private var filePresenter: BoundFilePresenter?
    private var availabilityPollWorkItem: DispatchWorkItem?
    private var externalReloadWorkItem: DispatchWorkItem?
    private var isWritingBoundFile = false

    /// 同一次运行中不重复打扰用户；下次启动仍可再次选择。
    private var promptedLegacyPaths = Set<String>()

    /// 默认路径：~/Desktop/xrecord/XRecord.xrecord
    private var defaultFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Desktop/xrecord")
        return dir.appendingPathComponent("XRecord.xrecord")
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

    deinit {
        stopMonitoring()
    }

    // MARK: - 路径持久化
    private func loadSavedPath() {
        guard let path = defaults.string(forKey: savedPathKey) else {
            hasBoundFile = false
            fileAvailability = .unbound
            return
        }

        let url = URL(fileURLWithPath: path)
        currentFileURL = url
        hasBoundFile = true
        startMonitoring(url)
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
        panel.title = "选择 XRecord 密码本"
        panel.allowedContentTypes = [.xrecordDocument, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if bind(to: url) {
            offerLegacyExtensionMigrationIfNeeded()
        }
    }

    /// 绑定文件；若无法解密则回滚绑定，避免误覆盖
    @discardableResult
    func bind(to url: URL) -> Bool {
        let previousURL = currentFileURL
        let previousBound = hasBoundFile
        let previousLocked = isLocked
        let previousData = data
        let previousMigrationBackup = pendingMigrationBackup
        let previousKnownFileData = lastKnownFileData
        let previousSyncedData = lastSyncedData

        stopMonitoring()
        savePath(url)
        hasBoundFile = true
        isLocked = false
        conflictNotice = nil
        startMonitoring(url)

        if !loadFromDisk() {
            // iCloud 占位文件正在下载时保留新绑定，下载完成后自动加载。
            if fileAvailability.blocksAccess && !isLocked {
                return true
            }
            stopMonitoring()
            savePath(previousURL)
            hasBoundFile = previousBound
            isLocked = previousLocked
            data = previousData
            pendingMigrationBackup = previousMigrationBackup
            lastKnownFileData = previousKnownFileData
            lastSyncedData = previousSyncedData
            if let previousURL, previousBound {
                startMonitoring(previousURL)
                refreshFileAvailability()
            } else {
                fileAvailability = .unbound
            }
            return false
        }
        return true
    }

    func createNewFile() {
        let panel = NSSavePanel()
        panel.title = "创建新的 XRecord 密码本"
        panel.nameFieldStringValue = "XRecord.xrecord"
        panel.allowedContentTypes = [.xrecordDocument]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        createFile(at: url)
    }

    /// 在指定位置创建新的数据文件（供文件面板与测试复用）
    func createFile(at url: URL) {
        let initialData = AppData()
        guard saveData(initialData, to: url) else { return }

        stopMonitoring()
        savePath(url)
        data = initialData
        lastKnownFileData = try? coordinatedRead(from: url)
        lastSyncedData = initialData
        pendingMigrationBackup = nil
        isLocked = false
        hasBoundFile = true
        isLoaded = true
        conflictNotice = nil
        startMonitoring(url)
        refreshFileAvailability()
    }

    /// 将当前绑定的旧 .txt 密码本安全改名为 .xrecord，不修改文件内容。
    @discardableResult
    func renameBoundFileToXRecord() -> Bool {
        guard let sourceURL = currentFileURL,
              sourceURL.pathExtension.lowercased() == "txt" else {
            return false
        }

        let destinationURL = sourceURL
            .deletingPathExtension()
            .appendingPathExtension("xrecord")

        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            presentMessage(
                "无法修改文件名",
                "同一位置已经存在 \(destinationURL.lastPathComponent)。原密码本和绑定路径均未更改。"
            )
            return false
        }

        do {
            stopMonitoring()
            try coordinatedMove(from: sourceURL, to: destinationURL)
            savePath(destinationURL)
            startMonitoring(destinationURL)
            refreshFileAvailability()
            return true
        } catch {
            startMonitoring(sourceURL)
            refreshFileAvailability()
            presentMessage(
                "无法修改文件名",
                "原密码本和绑定路径均未更改：\(error.localizedDescription)"
            )
            return false
        }
    }

    /// 对已成功解锁的旧 .txt 密码本给出一次改名选择。
    func offerLegacyExtensionMigrationIfNeeded() {
        guard hasBoundFile,
              !isLocked,
              let legacyURL = currentFileURL,
              legacyURL.pathExtension.lowercased() == "txt",
              !promptedLegacyPaths.contains(legacyURL.path) else {
            return
        }
        promptedLegacyPaths.insert(legacyURL.path)

        let alert = NSAlert()
        alert.messageText = "将密码本改为 .xrecord 文件？"
        alert.informativeText = "只会修改文件扩展名，不会更改或重新加密密码本内容。修改后 XRecord 会自动绑定新文件。"
        alert.addButton(withTitle: "修改为 .xrecord")
        alert.addButton(withTitle: "以后再说")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if renameBoundFileToXRecord(), let renamedURL = currentFileURL {
            presentMessage(
                "修改完成",
                "密码本已改名为 \(renamedURL.lastPathComponent)，数据内容保持不变。"
            )
        }
    }

    // MARK: - 加载（解密）
    func load() {
        _ = loadFromDisk()
    }

    func retryFileAccess() {
        refreshFileAvailability()
        guard !fileAvailability.blocksAccess else { return }
        _ = loadFromDisk()
    }

    /// 解锁已绑定的文件（供加锁界面重试）
    func retryUnlock() {
        isLocked = false
        _ = loadFromDisk()
    }

    /// 解除绑定，回到绑定文件界面
    func unbindForReselect() {
        stopMonitoring()
        savePath(nil)
        hasBoundFile = false
        isLocked = false
        data = AppData()
        lastKnownFileData = nil
        lastSyncedData = nil
        conflictNotice = nil
        fileAvailability = .unbound
        isLoaded = false
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard hasBoundFile, currentFileURL != nil else { return false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            fileAvailability = .unavailable("数据文件暂不可用或已被移动")
            isLoaded = true
            return false
        }

        guard prepareFileForReading() else {
            isLoaded = true
            return false
        }

        do {
            let blob = try coordinatedRead(from: fileURL)
            if blob.isEmpty {
                data = AppData()
                lastKnownFileData = blob
                lastSyncedData = data
                pendingMigrationBackup = nil
                isLocked = false
                isLoaded = true
                refreshFileAvailability()
                return true
            }

            if let decoded = decode(blob) {
                data = decoded.data
                lastKnownFileData = blob
                lastSyncedData = decoded.data
                pendingMigrationBackup = decoded.needsMigrationBackup ? blob : nil
                isLocked = false
                isLoaded = true
                refreshFileAvailability()
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

    private struct DecodedFile {
        let data: AppData
        let needsMigrationBackup: Bool
    }

    /// 将磁盘内容解码为 AppData；失败返回 nil（不清空数据）
    private func decode(_ blob: Data) -> DecodedFile? {
        // 1) 旧版本的明文 JSON
        if let plain = decodePlainJSON(blob) {
            return DecodedFile(data: plain, needsMigrationBackup: true)
        }

        guard let parsed = encryption.parse(blob) else { return nil }

        if parsed.isModern {
            // 1) 本机钥匙串已有主密钥
            if let key = encryption.cachedMasterKey(),
               let decrypted = encryption.decryptPayload(parsed, masterKey: key),
               let appData = decodePlainJSON(decrypted) {
                return DecodedFile(data: appData, needsMigrationBackup: false)
            }

            // 2) 用同步与恢复口令解出主密钥
            if let wrap = parsed.keyWrap ?? encryption.storedKeyWrap,
               let key = promptForMasterKey(wrap: wrap),
               let decrypted = encryption.decryptPayload(parsed, masterKey: key),
               let appData = decodePlainJSON(decrypted) {
                if !encryption.storeMasterKey(key) {
                    presentMessage(
                        "钥匙串保存失败",
                        "数据已成功解锁，但主密钥未能保存到 macOS 钥匙串。下次启动时需要再次输入同步与恢复口令。"
                    )
                }
                encryption.setStoredKeyWrap(wrap)
                hasMigrationPassphrase = true
                return DecodedFile(data: appData, needsMigrationBackup: false)
            }
            return nil
        }

        // 旧版加密格式：解密后自动升级为现代格式
        guard let decrypted = encryption.legacyDecrypt(parsed),
              let appData = decodePlainJSON(decrypted) else {
            return nil
        }
        return DecodedFile(data: appData, needsMigrationBackup: true)
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
    @discardableResult
    func save() -> Bool {
        guard hasBoundFile,
              currentFileURL != nil,
              !isLocked,
              !fileAvailability.blocksAccess else { return false }
        if diskChangedSinceLastSync() {
            reloadAfterExternalChange()
            return false
        }
        guard createMigrationBackupIfNeeded(for: fileURL) else { return false }
        guard saveData(data, to: fileURL) else { return false }
        lastSyncedData = data
        pendingMigrationBackup = nil
        refreshFileAvailability()
        return true
    }

    private func diskChangedSinceLastSync() -> Bool {
        guard let lastKnownFileData,
              FileManager.default.fileExists(atPath: fileURL.path),
              let diskData = try? coordinatedRead(from: fileURL) else {
            return false
        }
        return diskData != lastKnownFileData
    }

    /// 保存数据到指定路径（加密）
    @discardableResult
    private func saveData(_ appData: AppData, to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(appData)

            guard let masterKey = encryption.loadOrCreateMasterKey() else {
                presentMessage(
                    "无法保存数据",
                    "主密钥未能写入 macOS 钥匙串。为避免生成无法恢复的数据文件，本次保存已取消。"
                )
                return false
            }
            guard let encrypted = encryption.encrypt(
                jsonData,
                masterKey: masterKey,
                wrap: encryption.storedKeyWrap
            ) else {
                print("加密失败")
                presentMessage("无法保存数据", "数据加密失败，原文件未被覆盖。")
                return false
            }

            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            try coordinatedWrite(encrypted, to: url)
            if url.standardizedFileURL == currentFileURL?.standardizedFileURL {
                lastKnownFileData = encrypted
            }
            return true
        } catch {
            print("保存失败: \(error)")
            presentMessage("无法保存数据", "写入数据文件失败，原文件未被覆盖：\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 文件协调与外部变更

    private enum CoordinatedFileError: LocalizedError {
        case noResult

        var errorDescription: String? {
            "系统未返回可用的数据文件"
        }
    }

    private func coordinator(for url: URL) -> NSFileCoordinator {
        let usesPresenter = url.standardizedFileURL == currentFileURL?.standardizedFileURL
        return NSFileCoordinator(filePresenter: usesPresenter ? filePresenter : nil)
    }

    private func coordinatedRead(from url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator(for: url).coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CoordinatedFileError.noResult }
        return try result.get()
    }

    private func coordinatedWrite(_ contents: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var coordinationError: NSError?
        var writeError: Error?
        let options: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path)
            ? .forReplacing
            : []
        let writingBoundFile = url.standardizedFileURL == currentFileURL?.standardizedFileURL
        if writingBoundFile { isWritingBoundFile = true }
        defer { if writingBoundFile { isWritingBoundFile = false } }

        coordinator(for: url).coordinate(writingItemAt: url, options: options, error: &coordinationError) {
            coordinatedURL in
            do {
                try contents.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func coordinatedMove(from sourceURL: URL, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.moveItem(at: coordinatedURL, to: destinationURL)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    private func coordinatedDelete(at url: URL) throws {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                deleteError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let deleteError { throw deleteError }
    }

    private func startMonitoring(_ url: URL) {
        stopMonitoring()
        let presenter = BoundFilePresenter(url: url)
        presenter.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleExternalReload() }
        }
        presenter.onMove = { [weak self] newURL in
            DispatchQueue.main.async { self?.handlePresentedItemMove(to: newURL) }
        }
        presenter.onDeletion = { [weak self] in
            DispatchQueue.main.async {
                self?.fileAvailability = .unavailable("数据文件已被移动或删除")
            }
        }
        filePresenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func stopMonitoring() {
        availabilityPollWorkItem?.cancel()
        availabilityPollWorkItem = nil
        externalReloadWorkItem?.cancel()
        externalReloadWorkItem = nil
        if let filePresenter {
            NSFileCoordinator.removeFilePresenter(filePresenter)
        }
        filePresenter = nil
    }

    private func handlePresentedItemMove(to newURL: URL) {
        savePath(newURL)
        filePresenter?.updateURL(newURL)
        refreshFileAvailability()
    }

    private func scheduleExternalReload() {
        guard !isWritingBoundFile else { return }
        externalReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadAfterExternalChange()
        }
        externalReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func refreshFileAvailability() {
        guard hasBoundFile, let url = currentFileURL else {
            fileAvailability = .unbound
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            fileAvailability = .unavailable("数据文件暂不可用或已被移动")
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            guard values.isUbiquitousItem == true else {
                fileAvailability = .local
                return
            }

            if values.ubiquitousItemIsDownloading == true
                || values.ubiquitousItemDownloadingStatus == .notDownloaded {
                fileAvailability = .downloading
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                    scheduleAvailabilityPoll()
                } catch {
                    fileAvailability = .unavailable("无法下载 iCloud 文件：\(error.localizedDescription)")
                }
            } else {
                fileAvailability = .iCloudAvailable
            }
        } catch {
            fileAvailability = .unavailable("无法读取数据文件状态：\(error.localizedDescription)")
        }
    }

    private func prepareFileForReading() -> Bool {
        refreshFileAvailability()
        return !fileAvailability.blocksAccess
    }

    private func scheduleAvailabilityPoll() {
        availabilityPollWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshFileAvailability()
            if self.fileAvailability == .downloading {
                self.scheduleAvailabilityPoll()
            } else if !self.fileAvailability.blocksAccess {
                if self.lastKnownFileData == nil {
                    _ = self.loadFromDisk()
                } else {
                    self.reloadAfterExternalChange()
                }
            }
        }
        availabilityPollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    /// NSFilePresenter 回调与测试共用：只在磁盘字节确实改变时刷新数据。
    func reloadAfterExternalChange() {
        guard hasBoundFile, let url = currentFileURL, !isWritingBoundFile else { return }
        refreshFileAvailability()
        guard !fileAvailability.blocksAccess else { return }

        do {
            let conflictCount = preserveUnresolvedConflictVersions(at: url)
            let incomingData = try coordinatedRead(from: url)
            guard incomingData != lastKnownFileData else {
                if conflictCount > 0 {
                    reportPreservedConflicts(count: conflictCount)
                }
                return
            }
            guard let decoded = decode(incomingData) else {
                fileAvailability = .unavailable("同步后的数据文件暂时无法解密")
                return
            }

            var backupURLs: [URL] = []
            if let lastSyncedData, data != lastSyncedData,
               let backupURL = createConflictBackup(of: data, beside: url, label: "本机未保存") {
                backupURLs.append(backupURL)
            }

            data = decoded.data
            lastKnownFileData = incomingData
            lastSyncedData = decoded.data
            pendingMigrationBackup = decoded.needsMigrationBackup ? incomingData : nil
            isLocked = false
            isLoaded = true
            lastExternalRefreshDate = Date()
            refreshFileAvailability()

            if conflictCount > 0 || !backupURLs.isEmpty {
                reportPreservedConflicts(count: conflictCount + backupURLs.count)
            }
        } catch {
            fileAvailability = .unavailable("无法读取同步后的文件：\(error.localizedDescription)")
        }
    }

    private func reportPreservedConflicts(count: Int) {
        conflictNotice = "检测到同步冲突，已保留 \(count) 个备份文件"
        presentMessage(
            "已保护同步冲突数据",
            "XRecord 已在当前密码本旁保留冲突备份，并载入 iCloud 的最新版本。"
        )
    }

    @discardableResult
    private func preserveUnresolvedConflictVersions(at url: URL) -> Int {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !versions.isEmpty else { return 0 }

        var preserved = 0
        for (index, version) in versions.enumerated() {
            guard let contents = try? Data(contentsOf: version.url),
                  createConflictBackup(contents, beside: url, label: "iCloud-\(index + 1)") != nil else {
                continue
            }
            version.isResolved = true
            preserved += 1
        }
        return preserved
    }

    private func createConflictBackup(of appData: AppData, beside url: URL, label: String) -> URL? {
        let backupURL = conflictBackupURL(beside: url, label: label)
        return saveData(appData, to: backupURL) ? backupURL : nil
    }

    private func createConflictBackup(_ contents: Data, beside url: URL, label: String) -> URL? {
        let backupURL = conflictBackupURL(beside: url, label: label)
        do {
            try coordinatedWrite(contents, to: backupURL)
            return backupURL
        } catch {
            print("保存冲突备份失败: \(error)")
            return nil
        }
    }

    private func conflictBackupURL(beside url: URL, label: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = label.replacingOccurrences(of: " ", with: "-")
        let baseName = url.deletingPathExtension().lastPathComponent
        var candidate = url.deletingLastPathComponent().appendingPathComponent(
            "\(baseName)-conflict-\(formatter.string(from: Date()))-\(safeLabel).xrecord"
        )
        if FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent(
                "\(baseName)-conflict-\(UUID().uuidString)-\(safeLabel).xrecord"
            )
        }
        return candidate
    }

    private func createMigrationBackupIfNeeded(for url: URL) -> Bool {
        guard let originalData = pendingMigrationBackup else { return true }

        let preferredURL = url.appendingPathExtension("xrecord-v1-backup")
        var backupURL = preferredURL

        if FileManager.default.fileExists(atPath: preferredURL.path) {
            if let existing = try? Data(contentsOf: preferredURL), existing == originalData {
                return true
            }
            backupURL = url.appendingPathExtension("xrecord-v1-backup-\(UUID().uuidString)")
        }

        do {
            try originalData.write(to: backupURL, options: .withoutOverwriting)
            return true
        } catch {
            presentMessage(
                "旧数据备份失败",
                "升级加密格式前无法创建备份，已取消写入，原文件保持不变：\(error.localizedDescription)"
            )
            return false
        }
    }

    // MARK: - 同步与恢复口令

    @discardableResult
    func setMigrationPassphrase(_ passphrase: String) -> Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let masterKey = encryption.loadOrCreateMasterKey() else {
            presentMessage("无法设置同步与恢复口令", "主密钥未能写入 macOS 钥匙串。")
            return false
        }
        guard let wrap = encryption.makeKeyWrap(masterKey: masterKey, passphrase: trimmed) else {
            return false
        }
        let previousWrap = encryption.storedKeyWrap
        let previousState = hasMigrationPassphrase
        encryption.setStoredKeyWrap(wrap)
        hasMigrationPassphrase = true
        guard save() else {
            encryption.setStoredKeyWrap(previousWrap)
            hasMigrationPassphrase = previousState
            return false
        }
        return true
    }

    func clearMigrationPassphrase() {
        let previousWrap = encryption.storedKeyWrap
        encryption.setStoredKeyWrap(nil)
        hasMigrationPassphrase = false
        if !save() {
            encryption.setStoredKeyWrap(previousWrap)
            hasMigrationPassphrase = previousWrap != nil
        }
    }

    // MARK: - 重置
    func resetAll() {
        let target = currentFileURL ?? defaultFileURL
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                stopMonitoring()
                try coordinatedDelete(at: target)
            }
        } catch {
            presentMessage("无法重置数据", "数据文件删除失败，未进行重置：\(error.localizedDescription)")
            return
        }
        data = AppData()
        lastKnownFileData = nil
        lastSyncedData = nil
        conflictNotice = nil
        pendingMigrationBackup = nil
        savePath(nil)
        hasBoundFile = false
        isLocked = false
        fileAvailability = .unbound
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

    /// 将分组拖到目标分组所在位置；向下拖动时放在目标之后，向上拖动时放在目标之前。
    @discardableResult
    func moveGroup(id draggedId: String, onto targetId: String) -> Bool {
        guard draggedId != targetId,
              let fromIndex = data.groups.firstIndex(where: { $0.id == draggedId }),
              let originalTargetIndex = data.groups.firstIndex(where: { $0.id == targetId }) else {
            return false
        }

        let movingDown = fromIndex < originalTargetIndex
        let movedGroup = data.groups.remove(at: fromIndex)
        guard let targetIndex = data.groups.firstIndex(where: { $0.id == targetId }) else {
            data.groups.insert(movedGroup, at: fromIndex)
            return false
        }

        let insertionIndex = movingDown ? targetIndex + 1 : targetIndex
        data.groups.insert(movedGroup, at: insertionIndex)
        save()
        return true
    }

    func deleteGroup(id: String) {
        // 分组下的条目移入回收站，便于恢复
        let now = Date()
        for idx in data.cards.indices where data.cards[idx].groupId == id && !data.cards[idx].isTrashed {
            data.cards[idx].deletedAt = now
        }
        data.groups.removeAll { $0.id == id }
        save()
    }

    func groupCount(for groupId: String) -> Int {
        data.cards.filter { $0.groupId == groupId && !$0.isTrashed }.count
    }

    // MARK: - 卡片操作

    /// 先更新内存，再尝试落盘；普通写入失败时回滚，外部版本已载入时保留外部版本。
    private func commitCardMutation(_ mutation: (inout AppData) -> Void) -> Bool {
        let previousData = data
        let refreshDateBeforeSave = lastExternalRefreshDate
        mutation(&data)

        guard !save() else { return true }
        if lastExternalRefreshDate == refreshDateBeforeSave {
            data = previousData
        }
        return false
    }

    @discardableResult
    func addCard(_ card: Card) -> Bool {
        var cardToAdd = card
        if cardToAdd.updatedAt == nil {
            cardToAdd.updatedAt = cardToAdd.createdAt
        }
        return commitCardMutation { $0.cards.append(cardToAdd) }
    }

    @discardableResult
    func updateCard(_ card: Card) -> Bool {
        guard let idx = data.cards.firstIndex(where: { $0.id == card.id }) else {
            return false
        }
        var updatedCard = card
        let existingCard = data.cards[idx]
        updatedCard.updatedAt = updatedCard.hasContentChanges(comparedTo: existingCard)
            ? Date()
            : existingCard.updatedAt
        return commitCardMutation { $0.cards[idx] = updatedCard }
    }

    func deleteCard(id: String) {
        data.cards.removeAll { $0.id == id }
        save()
    }

    func cards(for groupId: String) -> [Card] {
        data.cards.filter { $0.groupId == groupId && !$0.isTrashed }
    }

    // MARK: - 回收站

    /// 当前未被移入回收站的条目
    var activeCards: [Card] {
        data.cards.filter { !$0.isTrashed }
    }

    /// 将条目移入回收站（软删除）
    func moveCardToTrash(id: String) {
        guard let idx = data.cards.firstIndex(where: { $0.id == id }) else { return }
        data.cards[idx].deletedAt = Date()
        save()
    }

    /// 从回收站恢复条目
    func restoreCard(id: String) {
        guard let idx = data.cards.firstIndex(where: { $0.id == id }) else { return }

        // 删除分组会把其条目一并移入回收站。恢复这类条目时，不能继续
        // 引用已经不存在的分组，否则条目会成为只能在“全部”中看到的孤立数据。
        if !data.groups.contains(where: { $0.id == data.cards[idx].groupId }) {
            if let fallbackGroup = data.groups.first {
                data.cards[idx].groupId = fallbackGroup.id
            } else {
                let recoveredGroup = Group(name: "已恢复", colorHex: Group.defaultColors[0])
                data.groups.append(recoveredGroup)
                data.cards[idx].groupId = recoveredGroup.id
            }
        }

        data.cards[idx].deletedAt = nil
        save()
    }

    /// 彻底删除单个条目
    func permanentlyDeleteCard(id: String) {
        data.cards.removeAll { $0.id == id }
        save()
    }

    /// 清空回收站
    func emptyTrash() {
        data.cards.removeAll { $0.isTrashed }
        save()
    }

    /// 回收站中的条目（按删除时间倒序）
    var trashedCards: [Card] {
        data.cards
            .filter { $0.isTrashed }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var trashedCount: Int {
        data.cards.reduce(0) { $0 + ($1.isTrashed ? 1 : 0) }
    }

    // MARK: - 收藏夹

    /// 切换条目的收藏状态
    @discardableResult
    func toggleFavorite(cardID: String) -> Bool {
        guard let idx = data.cards.firstIndex(where: { $0.id == cardID }) else { return false }
        return commitCardMutation {
            $0.cards[idx].isFavorite = !$0.cards[idx].isFavorited
        }
    }

    var favoriteCards: [Card] {
        data.cards.filter { $0.isFavorited && !$0.isTrashed }
    }

    var favoriteCount: Int {
        data.cards.reduce(0) { $0 + ($1.isFavorited && !$1.isTrashed ? 1 : 0) }
    }

    // MARK: - 工具
    func shortDomain(of url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - 弹窗

    private func promptForMasterKey(wrap: KeyWrap) -> Data? {
        let alert = NSAlert()
        alert.messageText = "需要同步与恢复口令"
        alert.informativeText = encryption.cachedMasterKey() != nil
            ? "该数据文件来自其他设备。输入同步与恢复口令后，本机钥匙串中的密钥会被替换；若本机其他数据文件未设置恢复口令，将无法再解锁。"
            : "该数据文件使用同步与恢复口令保护，请输入口令以解锁。"
        alert.addButton(withTitle: "解锁")
        alert.addButton(withTitle: "取消")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "同步与恢复口令"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let passphrase = field.stringValue
        guard let key = encryption.unwrapMasterKey(from: wrap, passphrase: passphrase) else {
            presentMessage("同步与恢复口令不正确", "无法解锁数据文件，请重试。")
            return nil
        }
        return key
    }

    private func presentUnlockFailure() {
        presentMessage(
            "数据文件已锁定",
            "无法解密当前数据文件。为保护数据，编辑已暂时禁用，不会写回覆盖。请确认同步与恢复口令，或重新绑定正确的数据文件。"
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
