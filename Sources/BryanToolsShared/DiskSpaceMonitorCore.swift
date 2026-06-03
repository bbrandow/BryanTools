import Foundation
import SQLite3

private let diskSpaceSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct DiskSpaceMonitorPreferences: Equatable {
    public static let defaultEnabled = true
    public static let defaultWarningThresholdGB = 50
    public static let minimumWarningThresholdGB = 1
    public static let maximumWarningThresholdGB = 9_999
    public static let minimumVisibleHistoryHours = 1
    public static let maximumVisibleHistoryHours = retentionDays * 24
    public static let pollInterval: TimeInterval = 5 * 60
    public static let retentionDays = 30

    public var isEnabled: Bool
    public var warningThresholdGB: Int
    public var visibleHistoryHours: Int?

    public init(isEnabled: Bool, warningThresholdGB: Int, visibleHistoryHours: Int? = nil) {
        self.isEnabled = isEnabled
        self.warningThresholdGB = Self.clampedWarningThresholdGB(warningThresholdGB)
        self.visibleHistoryHours = Self.clampedVisibleHistoryHours(visibleHistoryHours)
    }

    public static func load(defaults: UserDefaults = .standard) -> DiskSpaceMonitorPreferences {
        let enabled: Bool
        if defaults.object(forKey: "diskSpaceMonitor.isEnabled") == nil {
            enabled = defaultEnabled
        } else {
            enabled = defaults.bool(forKey: "diskSpaceMonitor.isEnabled")
        }

        let threshold = defaults.object(forKey: "diskSpaceMonitor.warningThresholdGB") as? Int
            ?? defaultWarningThresholdGB
        let visibleHistoryHours = defaults.object(forKey: "diskSpaceMonitor.visibleHistoryHours") as? Int

        return DiskSpaceMonitorPreferences(
            isEnabled: enabled,
            warningThresholdGB: threshold,
            visibleHistoryHours: visibleHistoryHours
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: "diskSpaceMonitor.isEnabled")
        defaults.set(warningThresholdGB, forKey: "diskSpaceMonitor.warningThresholdGB")
        if let visibleHistoryHours {
            defaults.set(visibleHistoryHours, forKey: "diskSpaceMonitor.visibleHistoryHours")
        } else {
            defaults.removeObject(forKey: "diskSpaceMonitor.visibleHistoryHours")
        }
    }

    public static func clampedWarningThresholdGB(_ value: Int) -> Int {
        min(max(value, minimumWarningThresholdGB), maximumWarningThresholdGB)
    }

    public static func clampedVisibleHistoryHours(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return min(max(value, minimumVisibleHistoryHours), maximumVisibleHistoryHours)
    }

    public static func selectedHistoryHours(startTime: TimeInterval, endTime: TimeInterval) -> Int? {
        guard endTime > startTime else {
            return nil
        }
        return clampedVisibleHistoryHours(Int(ceil((endTime - startTime) / 3_600)))
    }
}

public struct DiskSpaceSample: Equatable, Identifiable {
    public let sampledAt: Date
    public let availableBytes: Int64
    public let totalBytes: Int64

    public var id: Date {
        sampledAt
    }

    public init(sampledAt: Date, availableBytes: Int64, totalBytes: Int64) {
        self.sampledAt = sampledAt
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    public var freeGB: Int64 {
        DiskSpaceMonitorDisplay.wholeDecimalGB(from: availableBytes)
    }
}

public enum DiskSpaceMonitorDisplay {
    public static let bytesPerDecimalGB: Int64 = 1_000_000_000

    public static func wholeDecimalGB(from bytes: Int64) -> Int64 {
        max(0, bytes) / bytesPerDecimalGB
    }

    public static func trayTitle(availableBytes: Int64) -> String {
        "\(wholeDecimalGB(from: availableBytes))GB"
    }

    public static func warningThresholdBytes(thresholdGB: Int) -> Int64 {
        Int64(DiskSpaceMonitorPreferences.clampedWarningThresholdGB(thresholdGB)) * bytesPerDecimalGB
    }

    public static func isBelowWarningThreshold(availableBytes: Int64, thresholdGB: Int) -> Bool {
        availableBytes < warningThresholdBytes(thresholdGB: thresholdGB)
    }

    public static func samples(_ samples: [DiskSpaceSample], visibleHistoryHours: Int?) -> [DiskSpaceSample] {
        let sortedSamples = samples.sorted { $0.sampledAt < $1.sampledAt }
        guard let visibleHistoryHours = DiskSpaceMonitorPreferences.clampedVisibleHistoryHours(visibleHistoryHours),
              let latestDate = sortedSamples.last?.sampledAt else {
            return sortedSamples
        }

        let cutoffDate = latestDate.addingTimeInterval(-Double(visibleHistoryHours) * 3_600)
        return sortedSamples.filter { $0.sampledAt >= cutoffDate }
    }
}

public enum DiskSpaceMonitorError: Error, LocalizedError {
    case unavailableCapacity
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .unavailableCapacity:
            return "Unable to read primary disk free space."
        case .database(let message):
            return "Disk Space Monitor database error: \(message)"
        }
    }
}

