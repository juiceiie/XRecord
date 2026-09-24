import SwiftUI
import AppKit
import ServiceManagement

// MARK: - 开机自动启动

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        do {
            if enabled {
                guard status == .notRegistered || status == .notFound else {
                    refresh()
                    return
                }
                try service.register()
            } else {
                guard status != .notRegistered else {
                    refresh()
                    return
                }
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func clearError() {
        errorMessage = nil
    }
}

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

// MARK: - 密码输入偏好

enum PasswordInputPreferences {
    static let forcesRomanInputKey = "passwordInputForcesRomanInput"
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

    static func isWebAddress(_ value: String) -> Bool {
        guard let url = resolvedURL(from: value) else { return false }
        return isWebLink(url)
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
        return cardIDs.compactMap { cardsByID[$0] }
            .filter { !$0.isTrashed }
            .prefix(limit)
            .map { $0 }
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

// MARK: - 字体大小偏好

enum AppFontSizeLevel: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        case .extraLarge: return "特大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .standard: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

enum AppearancePreferences {
    static let fontSizeLevelKey = "appFontSizeLevel"
    static let cardListStyleKey = "cardListStyle"

    static var fontSizeLevel: AppFontSizeLevel {
        guard let raw = UserDefaults.standard.string(forKey: fontSizeLevelKey),
              let level = AppFontSizeLevel(rawValue: raw) else {
            return .standard
        }
        return level
    }

    static var fontScale: CGFloat { fontSizeLevel.scale }
}

enum CardListStyle: String, CaseIterable, Identifiable {
    case regular
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "常规卡片"
        case .compact: return "极简卡片"
        }
    }
}

// MARK: - 绑定文件状态展示

extension BoundFileAvailability {
    var iconName: String {
        switch self {
        case .unbound: return "questionmark.circle"
        case .local: return "checkmark.circle.fill"
        case .iCloudAvailable: return "checkmark.icloud.fill"
        case .downloading: return "icloud.and.arrow.down"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .unavailable: return .orange
        case .downloading: return .blue
        case .unbound: return .secondary
        case .local, .iCloudAvailable: return .green
        }
    }

}

// MARK: - 全局字体缩放

private struct AppFontScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var appFontScale: CGFloat {
        get { self[AppFontScaleEnvironmentKey.self] }
        set { self[AppFontScaleEnvironmentKey.self] = newValue }
    }
}

private struct AppFontScaleModifier: ViewModifier {
    @AppStorage(AppearancePreferences.fontSizeLevelKey)
    private var levelRaw = AppFontSizeLevel.standard.rawValue

    func body(content: Content) -> some View {
        let scale = (AppFontSizeLevel(rawValue: levelRaw) ?? .standard).scale
        return content.environment(\.appFontScale, scale)
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// 在窗口/页面根部调用，注入全局字体缩放比例
    func appFontSizeScaled() -> some View {
        modifier(AppFontScaleModifier())
    }

    /// 替代 `.font(.system(size:))`，按设置中的字体大小档位缩放
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

// MARK: - 条目展示模式

enum CardPresentationMode: String, CaseIterable, Identifiable {
    /// 添加/编辑/查看时弹出独立窗口或弹窗
    case popup
    /// 在主窗口右侧栏内完成添加/编辑/查看
    case threeColumn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .popup: return "弹窗模式"
        case .threeColumn: return "三段式"
        }
    }

    var detailDescription: String {
        switch self {
        case .popup: return "添加、编辑、查看条目时弹出独立窗口"
        case .threeColumn: return "在右侧分栏内完成添加、编辑与查看"
        }
    }
}

enum PresentationPreferences {
    static let modeKey = "cardPresentationMode"
    static let threeColumnWidthKey = "threeColumnPaneWidth"

    static var mode: CardPresentationMode {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = CardPresentationMode(rawValue: raw) else {
            return .popup
        }
        return mode
    }
}

// MARK: - 三段式背景层次

extension Color {
    /// 第一段：分类栏（浅灰）
    static let paneSidebarBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkAppearance
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor(calibratedWhite: 0.925, alpha: 1)
    })

    /// 第二段：条目栏（浅浅灰）
    static let paneListBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkAppearance
            ? NSColor(calibratedWhite: 0.15, alpha: 1)
            : NSColor(calibratedWhite: 0.965, alpha: 1)
    })

    /// 第三段：详情栏（白）
    static let paneDetailBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkAppearance
            ? NSColor(calibratedWhite: 0.19, alpha: 1)
            : NSColor(calibratedWhite: 1.0, alpha: 1)
    })
}

private extension NSAppearance {
    var isDarkAppearance: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - 获取承载窗口

/// 用于在主窗口内访问 NSWindow（例如动态调整最小尺寸）
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}
