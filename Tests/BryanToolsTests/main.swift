import AppKit
import BryanToolsShared
import ClipboardHistoryCore
import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() {
        throw TestFailure(description: message)
    }
}

private func require<T>(_ value: @autoclosure () throws -> T?, _ message: String) throws -> T {
    guard let value = try value() else {
        throw TestFailure(description: message)
    }
    return value
}

private final class Fixture {
    let directory: URL
    let store: ClipStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BryanToolsTests-\(UUID().uuidString)", isDirectory: true)
        store = try ClipStore(rootDirectory: directory)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func namedPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("BryanToolsTests-\(UUID().uuidString)"))
}

private func writeString(_ string: String, to pasteboard: NSPasteboard) throws {
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(string, forType: .string)
    try requirePasteboardWrite(pasteboard.writeObjects([item]))
}

private func capturedString(_ string: String) throws -> CapturedClip {
    let pasteboard = namedPasteboard()
    try writeString(string, to: pasteboard)
    return try require(
        PasteboardArchiver.capture(
            from: pasteboard,
            sourceApplication: nil,
            maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
            maxEventBytes: ClipStore.defaultMaxEventBytes
        ),
        "Expected captured string"
    )
}

private func requirePasteboardWrite(_ success: Bool) throws {
    if !success {
        throw TestFailure(description: "Expected pasteboard write to succeed")
    }
}

private func makePNGData(size: NSSize = NSSize(width: 2, height: 2)) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw TestFailure(description: "Expected test PNG encoding to succeed")
    }
    return png
}

private func testInsertSearchDeleteAndPurge() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    try writeString("hello searchable clipboard", to: pasteboard)

    let record = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected captured text record")
    try expect(try fixture.store.search("searchable").map(\.id) == [record.id], "Expected FTS search to find captured record")
    try expect(try fixture.store.search("missing").isEmpty, "Expected missing query to return no records")

    try fixture.store.deleteClip(id: record.id)
    try expect(try fixture.store.search().isEmpty, "Expected delete to remove record")
}

private func testRetentionPurgeRemovesOldItems() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let oldPasteboard = namedPasteboard()
    try writeString("old retained text", to: oldPasteboard)
    let oldSnapshot = try require(
        PasteboardArchiver.capture(
            from: oldPasteboard,
            sourceApplication: nil,
            maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
            maxEventBytes: ClipStore.defaultMaxEventBytes
        ),
        "Expected old snapshot"
    )
    let oldRecord = try require(
        try fixture.store.insert(oldSnapshot, createdAt: Date(timeIntervalSinceNow: -100 * 24 * 60 * 60)),
        "Expected old record insertion"
    )

    let newPasteboard = namedPasteboard()
    try writeString("new retained text", to: newPasteboard)
    let newRecord = try require(try fixture.store.captureCurrentPasteboard(newPasteboard), "Expected new record insertion")

    try fixture.store.purgeExpired()

    try expect(try fixture.store.record(id: oldRecord.id) == nil, "Expected expired record to purge")
    try expect(try fixture.store.record(id: newRecord.id) != nil, "Expected fresh record to remain")
}

private func testImmediateDuplicateRefreshesExistingRecord() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    try writeString("duplicate text", to: pasteboard)

    let firstRecord = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected first duplicate source to insert")
    let refreshedRecord = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected duplicate source to refresh existing record")

    try expect(refreshedRecord.id == firstRecord.id, "Expected duplicate source to reuse existing record")
    try expect(try fixture.store.search().count == 1, "Expected one stored record after duplicate refresh")
}

private func testDuplicateCopyMovesExistingRecordToTop() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let baseDate = Date(timeIntervalSinceNow: -60)
    let firstClip = try capturedString("move me back to top")
    let secondClip = try capturedString("newer clipboard item")

    let firstRecord = try require(
        try fixture.store.insert(firstClip, createdAt: baseDate),
        "Expected first record"
    )
    let secondRecord = try require(
        try fixture.store.insert(secondClip, createdAt: baseDate.addingTimeInterval(20)),
        "Expected second record"
    )

    try expect(
        try fixture.store.search().map(\.id) == [secondRecord.id, firstRecord.id],
        "Expected newer record to sort first before duplicate refresh"
    )

    let refreshedRecord = try require(
        try fixture.store.insert(firstClip, createdAt: baseDate.addingTimeInterval(40)),
        "Expected duplicate record refresh"
    )

    try expect(refreshedRecord.id == firstRecord.id, "Expected duplicate refresh to preserve original record id")
    try expect(
        try fixture.store.search().map(\.id) == [firstRecord.id, secondRecord.id],
        "Expected duplicate refresh to move existing record to top"
    )
    try expect(try fixture.store.search().count == 2, "Expected duplicate refresh not to create a new record")
}

