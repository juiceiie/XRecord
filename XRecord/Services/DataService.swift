import Foundation
import AppKit

// MARK: - 数据持久化服务（读写本地 record.txt）

class DataService: ObservableObject {
    static let shared = DataService()

    @Published var data: AppData = AppData()
    @Published var isLoaded: Bool = false

    /// 是否已绑定数据文件
    @Published var hasBoundFile: Bool = false

    // 绑定的文件路径（UserDefaults 持久化）
    private let savedPathKey = "xrecord_file_path"
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
        loadSavedPath()
        // 不再自动加载，等待用户绑定文件
    }

    // MARK: - 路径持久化
    private func loadSavedPath() {
        if let path = UserDefaults.standard.string(forKey: savedPathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                currentFileURL = url
                hasBoundFile = true
                load()
            } else {
                UserDefaults.standard.removeObject(forKey: savedPathKey)
                hasBoundFile = false
            }
        } else {
            hasBoundFile = false
        }
    }

    private func savePath(_ url: URL?) {
        if let url = url {
            UserDefaults.standard.set(url.path, forKey: savedPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedPathKey)
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

        if panel.runModal() == .OK, let url = panel.url {
            savePath(url)
            hasBoundFile = true
            load()
        }
    }

    func createNewFile() {
        let panel = NSSavePanel()
        panel.title = "创建新的数据文件"
        panel.nameFieldStringValue = "record.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            savePath(url)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 创建初始空数据文件
            let initialData = AppData()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonData = try? encoder.encode(initialData),
               let jsonText = String(data: jsonData, encoding: .utf8) {
                try? jsonText.write(to: url, atomically: true, encoding: .utf8)
            }
            hasBoundFile = true
            data = AppData()
            isLoaded = true
        }
    }

    // MARK: - 加载
    func load() {
        guard hasBoundFile, let _ = currentFileURL else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    data = try decoder.decode(AppData.self, from: Data(text.utf8))
                } else {
                    data = AppData()
                }
            } catch {
                data = AppData()
            }
        } else {
            data = AppData()
        }
        isLoaded = true
    }

    // MARK: - 保存
    func save() {
        guard hasBoundFile, let _ = currentFileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)
            let text = String(data: jsonData, encoding: .utf8) ?? "{}"

            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("保存失败: \(error)")
        }
    }

    // MARK: - 重置
    func resetAll() {
        data = AppData()
        savePath(nil)
        hasBoundFile = false
        try? FileManager.default.removeItem(at: defaultFileURL)
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
}
