import Foundation

public enum AppSupportDirectories {
    public static let applicationDirectoryName = "Bryan Tools"

    public static func appRoot(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent(applicationDirectoryName, isDirectory: true)
    }

    public static func toolRoot(_ tool: ToolIdentifier, fileManager: FileManager = .default) throws -> URL {
        try appRoot(fileManager: fileManager)
            .appendingPathComponent(tool.storageDirectoryName, isDirectory: true)
    }

    public static func legacyClipManRoot(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appendingPathComponent("ClipMan", isDirectory: true)
    }
}