private func testRichRepresentationsAreSerializedAndSearchable() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let item = NSPasteboardItem()
    item.setString("plain alpha", forType: .string)
    item.setData(Data("<p>html beta</p>".utf8), forType: NSPasteboard.PasteboardType("public.html"))
    item.setData(Data("{\"gamma\":true}".utf8), forType: NSPasteboard.PasteboardType("com.example.clipman-test"))
    item.setString(URL(fileURLWithPath: "/tmp/clipman-file.txt").absoluteString, forType: NSPasteboard.PasteboardType("public.file-url"))
    item.setData(try makePNGData(), forType: NSPasteboard.PasteboardType("public.png"))
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    let record = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected rich record")

    try expect(try fixture.store.representationCount(for: record.id) >= 5, "Expected all rich representations to be serialized")
    try expect(try fixture.store.search("alpha").first?.id == record.id, "Expected plain text search hit")
    try expect(try fixture.store.search("beta").first?.id == record.id, "Expected HTML text search hit")
    try expect(try fixture.store.search("clipman-file").first?.id == record.id, "Expected file URL search hit")
    try expect(try fixture.store.search("image").first?.id == record.id, "Expected image metadata search hit")
}

private func testImageThumbnailUsesHighResolutionPreview() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let item = NSPasteboardItem()
    item.setData(
        try makePNGData(size: NSSize(width: 2_000, height: 1_000)),
        forType: NSPasteboard.PasteboardType("public.png")
    )
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    let record = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected image record")
    let thumbnailPath = try require(record.thumbnailPath, "Expected image record to have a thumbnail")
    let thumbnailData = try Data(contentsOf: fixture.store.urlForRelativePath(thumbnailPath))
    let thumbnail = try require(NSBitmapImageRep(data: thumbnailData), "Expected thumbnail PNG to decode")

    try expect(
        max(thumbnail.pixelsWide, thumbnail.pixelsHigh) == Int(PasteboardArchiver.storedThumbnailMaxDimension),
        "Expected stored thumbnail to use the high-resolution preview max dimension"
    )
}

