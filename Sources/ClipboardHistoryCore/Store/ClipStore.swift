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
    private let cipher: ClipStoreCipher
    private static let recordColumns = """
        id, created_at, COALESCE(last_copied_at, created_at), item_count, content_hash,
        canonical_text_hash, primary_kind, summary, searchable_text, type_identifiers,
        byte_count, thumbnail_path
        """

    private struct RawClipRow {
        let id: UUID
        let summary: String
        let searchableText: String
        let typeIdentifiers: String
    }

    public convenience init() throws {
        try self.init(rootDirectory: Self.defaultRootDirectory())
    }

    public init(
        rootDirectory: URL,
        maxRepresentationBytes: Int = ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: Int = ClipStore.defaultMaxEventBytes,
        retentionDays: Int = ClipStore.defaultRetentionDays,
        encryptionKeyData: Data? = nil
    ) throws {
        self.rootDirectory = rootDirectory
        self.databaseURL = rootDirectory.appendingPathComponent("ClipMan.sqlite")
        self.blobDirectory = rootDirectory.appendingPathComponent("Blobs", isDirectory: true)
        self.maxRepresentationBytes = maxRepresentationBytes
        self.maxEventBytes = maxEventBytes
        self.retentionDays = retentionDays
        self.cipher = try ClipStoreCipher(keyData: encryptionKeyData ?? ClipStoreKeychain.loadOrCreateKey())

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)

        self.db = try SQLiteDatabase(url: databaseURL)
        try migrate()
        try encryptExistingStoredContent()
        try purgeExpired()
        try removeOrphanedBlobDirectories()
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
        if let canonicalTextHash = captured.canonicalTextHash {
            let duplicates = try semanticDuplicateRecords(
                canonicalTextHash: canonicalTextHash,
                summary: captured.summary
            )
            if let existingRecord = preferredSemanticDuplicate(from: duplicates) {
                try touchClip(id: existingRecord.id, at: createdAt)
                try purgeExpired()
                return try record(id: existingRecord.id)
            }
        }

        if let existingRecord = try record(contentHash: captured.contentHash) {
            if let canonicalTextHash = captured.canonicalTextHash {
                try updateCanonicalTextHash(id: existingRecord.id, canonicalTextHash: canonicalTextHash)
            }
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
            try cipher.encryptData(representation.data).write(to: url, options: .atomic)
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
            try cipher.encryptData(thumbnailPNGData).write(to: urlForRelativePath(relativePath), options: .atomic)
            thumbnailPath = relativePath
        } else {
            thumbnailPath = nil
        }

        let typeIdentifiersJSON = try encodeTypeIdentifiers(captured.typeIdentifiers)
        let record = ClipRecord(
            id: id,
            createdAt: createdAt,
            lastCopiedAt: createdAt,
            itemCount: captured.itemCount,
            contentHash: captured.contentHash,
            canonicalTextHash: captured.canonicalTextHash,
            primaryKind: captured.primaryKind,
            summary: captured.summary,
            searchableText: captured.searchableText,
            typeIdentifiers: captured.typeIdentifiers,
            byteCount: captured.byteCount,
            thumbnailPath: thumbnailPath
        )

        do {
            try db.exec("BEGIN IMMEDIATE TRANSACTION;")
            try insertRecord(
                record,
                canonicalTextHash: captured.canonicalTextHash,
                typeIdentifiersJSON: typeIdentifiersJSON
            )
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

    public func search(
        _ query: String = "",
        limit: Int = 100,
        shouldCancel: () -> Bool = { false }
    ) throws -> [ClipRecord] {
        if shouldCancel() {
            throw CancellationError()
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = Self.searchTerms(from: trimmed)
        guard trimmed.isEmpty || !terms.isEmpty else {
            return []
        }

        let statement = try db.prepare(
            """
            SELECT \(Self.recordColumns)
            FROM clips
            ORDER BY last_copied_at DESC;
            """
        )
        var matches: [ClipRecord] = []
        var seenDuplicateKeys = Set<String>()

        while try statement.step() {
            if shouldCancel() {
                throw CancellationError()
            }

            let record = try record(from: statement)
            let duplicateKey = record.canonicalTextHash.map { "text:\($0)" }
                ?? "content:\(record.contentHash)"
            guard trimmed.isEmpty || Self.record(record, matchesTerms: terms) else {
                continue
            }
            guard seenDuplicateKeys.insert(duplicateKey).inserted else {
                continue
            }
            matches.append(record)
            if matches.count == limit {
                break
            }
        }
        return matches
    }

    public func record(id: UUID) throws -> ClipRecord? {
        try records(
            sql: """
            SELECT \(Self.recordColumns)
            FROM clips
            WHERE id = ?
            LIMIT 1;
            """,
            bindings: { statement in
                try statement.bind(id, at: 1)
            }
        ).first
    }

    @discardableResult
    public func markCopied(id: UUID, at date: Date = Date()) throws -> ClipRecord {
        guard let existingRecord = try record(id: id) else {
            throw ClipboardHistoryError.notFound(id)
        }

        if let canonicalTextHash = try canonicalTextHash(for: existingRecord) {
            try updateCanonicalTextHash(id: id, canonicalTextHash: canonicalTextHash)
            _ = try semanticDuplicateRecords(
                canonicalTextHash: canonicalTextHash,
                summary: existingRecord.summary
            )
        }

        try touchClip(id: id, at: date)
        guard let updatedRecord = try record(id: id) else {
            throw ClipboardHistoryError.notFound(id)
        }
        return updatedRecord
    }

    public func deleteClip(id: UUID) throws {
        let statement = try db.prepare("DELETE FROM clips WHERE id = ?;")
        try statement.bind(id, at: 1)
        try statement.run()
        try removeBlobDirectoryIfPresent(id: id)
        try removeOrphanedBlobDirectories()
    }

    public func clearHistory() throws {
        try db.exec("DELETE FROM clips;")
        if FileManager.default.fileExists(atPath: blobDirectory.path) {
            try FileManager.default.removeItem(at: blobDirectory)
        }
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
    }

    public func purgeExpired() throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
        try purge(olderThan: cutoff)
    }

    public func purge(olderThan cutoff: Date) throws {
        let ids = try idsOlderThan(cutoff)
        guard !ids.isEmpty else {
            try removeOrphanedBlobDirectories()
            return
        }

        try db.exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let statement = try db.prepare("DELETE FROM clips WHERE last_copied_at < ?;")
            try statement.bind(cutoff.timeIntervalSince1970, at: 1)
            try statement.run()
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
            throw error
        }

        for id in ids {
            try removeBlobDirectoryIfPresent(id: id)
        }
        try removeOrphanedBlobDirectories()
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
                guard let data = try? dataForStoredFile(at: url) else {
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
            if try maxImagePixelDimension(at: existingURL) >= minimumUsefulDimension {
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
        try cipher.encryptData(thumbnailData).write(to: thumbnailURL, options: .atomic)

        if record.thumbnailPath == nil {
            try updateThumbnailPath(id: record.id, relativePath: relativePath)
        }

        return thumbnailURL
    }

    public func image(for record: ClipRecord) throws -> NSImage? {
        if let image = try firstImageRepresentation(for: record.id) {
            return image
        }
        guard let thumbnailPath = record.thumbnailPath else {
            return nil
        }
        return try imageForStoredFile(at: urlForRelativePath(thumbnailPath))
    }

    public func thumbnailImage(for record: ClipRecord) throws -> NSImage? {
        guard let thumbnailURL = try ensureHighResolutionThumbnail(for: record) else {
            return nil
        }
        return try imageForStoredFile(at: thumbnailURL)
    }

    public func removeOrphanedBlobDirectories() throws {
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        let knownIDs = try allClipIDs()
        let contents = try FileManager.default.contentsOfDirectory(
            at: blobDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for url in contents {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  let id = UUID(uuidString: url.lastPathComponent),
                  !knownIDs.contains(id) else {
                continue
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func migrate() throws {
        try db.exec(
            """
            PRAGMA foreign_keys = ON;
            PRAGMA journal_mode = WAL;

            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                last_copied_at REAL NOT NULL,
                item_count INTEGER NOT NULL,
                content_hash TEXT NOT NULL,
                canonical_text_hash TEXT,
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
        try ensureCanonicalTextHashColumn()
        try ensureLastCopiedAtColumn()
        try db.exec(
            """
            CREATE INDEX IF NOT EXISTS clips_canonical_text_hash_idx ON clips(canonical_text_hash);
            CREATE INDEX IF NOT EXISTS clips_last_copied_at_idx ON clips(last_copied_at DESC);
            """
        )
    }

    private func ensureCanonicalTextHashColumn() throws {
        let statement = try db.prepare("PRAGMA table_info(clips);")
        while try statement.step() {
            if statement.columnString(1) == "canonical_text_hash" {
                return
            }
        }
        try db.exec("ALTER TABLE clips ADD COLUMN canonical_text_hash TEXT;")
    }

    private func ensureLastCopiedAtColumn() throws {
        let statement = try db.prepare("PRAGMA table_info(clips);")
        var hasColumn = false
        while try statement.step() {
            if statement.columnString(1) == "last_copied_at" {
                hasColumn = true
                break
            }
        }
        if !hasColumn {
            try db.exec("ALTER TABLE clips ADD COLUMN last_copied_at REAL;")
        }
        try db.exec("UPDATE clips SET last_copied_at = created_at WHERE last_copied_at IS NULL;")
    }

    private func encryptExistingStoredContent() throws {
        let rows = try rawClipRows()
        guard !rows.isEmpty else {
            return
        }

        var didUpdateMetadata = false
        try db.exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for row in rows {
                let encryptedSummary = try encryptedTextIfNeeded(row.summary)
                let encryptedSearchableText = try encryptedTextIfNeeded(row.searchableText)
                let encryptedTypeIdentifiers = try encryptedTextIfNeeded(row.typeIdentifiers)
                guard encryptedSummary != row.summary
                    || encryptedSearchableText != row.searchableText
                    || encryptedTypeIdentifiers != row.typeIdentifiers else {
                    continue
                }

                let statement = try db.prepare(
                    """
                    UPDATE clips
                    SET summary = ?, searchable_text = ?, type_identifiers = ?
                    WHERE id = ?;
                    """
                )
                try statement.bind(encryptedSummary, at: 1)
                try statement.bind(encryptedSearchableText, at: 2)
                try statement.bind(encryptedTypeIdentifiers, at: 3)
                try statement.bind(row.id, at: 4)
                try statement.run()
                didUpdateMetadata = true
            }
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
            throw error
        }

        if didUpdateMetadata {
            try rebuildSearchIndex()
        }

        try encryptExistingBlobFiles()
    }

    private func encryptedTextIfNeeded(_ text: String) throws -> String {
        let decryptedText = try cipher.decryptTextIfNeeded(text)
        return try cipher.encryptText(decryptedText)
    }

    private func encryptExistingBlobFiles() throws {
        let paths = try storedBlobRelativePaths()
        for path in paths {
            let url = urlForRelativePath(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let data = try Data(contentsOf: url)
            guard !cipher.isEncryptedData(data) else {
                continue
            }
            try cipher.encryptData(data).write(to: url, options: .atomic)
        }
    }

    private func rebuildSearchIndex() throws {
        try db.exec(
            """
            DELETE FROM clip_search;
            INSERT INTO clip_search(clip_id, body)
            SELECT id, summary || ' ' || searchable_text || ' ' || type_identifiers
            FROM clips;
            """
        )
    }

    private func insertRecord(
        _ record: ClipRecord,
        canonicalTextHash: String?,
        typeIdentifiersJSON: String
    ) throws {
        let statement = try db.prepare(
            """
            INSERT INTO clips (
                id, created_at, last_copied_at, item_count, content_hash, canonical_text_hash,
                primary_kind, summary, searchable_text, type_identifiers, byte_count, thumbnail_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        try statement.bind(record.id, at: 1)
        try statement.bind(record.createdAt.timeIntervalSince1970, at: 2)
        try statement.bind(record.lastCopiedAt.timeIntervalSince1970, at: 3)
        try statement.bind(record.itemCount, at: 4)
        try statement.bind(record.contentHash, at: 5)
        try statement.bind(canonicalTextHash, at: 6)
        try statement.bind(record.primaryKind.rawValue, at: 7)
        try statement.bind(cipher.encryptText(record.summary), at: 8)
        try statement.bind(cipher.encryptText(record.searchableText), at: 9)
        try statement.bind(cipher.encryptText(typeIdentifiersJSON), at: 10)
        try statement.bind(record.byteCount, at: 11)
        try statement.bind(record.thumbnailPath, at: 12)
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
        let statement = try db.prepare("UPDATE clips SET last_copied_at = ? WHERE id = ?;")
        try statement.bind(date.timeIntervalSince1970, at: 1)
        try statement.bind(id, at: 2)
        try statement.run()
    }

    private func updateCanonicalTextHash(id: UUID, canonicalTextHash: String) throws {
        let statement = try db.prepare(
            "UPDATE clips SET canonical_text_hash = ? WHERE id = ?;"
        )
        try statement.bind(canonicalTextHash, at: 1)
        try statement.bind(id, at: 2)
        try statement.run()
    }

    private func updateThumbnailPath(id: UUID, relativePath: String) throws {
        let statement = try db.prepare("UPDATE clips SET thumbnail_path = ? WHERE id = ?;")
        try statement.bind(relativePath, at: 1)
        try statement.bind(id, at: 2)
        try statement.run()
    }

    private func records(
        sql: String,
        bindings: (SQLiteStatement) throws -> Void,
        shouldCancel: () -> Bool = { false }
    ) throws -> [ClipRecord] {
        let statement = try db.prepare(sql)
        try bindings(statement)

        var records: [ClipRecord] = []
        while try statement.step() {
            if shouldCancel() {
                throw CancellationError()
            }
            records.append(try record(from: statement))
        }
        return records
    }

    private func rawClipRows() throws -> [RawClipRow] {
        let statement = try db.prepare(
            """
            SELECT id, summary, searchable_text, type_identifiers
            FROM clips;
            """
        )

        var rows: [RawClipRow] = []
        while try statement.step() {
            guard let idString = statement.columnString(0),
                  let id = UUID(uuidString: idString),
                  let summary = statement.columnString(1),
                  let searchableText = statement.columnString(2),
                  let typeIdentifiers = statement.columnString(3) else {
                continue
            }
            rows.append(
                RawClipRow(
                    id: id,
                    summary: summary,
                    searchableText: searchableText,
                    typeIdentifiers: typeIdentifiers
                )
            )
        }
        return rows
    }

    private func record(from statement: SQLiteStatement) throws -> ClipRecord {
        guard let idString = statement.columnString(0),
              let id = UUID(uuidString: idString),
              let contentHash = statement.columnString(4),
              let kindString = statement.columnString(6),
              let primaryKind = ClipPrimaryKind(rawValue: kindString),
              let rawSummary = statement.columnString(7),
              let rawSearchableText = statement.columnString(8),
              let rawTypeIdentifiersJSON = statement.columnString(9) else {
            throw ClipboardHistoryError.database("Unable to decode clip row.")
        }

        let summary = try cipher.decryptTextIfNeeded(rawSummary)
        let searchableText = try cipher.decryptTextIfNeeded(rawSearchableText)
        let typeIdentifiersJSON = try cipher.decryptTextIfNeeded(rawTypeIdentifiersJSON)

        return ClipRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: statement.columnDouble(1)),
            lastCopiedAt: Date(timeIntervalSince1970: statement.columnDouble(2)),
            itemCount: statement.columnInt(3),
            contentHash: contentHash,
            canonicalTextHash: statement.columnString(5),
            primaryKind: primaryKind,
            summary: summary,
            searchableText: searchableText,
            typeIdentifiers: try decodeTypeIdentifiers(typeIdentifiersJSON),
            byteCount: statement.columnInt64(10),
            thumbnailPath: statement.columnString(11)
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

    private func storedBlobRelativePaths() throws -> Set<String> {
        var paths = Set<String>()

        let representationStatement = try db.prepare("SELECT storage_path FROM representations;")
        while try representationStatement.step() {
            if let path = representationStatement.columnString(0) {
                paths.insert(path)
            }
        }

        let thumbnailStatement = try db.prepare("SELECT thumbnail_path FROM clips WHERE thumbnail_path IS NOT NULL;")
        while try thumbnailStatement.step() {
            if let path = thumbnailStatement.columnString(0) {
                paths.insert(path)
            }
        }

        return paths
    }

    private func allClipIDs() throws -> Set<UUID> {
        let statement = try db.prepare("SELECT id FROM clips;")
        var ids = Set<UUID>()
        while try statement.step() {
            if let idString = statement.columnString(0),
               let id = UUID(uuidString: idString) {
                ids.insert(id)
            }
        }
        return ids
    }

    private func removeBlobDirectoryIfPresent(id: UUID) throws {
        let url = blobDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func dataForStoredFile(at url: URL) throws -> Data {
        try cipher.decryptDataIfNeeded(Data(contentsOf: url))
    }

    private func imageForStoredFile(at url: URL) throws -> NSImage? {
        let data = try dataForStoredFile(at: url)
        let image = NSImage(data: data)
        return image?.isValid == true ? image : nil
    }

    private func firstImageRepresentation(for clipID: UUID) throws -> NSImage? {
        for representation in try representations(for: clipID) {
            guard isImageTypeIdentifier(representation.typeIdentifier) else {
                continue
            }
            let url = urlForRelativePath(representation.storagePath)
            guard let data = try? dataForStoredFile(at: url),
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

    private func maxImagePixelDimension(at url: URL) throws -> CGFloat {
        let data = try dataForStoredFile(at: url)
        guard let bitmap = NSBitmapImageRep(data: data) else {
            return 0
        }
        return CGFloat(max(bitmap.pixelsWide, bitmap.pixelsHigh))
    }

    private func record(contentHash: String) throws -> ClipRecord? {
        try records(
            sql: """
            SELECT \(Self.recordColumns)
            FROM clips
            WHERE content_hash = ?
            ORDER BY last_copied_at DESC
            LIMIT 1;
            """,
            bindings: { statement in
                try statement.bind(contentHash, at: 1)
            }
        ).first
    }

    private func records(canonicalTextHash: String) throws -> [ClipRecord] {
        try records(
            sql: """
            SELECT \(Self.recordColumns)
            FROM clips
            WHERE canonical_text_hash = ?
            ORDER BY last_copied_at DESC;
            """,
            bindings: { statement in
                try statement.bind(canonicalTextHash, at: 1)
            }
        )
    }

    private func legacyTextRecords(
        matchingCanonicalTextHash canonicalTextHash: String,
        summary: String
    ) throws -> [ClipRecord] {
        let candidates = try records(
            sql: """
            SELECT \(Self.recordColumns)
            FROM clips
            WHERE canonical_text_hash IS NULL
              AND primary_kind IN (?, ?, ?)
            ORDER BY last_copied_at DESC;
            """,
            bindings: { statement in
                try statement.bind(ClipPrimaryKind.text.rawValue, at: 1)
                try statement.bind(ClipPrimaryKind.richText.rawValue, at: 2)
                try statement.bind(ClipPrimaryKind.mixed.rawValue, at: 3)
            }
        )

        var matches: [ClipRecord] = []
        for candidate in candidates where candidate.summary == summary {
            guard let candidateHash = try self.canonicalTextHash(for: candidate) else {
                continue
            }
            try updateCanonicalTextHash(id: candidate.id, canonicalTextHash: candidateHash)
            if candidateHash == canonicalTextHash {
                matches.append(candidate)
            }
        }
        return matches
    }

    private func semanticDuplicateRecords(
        canonicalTextHash: String,
        summary: String
    ) throws -> [ClipRecord] {
        let indexedRecords = try records(canonicalTextHash: canonicalTextHash)
        let legacyRecords = try legacyTextRecords(
            matchingCanonicalTextHash: canonicalTextHash,
            summary: summary
        )
        return Dictionary(
            uniqueKeysWithValues: (indexedRecords + legacyRecords).map { ($0.id, $0) }
        ).values.map { $0 }
    }

    private func preferredSemanticDuplicate(from records: [ClipRecord]) -> ClipRecord? {
        records.max { lhs, rhs in
            if (lhs.thumbnailPath != nil) != (rhs.thumbnailPath != nil) {
                return lhs.thumbnailPath == nil
            }
            if lhs.byteCount != rhs.byteCount {
                return lhs.byteCount < rhs.byteCount
            }
            return lhs.lastCopiedAt < rhs.lastCopiedAt
        }
    }

    private func canonicalTextHash(for record: ClipRecord) throws -> String? {
        if let canonicalTextHash = record.canonicalTextHash {
            return canonicalTextHash
        }
        return PasteboardArchiver.canonicalTextHash(
            for: try capturedRepresentations(for: record.id),
            primaryKind: record.primaryKind
        )
    }

    private func capturedRepresentations(for clipID: UUID) throws -> [CapturedRepresentation] {
        try representations(for: clipID).compactMap { representation in
            let url = urlForRelativePath(representation.storagePath)
            guard let data = try? dataForStoredFile(at: url) else {
                return nil
            }
            return CapturedRepresentation(
                itemIndex: representation.itemIndex,
                typeIdentifier: representation.typeIdentifier,
                data: data
            )
        }
    }

    private func idsOlderThan(_ cutoff: Date) throws -> [UUID] {
        let statement = try db.prepare("SELECT id FROM clips WHERE last_copied_at < ?;")
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
        let data = try JSONEncoder().encode(typeIdentifiers)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeTypeIdentifiers(_ string: String) throws -> [String] {
        guard let data = string.data(using: .utf8) else {
            return []
        }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func searchTerms(from query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func record(_ record: ClipRecord, matchesTerms terms: [String]) -> Bool {
        let searchableContent = (
            record.summary + " " +
                record.searchableText + " " +
                record.typeIdentifiers.joined(separator: " ")
        ).lowercased()
        return terms.allSatisfy { searchableContent.contains($0) }
    }
}
