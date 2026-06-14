import Foundation

public enum BryanToolsAutoStart {
    public static let defaultsKey = "bryanTools.autoStart.enabled"
    public static let launchAgentLabel = "com.local.BryanTools.autostart"
    public static let launchAgentFileName = "\(launchAgentLabel).plist"
    public static let installedAppPath = "/Applications/Bryan Tools.app"

    public static func isEnabledByDefault(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: defaultsKey) == nil {
            return true
        }
        return defaults.bool(forKey: defaultsKey)
    }

    public static func launchAgentURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent(launchAgentFileName)
    }

    public static func launchAgentPlist(appPath: String = installedAppPath) -> [String: Any] {
        [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                appPath
            ],
            "RunAtLoad": true
        ]
    }

    public static func launchAgentPlistData(appPath: String = installedAppPath) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: launchAgentPlist(appPath: appPath),
            format: .xml,
            options: 0
        )
    }
}