private func testRestoreRoundTripUsesNamedPasteboard() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let source = namedPasteboard()
    source.clearContents()

    let item = NSPasteboardItem()
    item.setString("round trip text", forType: .string)
    item.setData(Data([0, 1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.binary"))
    try requirePasteboardWrite(source.writeObjects([item]))

    let record = try require(try fixture.store.captureCurrentPasteboard(source), "Expected source capture")
    let destination = namedPasteboard()
    try fixture.store.restoreClip(id: record.id, to: destination)

    let restored = try require(destination.pasteboardItems?.first, "Expected restored pasteboard item")
    try expect(restored.string(forType: .string) == "round trip text", "Expected restored string")
    try expect(
        restored.data(forType: NSPasteboard.PasteboardType("com.example.binary")) == Data([0, 1, 2, 3]),
        "Expected restored custom data"
    )
}

private func testOnePasswordMarkerIsSkipped() throws {
    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let item = NSPasteboardItem()
    item.setString("should-not-be-captured", forType: .string)
    item.setData(Data("marker".utf8), forType: NSPasteboard.PasteboardType("com.agilebits.onepassword"))
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected 1Password pasteboard marker to be skipped")
}

private func testLikelyChromeExtensionPasswordIsSkipped() throws {
    let pasteboard = namedPasteboard()
    try writeString("A8f!qTz$9Lm#vP2x", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected likely password copied from Chrome to be skipped")
}

private func testLikelyChromeExtensionOTPIsSkipped() throws {
    let pasteboard = namedPasteboard()
    try writeString("123456", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected likely one-time password copied from Chrome to be skipped")
}

private func testNormalChromeTextIsCaptured() throws {
    let pasteboard = namedPasteboard()
    try writeString("Quarterly planning notes for the design review", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured != nil, "Expected normal text copied from Chrome to be captured")
}

private func testLikelyPasswordFromNonBrowserIsCapturedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("A8f!qTz$9Lm#vP2x", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured != nil, "Expected secret-shaped text from non-browser apps to require an explicit privacy marker")
}

private func testPlainTextExtractorReadsString() throws {
    let pasteboard = namedPasteboard()
    try writeString("already plain", to: pasteboard)

    try expect(
        PasteboardPlainTextExtractor.plainText(from: pasteboard) == "already plain",
        "Expected plain string extraction"
    )
}

private func testPlainTextExtractorReadsHTML() throws {
    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let item = NSPasteboardItem()
    item.setData(Data("<p>Hello <strong>plain</strong></p>".utf8), forType: NSPasteboard.PasteboardType("public.html"))
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    let text = try require(PasteboardPlainTextExtractor.plainText(from: pasteboard), "Expected HTML plain text extraction")
    try expect(text.contains("Hello plain"), "Expected HTML formatting to be stripped")
}

private func testPlainTextExtractorReadsRTF() throws {
    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let attributed = NSAttributedString(string: "rich text")
    let data = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let item = NSPasteboardItem()
    item.setData(data, forType: NSPasteboard.PasteboardType("public.rtf"))
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    try expect(
        PasteboardPlainTextExtractor.plainText(from: pasteboard) == "rich text",
        "Expected RTF formatting to be stripped"
    )
}

private func testPlainTextExtractorIgnoresImages() throws {
    let pasteboard = namedPasteboard()
    pasteboard.clearContents()

    let item = NSPasteboardItem()
    item.setData(try makePNGData(), forType: NSPasteboard.PasteboardType("public.png"))
    try requirePasteboardWrite(pasteboard.writeObjects([item]))

    try expect(PasteboardPlainTextExtractor.plainText(from: pasteboard) == nil, "Expected image-only clipboard to produce no text")
}

private func testColorPickerDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultColorPickerValue.displayString == "Command-Shift-~",
        "Expected ColorPicker default hotkey to be Command-Shift-~"
    )
}

private func testMacroTextDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultMacroTextValue.displayString == "Command-Shift-/",
        "Expected MacroText default hotkey to be Command-Shift-/"
    )
}

private func testQuickTaskDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultQuickTaskValue.displayString == "Command-Space",
        "Expected QuickTask default hotkey to be Command-Space"
    )
    try expect(
        AppHotKey.fallbackQuickTaskValue.displayString == "Option-Space",
        "Expected QuickTask fallback hotkey to be Option-Space"
    )
}

private func testShotFloatDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultShotFloatValue.displayString == "Command-Shift-2",
        "Expected ShotFloat default hotkey to be Command-Shift-2"
    )
}

private func makeTemporaryDefaults() throws -> (UserDefaults, String) {
    let suiteName = "BryanToolsTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "Expected temporary user defaults")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private func testMigrationCopiesLegacyClipManData() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BryanToolsMigration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let legacy = root.appendingPathComponent("ClipMan", isDirectory: true)
    let destination = root
        .appendingPathComponent("Bryan Tools", isDirectory: true)
        .appendingPathComponent("Clipboard History", isDirectory: true)
    try FileManager.default.createDirectory(
        at: legacy.appendingPathComponent("Blobs", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("legacy database".utf8).write(to: legacy.appendingPathComponent("ClipMan.sqlite"))
    try Data("legacy blob".utf8).write(to: legacy.appendingPathComponent("Blobs/blob.txt"))

    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let outcome = try ClipboardHistoryMigration.migrateClipManDataIfNeeded(
        defaults: defaults,
        legacyRoot: legacy,
        destinationRoot: destination
    )

    try expect(outcome == .copied, "Expected migration to copy legacy data")
    try expect(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("ClipMan.sqlite").path),
        "Expected copied database"
    )
    try expect(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("Blobs/blob.txt").path),
        "Expected copied blob"
    )
    try expect(
        FileManager.default.fileExists(atPath: legacy.appendingPathComponent("ClipMan.sqlite").path),
        "Expected legacy data to remain"
    )
    try expect(
        defaults.bool(forKey: ClipboardHistoryMigration.migrationCompleteKey),
        "Expected migration completion marker"
    )
}

