import SwiftUI
import AppKit

// MARK: - 剪贴板

enum Clipboard {
    /// 复制文本，并在指定秒数后自动清除（若期间剪贴板未被其他内容替换）
    static func copy(_ text: String, clearAfter seconds: TimeInterval = 30) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
    }
}

// MARK: - 链接浏览器偏好

enum PreferredBrowserStore {
    static let pathKey = "preferredBrowserApplicationPath"

    static var applicationPath: String? {
        let path = UserDefaults.standard.string(forKey: pathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    static var availableApplicationURL: URL? {
        guard let path = applicationPath,
              path.lowercased().hasSuffix(".app"),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static func select(applicationURL: URL) {
        UserDefaults.standard.set(applicationURL.path, forKey: pathKey)
    }

    static func useSystemDefault() {
        UserDefaults.standard.removeObject(forKey: pathKey)
    }
}

enum CredentialPanelPreferences {
    static let isEnabledKey = "credentialPanelEnabled"
    static let autoDismissSecondsKey = "credentialPanelAutoDismissSeconds"
    static let defaultAutoDismissSeconds = -1

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: isEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    /// 浮窗出现后无操作多少秒自动消失；<= 0 表示不自动消失
    static var autoDismissSeconds: Int {
        guard UserDefaults.standard.object(forKey: autoDismissSecondsKey) != nil else {
            return defaultAutoDismissSeconds
        }
        return UserDefaults.standard.integer(forKey: autoDismissSecondsKey)
    }

    static func setAutoDismissSeconds(_ value: Int) {
        UserDefaults.standard.set(value, forKey: autoDismissSecondsKey)
    }
}

// MARK: - 可打开目标（网址或 macOS 应用）

enum LaunchTarget {
    static func resolvedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }

    static func isApplication(_ value: String) -> Bool {
        guard let url = resolvedURL(from: value), url.isFileURL else { return false }
        return url.pathExtension.lowercased() == "app"
    }

    static func displayName(for value: String, dataService: DataService) -> String {
        guard let url = resolvedURL(from: value) else { return value }
        if url.isFileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return dataService.shortDomain(of: url.absoluteString)
    }

    @discardableResult
    static func open(_ value: String, cardID: String? = nil) -> Bool {
        guard let url = resolvedURL(from: value) else { return false }

        guard isWebLink(url), let browserURL = PreferredBrowserStore.availableApplicationURL else {
            return openWithSystemDefault(url, cardID: cardID)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browserURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    recordRecentLaunch(cardID)
                } else {
                    _ = openWithSystemDefault(url, cardID: cardID)
                }
            }
        }
        return true
    }

    private static func isWebLink(_ url: URL) -> Bool {
        guard !url.isFileURL else { return false }
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    @discardableResult
    private static func openWithSystemDefault(_ url: URL, cardID: String?) -> Bool {
        let didOpen = NSWorkspace.shared.open(url)
        if didOpen {
            recordRecentLaunch(cardID)
        }
        return didOpen
    }

    private static func recordRecentLaunch(_ cardID: String?) {
        if let cardID {
            RecentLaunchStore.record(cardID: cardID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .didOpenLaunchTarget, object: cardID)
            }
        }
    }
}

// MARK: - 最近打开记录

enum RecentLaunchStore {
    private static let key = "recentlyOpenedCardIDs"
    private static let maximumStoredCount = 30

    static func record(cardID: String) {
        var cardIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
        cardIDs.removeAll { $0 == cardID }
        cardIDs.insert(cardID, at: 0)
        UserDefaults.standard.set(Array(cardIDs.prefix(maximumStoredCount)), forKey: key)
    }

    static func cards(in data: AppData, limit: Int) -> [Card] {
        let cardsByID = Dictionary(uniqueKeysWithValues: data.cards.map { ($0.id, $0) })
        let cardIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
        return cardIDs.compactMap { cardsByID[$0] }.prefix(limit).map { $0 }
    }
}

// MARK: - Color 扩展：Hex 支持

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    var hexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }

    /// 与 hexString 相同，方便调用
    func toHex() -> String { hexString }
}

// MARK: - NSColor 扩展

extension NSColor {
    convenience init(hex: String) {
        let color = Color(hex: hex)
        self.init(color)
    }
}
