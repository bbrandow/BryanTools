import BryanToolsShared
import Foundation

public enum ClipboardHistoryMigration {
    public enum Outcome: Equatable {
        case alreadyCompleted
        case legacyMissing
        case destinationAlreadyExists
        case copied
    }

    public static let migrationCompleteKey = "clipboardHistory.clipManDataMigrationComplete"

    public static func migrateClipManDataIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        legacyRoot: URL? = nil,
        destinationRoot: URL? = nil
    ) throws -> Outcome {
        if defaults.bool(forKey: migrationCompleteKey) {
            return .alreadyCompleted
        }

        let source = try legacyRoot ?? AppSupportDirectories.legacyClipManRoot(fileManager: fileManager)
        let destination = try destinationRoot ?? ClipStore.defaultRootDirectory(fileManager: fileManager)

        guard fileManager.fileExists(atPath: source.path) else {
            defaults.set(true, forKey: migrationCompleteKey)
            return .legacyMissing
        }

        guard !fileManager.fileExists(atPath: destination.path) else {
            defaults.set(true, forKey: migrationCompleteKey)
            return .destinationAlreadyExists
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: source, to: destination)
        defaults.set(true, forKey: migrationCompleteKey)
        return .copied
    }
}
