import AppKit
import BryanToolsShared
import Foundation
import UniformTypeIdentifiers

public final class ClipStore {
    public static let defaultRetentionDays = 90
    public static let defaultMaxRepresentationBytes = 25 * 1024 * 1024
    public static let defaultMaxEventBytes = 100 * 1024 * 1024

    public let rootDirectory: URL
    public let databaseURL: URL
    public let blobDirectory: URL

    private let db: SQLiteDatabase
    private let maxRepresentationBytes: Int
    private let maxEventBytes: Int
    private let retentionDays: Int
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public convenience init() throws {
        try self.init(rootDirectory: Self.defaultRootDirectory())
    }

    public init(
        rootDirectory: URL,
        maxRepresentationBytes: Int = ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: Int = ClipStore.defaultMaxEventBytes,
        retentionDays: Int = ClipStore.defaultRetentionDays
    ) throws {
        self.rootDirectory = rootDirectory
        self.databaseURL = rootDirectory.appendingPathComponent("ClipMan.sqlite")
        self.blobDirectory = rootDirectory.appendingPathComponent("Blobs", isDirectory: true)
        self.maxRepresentationBytes = maxRepresentationBytes
        self.maxEventBytes = maxEventBytes
        self.retentionDays = retentionDays

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)

        self.db = try SQLiteDatabase(url: databaseURL)
        try migrate()
        try purgeExpired()
    }

    public static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        try AppSupportDirectories.toolRoot(.clipboardHistory, fileManager: fileManager)
    }

    public func captureCurrentPasteboard(
        _ pasteboard: NSPasteboard = .general,
        sourceApplication: NSRunningApplication? = nil
    ) throws -> ClipRecord? {
        guard let captured = PasteboardArchiver.capture(
            from: pasteboard,
            sourceApplication: sourceApplication,
            maxRepresentationBytes: maxRepresentationBytes,
            maxEventBytes: maxEventBytes
        ) else {
            return nil
        }
        return try insert(captured)
    }

    @discardableResult
    public func insert(_ captured: CapturedClip, createdAt: Date = Date()) throws -> ClipRecord? {
        if let existingRecord = try record(contentHash: captured.contentHash) {
            try touchClip(id: existingRecord.id, at: createdAt)
            try purgeExpired()
            return try record(id: existingRecord.id)
        }

        let id = UUID()
        let clipDirectory = blobDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: clipDirectory, withIntermediateDirectories: true)

        var storedRepresentations: [ClipRepresentation] = []
        for (index, representation) in captured.representations.enumerated() {
            let fileName = representationFileName(index: index, typeIdentifier: representation.typeIdentifier)
            let relativePath = "Blobs/\(id.uuidString)/\(fileName)"
            let url = urlForRelativePath(relativePath)
            try representation.data.write(to: url, options: .atomic)
            storedRepresentations.append(
                ClipRepresentation(
                    itemIndex: representation.itemIndex,
                    typeIdentifier: representation.typeIdentifier,
                    storagePath: relativePath,
                    byteCount: representation.byteCount
                )
            )
        }

        let thumbnailPath: String?
        if let thumbnailPNGData = captured.thumbnailPNGData {
            let relativePath = "Blobs/\(id.uuidString)/thumbnail.png"
            try thumbnailPNGData.write(to: urlForRelativePath(relativePath), options: .atomic)
            thumbnailPath = relativePath
        } else {
            thumbnailPath = nil
        }

        let typeIdentifiersJSON = try encodeTypeIdentifiers(captured.typeIdentifiers)
        let record = ClipRecord(
            id: id,
            createdAt: createdAt,
            itemCount: captured.itemCount,
            contentHash: captured.contentHash,
            primaryKind: captured.primaryKind,
            summary: captured.summary,
            searchableText: captured.searchableText,
            typeIdentifiers: captured.typeIdentifiers,
            byteCount: captured.byteCount,
            thumbnailPath: thumbnailPath
        )

        do {
            try db.exec("BEGIN IMMEDIATE TRANSACTION;")
            try insertRecord(record, typeIdentifiersJSON: typeIdentifiersJSON)
            for representation in storedRepresentations {
                try insertRepresentation(representation, clipID: id)
            }
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
            try? FileManager.default.removeItem(at: clipDirectory)
            throw error
        }

        try purgeExpired()
        return record
    }

    public func search(_ query: String = "", limit: Int = 100) throws -> [ClipRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try records(
                sql: """
                SELECT id, created_at, item_count, content_hash, primary_kind, summary,
                       searchable_text, type_identifiers, byte_count, thumbnail_path
                FROM clips
                ORDER BY created_at DESC
                LIMIT ?;
                """,
                bindings: { statement in
                    try statement.bind(limit, at: 1)
                }
            )
        }

        let ftsQuery = Self.ftsQuery(from: trimmed)
        if !ftsQuery.isEmpty {
            do {
                return try records(
                    sql: """
                    SELECT c.id, c.created_at, c.item_count, c.content_hash, c.primary_kind, c.summary,
                           c.searchable_text, c.type_identifiers, c.byte_count, c.thumbnail_path
                    FROM clip_search s
                    JOIN clips c ON c.id = s.clip_id
                    WHERE clip_search MATCH ?
                    ORDER BY c.created_at DESC
                    LIMIT ?;
                    """,
                    bindings: { statement in
                        try statement.bind(ftsQuery, at: 1)
                        try statement.bind(limit, at: 2)
                    }
                )
            } catch {
                return try likeSearch(trimmed, limit: limit)
            }
        }

        return try likeSearch(trimmed, limit: limit)
    }

    public func record(id: UUID) throws -> ClipRecord? {
        try records(
            sql: """
            SELECT id, created_at, item_count, content_hash, primary_kind, summary,
                   searchable_text, type_identifiers, byte_count, thumbnail_path
            FROM clips
            WHERE id = ?
            LIMIT 1;
            """,
            bindings: { statement in
                try statement.bind(id, at: 1)
            }
        ).first
    }

    public func deleteClip(id: UUID) throws {
        let statement = try db.prepare("DELETE FROM clips WHERE id = ?;")
        try statement.bind(id, at: 1)
        try statement.run()
        try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    public func clearHistory() throws {
        try db.exec("DELETE FROM clips;")
        try? FileManager.default.removeItem(at: blobDirectory)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
    }

    public func purgeExpired() throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
        try purge(olderThan: cutoff)
    }

    public func purge(olderThan cutoff: Date) throws {
        let ids = try idsOlderThan(cutoff)
        guard !ids.isEmpty else {
            return
        }

        try db.exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let statement = try db.prepare("DELETE FROM clips WHERE created_at < ?;")
            try statement.bind(cutoff.timeIntervalSince1970, at: 1)
            try statement.run()
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
            throw error
        }

        for id in ids {
            try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
        }
    }

    public func restoreClip(id: UUID, to pasteboard: NSPasteboard = .general) throws {
        let representations = try representations(for: id)
        guard !representations.isEmpty else {
            if let record = try record(id: id), !record.searchableText.isEmpty {
                pasteboard.clearContents()
                pasteboard.setString(record.searchableText, forType: .string)
                return
            }
            throw ClipboardHistoryError.notFound(id)
        }

        var items: [NSPasteboardItem] = []
        let grouped = Dictionary(grouping: representations, by: \.itemIndex)
        for itemIndex in grouped.keys.sorted() {
            let item = NSPasteboardItem()
            for representation in grouped[itemIndex, default: []] {
                let url = urlForRelativePath(representation.storagePath)
                guard let data = try? Data(contentsOf: url) else {
                    continue
                }
                item.setData(data, forType: NSPasteboard.PasteboardType(representation.typeIdentifier))
            }
            if !item.types.isEmpty {
                items.append(item)
            }
        }

        guard !items.isEmpty else {
            throw ClipboardHistoryError.pasteboard("No stored pasteboard representations could be restored.")
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            throw ClipboardHistoryError.pasteboard("Unable to write archived items to the pasteboard.")
        }
    }

    public func representationCount(for clipID: UUID) throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM representations WHERE clip_id = ?;")
        try statement.bind(clipID, at: 1)
        guard try statement.step() else {
            return 0
        }
        return statement.columnInt(0)
    }

    public func urlForRelativePath(_ relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    public func ensureHighResolutionThumbnail(for record: ClipRecord) throws -> URL? {
        let minimumUsefulDimension = PasteboardArchiver.storedThumbnailMaxDimension * 0.75
        if let thumbnailPath = record.thumbnailPath {
            let existingURL = urlForRelativePath(thumbnailPath)
            if Self.maxImagePixelDimension(at: existingURL) >= minimumUsefulDimension {
                return existingURL
            }
        }

        guard let image = try firstImageRepresentation(for: record.id),
              let thumbnailData = PasteboardArchiver.makeThumbnailPNG(from: image) else {
            return record.thumbnailPath.map(urlForRelativePath)
        }

        let relativePath = record.thumbnailPath ?? "Blobs/\(record.id.uuidString)/thumbnail.png"
        let thumbnailURL = urlForRelativePath(relativePath)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try thumbnailData.write(to: thumbnailURL, options: .atomic)

        if record.thumbnailPath == nil {
            try updateThumbnailPath(id: record.id, relativePath: relativePath)
        }

        return thumbnailURL
    }

    private func migrate() throws {
        try db.exec(
            """
            PRAGMA foreign_keys = ON;
            PRAGMA journal_mode = WAL;

            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                item_count INTEGER NOT NULL,
                content_hash TEXT NOT NULL,
                primary_kind TEXT NOT NULL,
                summary TEXT NOT NULL,
                searchable_text TEXT NOT NULL,
                type_identifiers TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                thumbnail_path TEXT
            );

            CREATE INDEX IF NOT EXISTS clips_created_at_idx ON clips(created_at DESC);
            CREATE INDEX IF NOT EXISTS clips_content_hash_idx ON clips(content_hash);

            CREATE TABLE IF NOT EXISTS representations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
                item_index INTEGER NOT NULL,
                type_identifier TEXT NOT NULL,
                storage_path TEXT NOT NULL,
                byte_count INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS representations_clip_id_idx ON representations(clip_id);

            CREATE VIRTUAL TABLE IF NOT EXISTS clip_search USING fts5(
                clip_id UNINDEXED,
                body,
                tokenize = 'unicode61'
            );

            CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
                INSERT INTO clip_search(clip_id, body)
                VALUES (
                    new.id,
                    new.summary || ' ' || new.searchable_text || ' ' || new.type_identifiers
                );
            END;

            CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
                DELETE FROM clip_search WHERE clip_id = old.id;
            END;
            """
        )
    }

    private func insertRecord(_ record: ClipRecord, typeIdentifiersJSON: String) throws {
        let statement = try db.prepare(
            """
            INSERT INTO clips (
                id, created_at, item_count, content_hash, primary_kind, summary,
                searchable_text, type_identifiers, byte_count, thumbnail_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        try statement.bind(record.id, at: 1)
        try statement.bind(record.createdAt.timeIntervalSince1970, at: 2)
        try statement.bind(record.itemCount, at: 3)
        try statement.bind(record.contentHash, at: 4)
        try statement.bind(record.primaryKind.rawValue, at: 5)
        try statement.bind(record.summary, at: 6)
        try statement.bind(record.searchableText, at: 7)
        try statement.bind(typeIdentifiersJSON, at: 8)
        try statement.bind(record.byteCount, at: 9)
        try statement.bind(record.thumbnailPath, at: 10)
        try statement.run()
    }

    private func insertRepresentation(_ representation: ClipRepresentation, clipID: UUID) throws {
        let statement = try db.prepare(
            """
            INSERT INTO representations (clip_id, item_index, type_identifier, storage_path, byte_count)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        try statement.bind(clipID, at: 1)
        try statement.bind(representation.itemIndex, at: 2)
        try statement.bind(representation.typeIdentifier, at: 3)
        try statement.bind(representation.storagePath, at: 4)
        try statement.bind(representation.byteCount, at: 5)
        try statement.run()
    }

    private func touchClip(id: UUID, at date: Date) throws {
        let statement = try db.prepare("UPDATE clips SET created_at = ? WHERE id = ?;")
        try statement.bind(date.timeIntervalSince1970, at: 1)
        try statement.bind(id, at: 2)
        try statement.run()
    }

    private func updateThumbnailPath(id: UUID, relativePath: String) throws {
        let statement = try db.prepare("UPDATE clips SET thumbnail_path = ? WHERE id = ?;")
        try statement.bind(relativePath, at: 1)
        try statement.bind(id, at: 2)
        try statement.run()
    }

    private func records(sql: String, bindings: (SQLiteStatement) throws -> Void) throws -> [ClipRecord] {
        let statement = try db.prepare(sql)
        try bindings(statement)

        var records: [ClipRecord] = []
        while try statement.step() {
            records.append(try record(from: statement))
        }
        return records
    }

    private func record(from statement: SQLiteStatement) throws -> ClipRecord {
        guard let idString = statement.columnString(0),
              let id = UUID(uuidString: idString),
              let contentHash = statement.columnString(3),
              let kindString = statement.columnString(4),
              let primaryKind = ClipPrimaryKind(rawValue: kindString),
              let summary = statement.columnString(5),
              let searchableText = statement.columnString(6),
              let typeIdentifiersJSON = statement.columnString(7) else {
            throw ClipboardHistoryError.database("Unable to decode clip row.")
        }

        return ClipRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: statement.columnDouble(1)),
            itemCount: statement.columnInt(2),
            contentHash: contentHash,
            primaryKind: primaryKind,
            summary: summary,
            searchableText: searchableText,
            typeIdentifiers: try decodeTypeIdentifiers(typeIdentifiersJSON),
            byteCount: statement.columnInt64(8),
            thumbnailPath: statement.columnString(9)
        )
    }

    private func representations(for clipID: UUID) throws -> [ClipRepresentation] {
        let statement = try db.prepare(
            """
            SELECT item_index, type_identifier, storage_path, byte_count
            FROM representations
            WHERE clip_id = ?
            ORDER BY item_index ASC, id ASC;
            """
        )
        try statement.bind(clipID, at: 1)

        var representations: [ClipRepresentation] = []
        while try statement.step() {
            guard let typeIdentifier = statement.columnString(1),
                  let storagePath = statement.columnString(2) else {
                continue
            }
            representations.append(
                ClipRepresentation(
                    itemIndex: statement.columnInt(0),
                    typeIdentifier: typeIdentifier,
                    storagePath: storagePath,
                    byteCount: statement.columnInt64(3)
                )
            )
        }
        return representations
    }

    private func firstImageRepresentation(for clipID: UUID) throws -> NSImage? {
        for representation in try representations(for: clipID) {
            guard isImageTypeIdentifier(representation.typeIdentifier) else {
                continue
            }
            let url = urlForRelativePath(representation.storagePath)
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data),
                  image.isValid else {
                continue
            }
            return image
        }
        return nil
    }

    private func isImageTypeIdentifier(_ typeIdentifier: String) -> Bool {
        if let type = UTType(typeIdentifier), type.conforms(to: .image) {
            return true
        }
        let normalized = typeIdentifier.lowercased()
        return normalized.contains("image")
            || normalized == "public.png"
            || normalized == "public.jpeg"
            || normalized == "public.tiff"
    }

    private static func maxImagePixelDimension(at url: URL) -> CGFloat {
        guard let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data) else {
            return 0
        }
        return CGFloat(max(bitmap.pixelsWide, bitmap.pixelsHigh))
    }

    private func likeSearch(_ query: String, limit: Int) throws -> [ClipRecord] {
        let pattern = "%\(query)%"
        return try records(
            sql: """
            SELECT id, created_at, item_count, content_hash, primary_kind, summary,
                   searchable_text, type_identifiers, byte_count, thumbnail_path
            FROM clips
            WHERE searchable_text LIKE ? OR summary LIKE ? OR type_identifiers LIKE ?
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            bindings: { statement in
                try statement.bind(pattern, at: 1)
                try statement.bind(pattern, at: 2)
                try statement.bind(pattern, at: 3)
                try statement.bind(limit, at: 4)
            }
        )
    }

    private func record(contentHash: String) throws -> ClipRecord? {
        try records(
            sql: """
            SELECT id, created_at, item_count, content_hash, primary_kind, summary,
                   searchable_text, type_identifiers, byte_count, thumbnail_path
            FROM clips
            WHERE content_hash = ?
            ORDER BY created_at DESC
            LIMIT 1;
            """,
            bindings: { statement in
                try statement.bind(contentHash, at: 1)
            }
        ).first
    }

    private func idsOlderThan(_ cutoff: Date) throws -> [UUID] {
        let statement = try db.prepare("SELECT id FROM clips WHERE created_at < ?;")
        try statement.bind(cutoff.timeIntervalSince1970, at: 1)

        var ids: [UUID] = []
        while try statement.step() {
            if let idString = statement.columnString(0),
               let id = UUID(uuidString: idString) {
                ids.append(id)
            }
        }
        return ids
    }

    private func representationFileName(index: Int, typeIdentifier: String) -> String {
        let safeType = typeIdentifier.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let safeBase = String(safeType).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if let ext = preferredExtension(for: typeIdentifier), !ext.isEmpty {
            return "\(index)-\(safeBase).\(ext)"
        }
        return "\(index)-\(safeBase).bin"
    }

    private func preferredExtension(for typeIdentifier: String) -> String? {
        if let ext = UTType(typeIdentifier)?.preferredFilenameExtension {
            return ext
        }
        switch typeIdentifier {
        case NSPasteboard.PasteboardType.string.rawValue:
            return "txt"
        default:
            return nil
        }
    }

    private func encodeTypeIdentifiers(_ typeIdentifiers: [String]) throws -> String {
        let data = try jsonEncoder.encode(typeIdentifiers)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeTypeIdentifiers(_ string: String) throws -> [String] {
        guard let data = string.data(using: .utf8) else {
            return []
        }
        return try jsonDecoder.decode([String].self, from: data)
    }

    private static func ftsQuery(from query: String) -> String {
        let terms = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return terms.map { "\($0)*" }.joined(separator: " AND ")
    }
}
