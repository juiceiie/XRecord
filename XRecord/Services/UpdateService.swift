import Foundation
import AppKit

// MARK: - 更新信息模型

struct AppRelease {
    let version: String       // "1.0.2"
    let tagName: String       // "v1.0.2"
    let releaseNotes: String
    let downloadURL: URL
}

// MARK: - 更新服务

@MainActor
class UpdateService: ObservableObject {

    static let shared = UpdateService()

    // 当前应用版本（从 Info.plist 读取）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // GitHub 仓库信息
    private let repoOwner = "juiceiie"
    private let repoName  = "XRecord"

    // 状态
    @Published var latestRelease: AppRelease? = nil
    @Published var hasUpdate: Bool = false
    @Published var isChecking: Bool = false
    @Published var lastCheckError: String? = nil

    // 忽略的版本
    private let ignoredVersionKey = "ignoredUpdateVersion"

    /// 永久忽略某个版本（存入 UserDefaults）
    func ignoreVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: ignoredVersionKey)
    }

    /// 检查某版本是否被永久忽略
    func isVersionIgnored(_ version: String) -> Bool {
        UserDefaults.standard.string(forKey: ignoredVersionKey) == version
    }

    /// 忽略后重新检查（发布时调用）
    func recheckAfterIgnore() {
        if let release = latestRelease {
            hasUpdate = isNewer(release.version, than: currentVersion) && !isVersionIgnored(release.version)
        }
    }

    private init() {}

    // MARK: - 检查更新

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        lastCheckError = nil

        Task {
            do {
                let release = try await fetchLatestRelease()
                self.latestRelease = release
                let newer = isNewer(release.version, than: currentVersion)
                let ignored = isVersionIgnored(release.version)
                self.hasUpdate = newer && !ignored
                LoggerService.shared.info("检查更新完成：最新版本 \(release.version)，当前版本 \(currentVersion)，需要更新：\(self.hasUpdate)，已忽略：\(ignored)")
            } catch {
                self.lastCheckError = error.localizedDescription
                LoggerService.shared.error("检查更新失败：\(error.localizedDescription)")
            }
            self.isChecking = false
        }
    }

    // MARK: - 打开下载页

    func openDownloadPage() {
        guard let release = latestRelease else {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!)
            return
        }
        NSWorkspace.shared.open(release.downloadURL)
    }

    // MARK: - 私有方法

    private func fetchLatestRelease() async throws -> AppRelease {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError("服务器返回错误")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw UpdateError.parseError
        }

        // 版本号：去掉 "v" 前缀
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let body = json["body"] as? String ?? ""

        // 找 DMG 下载链接
        var downloadURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                   let browserURL = asset["browser_download_url"] as? String,
                   let url = URL(string: browserURL) {
                    downloadURL = url
                    break
                }
            }
        }

        return AppRelease(
            version: version,
            tagName: tagName,
            releaseNotes: body,
            downloadURL: downloadURL
        )
    }

    /// 语义化版本比较：判断 newVer 是否比 currentVer 新
    private func isNewer(_ newVer: String, than currentVer: String) -> Bool {
        let new     = newVer.split(separator: ".").compactMap { Int($0) }
        let current = currentVer.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(new.count, current.count)
        for i in 0..<maxLen {
            let n = i < new.count     ? new[i]     : 0
            let c = i < current.count ? current[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }
}

// MARK: - 错误类型

enum UpdateError: LocalizedError {
    case invalidURL
    case networkError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "无效的 URL"
        case .networkError(let msg): return "网络错误：\(msg)"
        case .parseError:            return "解析响应失败"
        }
    }
}
