import AppKit
import Foundation
import Sparkle

// MARK: - Sparkle 自动更新服务

@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateService()

    private(set) var updaterController: SPUStandardUpdaterController!
    @Published private(set) var automaticallyChecksForUpdates: Bool = true

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    private override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Sparkle normally sends a standard quit event. Explicitly terminating here
        // also covers menu-bar-only and manually-created NSApplication lifecycles.
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