public enum DiskSpaceMeasurer {
    public static func measurePrimaryVolume(path: String = "/", now: Date = Date()) throws -> DiskSpaceSample {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])

        guard let availableBytes = values.volumeAvailableCapacityForImportantUsage,
              let totalBytes = values.volumeTotalCapacity else {
            throw DiskSpaceMonitorError.unavailableCapacity
        }

        return DiskSpaceSample(
            sampledAt: now,
            availableBytes: Int64(availableBytes),
            totalBytes: Int64(totalBytes)
        )
    }
}

public final class DiskSpaceSampleStore {
    public static let databaseName = "DiskSpace.sqlite"

    public let rootDirectory: URL
    public let databaseURL: URL

    private let db: DiskSpaceSQLiteDatabase

    public convenience init() throws {
        try self.init(rootDirectory: AppSupportDirectories.toolRoot(.diskSpaceMonitor))
    }

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.databaseURL = rootDirectory.appendingPathComponent(Self.databaseName)

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        self.db = try DiskSpaceSQLiteDatabase(url: databaseURL)
        try migrate()
    }

    public func insert(_ sample: DiskSpaceSample) throws {
        let statement = try db.prepare(
            """
            INSERT OR REPLACE INTO disk_space_samples
                (sampled_at, available_bytes, total_bytes)
            VALUES (?, ?, ?);
            """
        )
        try statement.bind(sample.sampledAt.timeIntervalSince1970, at: 1)
        try statement.bind(sample.availableBytes, at: 2)
        try statement.bind(sample.totalBytes, at: 3)
        try statement.run()
    }

    public func latestSample() throws -> DiskSpaceSample? {
        let statement = try db.prepare(
            """
            SELECT sampled_at, available_bytes, total_bytes
            FROM disk_space_samples
            ORDER BY sampled_at DESC
            LIMIT 1;
            """
        )
        guard try statement.step() else {
            return nil
        }
        return sample(from: statement)
    }

    public func samples(since startDate: Date, limit: Int? = nil) throws -> [DiskSpaceSample] {
        let statement: DiskSpaceSQLiteStatement
        if let limit {
            guard limit > 0 else {
                return []
            }
            statement = try db.prepare(
                """
                SELECT sampled_at, available_bytes, total_bytes
                FROM (
                    SELECT sampled_at, available_bytes, total_bytes
                    FROM disk_space_samples
                    WHERE sampled_at >= ?
                    ORDER BY sampled_at DESC
                    LIMIT ?
                )
                ORDER BY sampled_at ASC;
                """
            )
            try statement.bind(startDate.timeIntervalSince1970, at: 1)
            try statement.bind(limit, at: 2)
        } else {
            statement = try db.prepare(
                """
                SELECT sampled_at, available_bytes, total_bytes
                FROM disk_space_samples
                WHERE sampled_at >= ?
                ORDER BY sampled_at ASC;
                """
            )
            try statement.bind(startDate.timeIntervalSince1970, at: 1)
        }

        var samples: [DiskSpaceSample] = []
        while try statement.step() {
            samples.append(sample(from: statement))
        }
        return samples
    }

    public func purgeOlderThan(retentionDays: Int = DiskSpaceMonitorPreferences.retentionDays, now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let statement = try db.prepare("DELETE FROM disk_space_samples WHERE sampled_at < ?;")
        try statement.bind(cutoff.timeIntervalSince1970, at: 1)
        try statement.run()
    }

    private func migrate() throws {
        try db.exec(
            """
            CREATE TABLE IF NOT EXISTS disk_space_samples (
                sampled_at REAL PRIMARY KEY NOT NULL,
                available_bytes INTEGER NOT NULL,
                total_bytes INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_disk_space_samples_sampled_at
                ON disk_space_samples(sampled_at);
            """
        )
    }

    private func sample(from statement: DiskSpaceSQLiteStatement) -> DiskSpaceSample {
        DiskSpaceSample(
            sampledAt: Date(timeIntervalSince1970: statement.columnDouble(0)),
            availableBytes: statement.columnInt64(1),
            totalBytes: statement.columnInt64(2)
        )
    }
}

private final class DiskSpaceSQLiteDatabase {
    fileprivate var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle {
                sqlite3_close(handle)
            }
            throw DiskSpaceMonitorError.database(message)
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw DiskSpaceMonitorError.database(message)
        }
    }

    func prepare(_ sql: String) throws -> DiskSpaceSQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw DiskSpaceMonitorError.database(lastErrorMessage)
        }
        return DiskSpaceSQLiteStatement(database: self, statement: statement)
    }

    fileprivate var lastErrorMessage: String {
        guard let handle else {
            return "Database handle is closed"
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}

private final class DiskSpaceSQLiteStatement {
    private unowned let database: DiskSpaceSQLiteDatabase
    private var statement: OpaquePointer?

    fileprivate init(database: DiskSpaceSQLiteDatabase, statement: OpaquePointer) {
        self.database = database
        self.statement = statement
    }

    deinit {
        if let statement {
            sqlite3_finalize(statement)
        }
    }

    func bind(_ value: Int, at index: Int32) throws {
        try bind(Int64(value), at: index)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(statement, index, value))
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            return false
        }
        throw DiskSpaceMonitorError.database(database.lastErrorMessage)
    }

    func run() throws {
        _ = try step()
    }

    func columnInt64(_ index: Int32) -> Int64 {
        Int64(sqlite3_column_int64(statement, index))
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw DiskSpaceMonitorError.database(database.lastErrorMessage)
        }
    }
}
