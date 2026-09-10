import Foundation
import Sparkle

// MARK: - Sparkle 自动更新服务

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    let updaterController: SPUStandardUpdaterController
    @Published private(set) var automaticallyChecksForUpdates: Bool = true

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }
}
