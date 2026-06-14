import BryanToolsShared
import Foundation

@MainActor
final class BryanToolsAutoStartController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let installedAppPath: String

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedAppPath: String = BryanToolsAutoStart.installedAppPath
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.installedAppPath = installedAppPath
        self.isEnabled = BryanToolsAutoStart.isEnabledByDefault(defaults: defaults)
    }

    func reconcile() {
        if isEnabled {
            enable()
        } else {
            disable()
        }
    }

    func updateEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: BryanToolsAutoStart.defaultsKey)
        reconcile()
    }

    private func enable() {
        guard fileManager.fileExists(atPath: installedAppPath) else {
            lastErrorMessage = "Install Bryan Tools to /Applications before enabling auto start."
            return
        }

        do {
            let launchAgentURL = BryanToolsAutoStart.launchAgentURL(homeDirectory: homeDirectory)
            try fileManager.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try BryanToolsAutoStart.launchAgentPlistData(appPath: installedAppPath)
            try data.write(to: launchAgentURL, options: .atomic)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func disable() {
        do {
            let launchAgentURL = BryanToolsAutoStart.launchAgentURL(homeDirectory: homeDirectory)
            if fileManager.fileExists(atPath: launchAgentURL.path) {
                try fileManager.removeItem(at: launchAgentURL)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
