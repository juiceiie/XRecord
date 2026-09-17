import SwiftUI
import AppKit

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
        let didOpen = NSWorkspace.shared.open(url)
        if didOpen, let cardID {
            RecentLaunchStore.record(cardID: cardID)
        }
        return didOpen
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
        guard let components = NSColor(self).cgColor.components else { return "#000000" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
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