private func testMigrationSkipsWhenAlreadyComplete() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BryanToolsMigration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let legacy = root.appendingPathComponent("ClipMan", isDirectory: true)
    let destination = root
        .appendingPathComponent("Bryan Tools", isDirectory: true)
        .appendingPathComponent("Clipboard History", isDirectory: true)

    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: ClipboardHistoryMigration.migrationCompleteKey)

    let outcome = try ClipboardHistoryMigration.migrateClipManDataIfNeeded(
        defaults: defaults,
        legacyRoot: legacy,
        destinationRoot: destination
    )

    try expect(outcome == .alreadyCompleted, "Expected completed migration to no-op")
    try expect(
        !FileManager.default.fileExists(atPath: destination.path),
        "Expected no destination data to be created"
    )
}

private func testMigrationFreshInstallWithoutLegacyData() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BryanToolsMigration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let legacy = root.appendingPathComponent("ClipMan", isDirectory: true)
    let destination = root
        .appendingPathComponent("Bryan Tools", isDirectory: true)
        .appendingPathComponent("Clipboard History", isDirectory: true)

    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let outcome = try ClipboardHistoryMigration.migrateClipManDataIfNeeded(
        defaults: defaults,
        legacyRoot: legacy,
        destinationRoot: destination
    )

    try expect(outcome == .legacyMissing, "Expected fresh install migration to skip missing legacy data")
    try expect(
        !FileManager.default.fileExists(atPath: destination.path),
        "Expected no destination data to be created"
    )
    try expect(
        defaults.bool(forKey: ClipboardHistoryMigration.migrationCompleteKey),
        "Expected migration completion marker"
    )
}

private let tests: [(String, () throws -> Void)] = [
    ("insert/search/delete/purge", testInsertSearchDeleteAndPurge),
    ("90-day retention purge", testRetentionPurgeRemovesOldItems),
    ("immediate duplicate refresh", testImmediateDuplicateRefreshesExistingRecord),
    ("duplicate copy moves existing record to top", testDuplicateCopyMovesExistingRecordToTop),
    ("rich representation serialization/search", testRichRepresentationsAreSerializedAndSearchable),
    ("named pasteboard restore round trip", testRestoreRoundTripUsesNamedPasteboard),
    ("1Password pasteboard marker skip", testOnePasswordMarkerIsSkipped),
    ("Chrome extension password skip", testLikelyChromeExtensionPasswordIsSkipped),
    ("Chrome extension OTP skip", testLikelyChromeExtensionOTPIsSkipped),
    ("normal Chrome text capture", testNormalChromeTextIsCaptured),
    ("non-browser secret-shaped text capture", testLikelyPasswordFromNonBrowserIsCapturedWithoutMarker),
    ("plain text extractor string", testPlainTextExtractorReadsString),
    ("plain text extractor HTML", testPlainTextExtractorReadsHTML),
    ("plain text extractor RTF", testPlainTextExtractorReadsRTF),
    ("plain text extractor image ignore", testPlainTextExtractorIgnoresImages),
    ("image thumbnail high-resolution preview", testImageThumbnailUsesHighResolutionPreview),
    ("ColorPicker default hotkey", testColorPickerDefaultHotKey),
    ("MacroText default hotkey", testMacroTextDefaultHotKey),
    ("QuickTask default hotkey", testQuickTaskDefaultHotKey),
    ("ShotFloat default hotkey", testShotFloatDefaultHotKey),
    ("ClipMan data migration copy", testMigrationCopiesLegacyClipManData),
    ("ClipMan data migration already complete", testMigrationSkipsWhenAlreadyComplete),
    ("ClipMan data migration fresh install", testMigrationFreshInstallWithoutLegacyData)
]

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}

if failures > 0 {
    print("\n\(failures) Bryan Tools self-test(s) failed.")
    exit(1)
}

print("\nAll Bryan Tools self-tests passed.")
