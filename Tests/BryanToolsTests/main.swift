import AppKit
import BryanToolsShared
import Carbon
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
        store = try ClipStore(
            rootDirectory: directory,
            encryptionKeyData: ClipStoreEncryptionKey.deterministicTestKey()
        )
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

private func storageContainsPlaintext(_ text: String, in directory: URL) throws -> Bool {
    let needle = Data(text.utf8)
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return false
    }

    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            continue
        }
        let data = try Data(contentsOf: url)
        if data.range(of: needle) != nil {
            return true
        }
    }
    return false
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

private func testClipboardStorageEncryptsSearchableContentAndRestores() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let secretText = "sensitive-token-\(UUID().uuidString)"
    let pasteboard = namedPasteboard()
    try writeString(secretText, to: pasteboard)

    let record = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected encrypted text record")
    try expect(
        try fixture.store.search(secretText).map(\.id) == [record.id],
        "Expected encrypted records to remain searchable"
    )
    try expect(
        try !storageContainsPlaintext(secretText, in: fixture.directory),
        "Expected Clipboard History storage not to contain raw captured text"
    )

    let restorePasteboard = namedPasteboard()
    try fixture.store.restoreClip(id: record.id, to: restorePasteboard)
    try expect(
        restorePasteboard.string(forType: .string) == secretText,
        "Expected encrypted clipboard representation to restore original text"
    )
}

private func testClipboardStorageRemovesOrphanedBlobDirectories() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    try writeString("orphan cleanup survivor", to: pasteboard)
    let record = try require(try fixture.store.captureCurrentPasteboard(pasteboard), "Expected record before orphan cleanup")

    let orphanID = UUID()
    let orphanDirectory = fixture.store.blobDirectory.appendingPathComponent(orphanID.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
    try Data("orphan".utf8).write(to: orphanDirectory.appendingPathComponent("orphan.bin"))

    try fixture.store.purgeExpired()

    try expect(!FileManager.default.fileExists(atPath: orphanDirectory.path), "Expected orphaned blob directory to be removed")
    try expect(try fixture.store.record(id: record.id) != nil, "Expected live clip to survive orphan cleanup")
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
    let rawThumbnailData = try Data(contentsOf: fixture.store.urlForRelativePath(thumbnailPath))
    try expect(NSBitmapImageRep(data: rawThumbnailData) == nil, "Expected raw thumbnail file to be encrypted")
    let thumbnailImage = try require(try fixture.store.thumbnailImage(for: record), "Expected thumbnail image to decode through store")
    let thumbnail = try require(thumbnailImage.representations.first, "Expected thumbnail image to have a representation")

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

private func testOnePasswordAppSourceIsSkipped() throws {
    let pasteboard = namedPasteboard()
    try writeString("A8f!qTz$9Lm#vP2x", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.1password.1password", localizedName: "1Password"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected 1Password app source to be skipped")
}

private func testChromeSecretShapedTextIsSkippedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("A8f!qTz$9Lm#vP2x", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected Chrome secret-shaped text without a 1Password marker to be skipped")
}

private func testChromeShortPasswordIsSkippedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("Password1!", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected short Chrome password-shaped text without a marker to be skipped")
}

private func testChromeMemorablePasswordIsSkippedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("orbit-velvet-afternoon-harbor", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured == nil, "Expected Chrome memorable-password-shaped text without a marker to be skipped")
}

private func testChromeOTPIsCapturedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("123456", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured != nil, "Expected Chrome OTP-shaped text without a 1Password marker to be captured")
}

private func testChromeUUIDIsCapturedWithoutMarker() throws {
    let pasteboard = namedPasteboard()
    try writeString("550e8400-e29b-41d4-a716-446655440000", to: pasteboard)

    let captured = PasteboardArchiver.capture(
        from: pasteboard,
        sourceApplicationInfo: PasteboardSourceApplication(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome"),
        maxRepresentationBytes: ClipStore.defaultMaxRepresentationBytes,
        maxEventBytes: ClipStore.defaultMaxEventBytes
    )
    try expect(captured != nil, "Expected UUID copied from Chrome without a 1Password marker to be captured")
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

private func macroTextTemplateTestClock() throws -> (now: Date, calendar: Calendar, timeZone: TimeZone) {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try require(
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 15)),
        "Expected MacroText test date"
    )
    return (now, calendar, timeZone)
}

private func testMacroTextDateTemplateHourOffset() throws {
    let clock = try macroTextTemplateTestClock()
    let rendered = MacroTextTemplateRenderer.render(
        "{yyyy-MM-dd'T'hh:-2h}",
        now: clock.now,
        calendar: clock.calendar,
        timeZone: clock.timeZone
    )

    try expect(
        rendered == "2026-05-27T13",
        "Expected MacroText hour offset date template to render from expansion time"
    )
}

private func testMacroTextDateTemplateDayOffset() throws {
    let clock = try macroTextTemplateTestClock()
    let rendered = MacroTextTemplateRenderer.render(
        "Yesterday: {yyyy-MM-dd:-1d}",
        now: clock.now,
        calendar: clock.calendar,
        timeZone: clock.timeZone
    )

    try expect(
        rendered == "Yesterday: 2026-05-26",
        "Expected MacroText day offset date template to render from expansion time"
    )
}

private func testMacroTextTemplateLeavesNonDateBracesUntouched() throws {
    let clock = try macroTextTemplateTestClock()
    let rendered = MacroTextTemplateRenderer.render(
        "Keep {name} and {hello}",
        now: clock.now,
        calendar: clock.calendar,
        timeZone: clock.timeZone
    )

    try expect(
        rendered == "Keep {name} and {hello}",
        "Expected MacroText date template renderer to leave non-date brace content untouched"
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

private func testQuickTaskCommandLinePrefix() throws {
    try expect(
        QuickTaskCommandLine.commandText(fromPrefixedQuery: ">pwd") == "pwd",
        "Expected QuickTask command mode to strip the command prefix"
    )
    try expect(
        QuickTaskCommandLine.commandText(fromPrefixedQuery: "> pwd") == "pwd",
        "Expected QuickTask command mode to strip one leading space after the prefix"
    )
    try expect(
        QuickTaskCommandLine.commandText(fromPrefixedQuery: "pwd") == nil,
        "Expected QuickTask command mode to require the command prefix"
    )
}

private func testMouseMacroCommandParser() throws {
    let command = try require(
        MouseMacroCommandParser.parse("cmd+shift+ctrl+4")?.first,
        "Expected MouseMacro command to parse"
    )
    try expect(
        command.keyCode == UInt16(kVK_ANSI_4),
        "Expected MouseMacro command parser to resolve key 4"
    )
    try expect(
        command.flags.contains([.maskCommand, .maskShift, .maskControl]),
        "Expected MouseMacro command parser to resolve command, shift, and control modifiers"
    )
    try expect(
        MouseMacroCommandParser.parse("") == nil,
        "Expected MouseMacro command parser to reject empty commands"
    )
}

private func createValidUpdaterSourceRoot(_ sourceRoot: URL) throws {
    let scriptsDirectory = sourceRoot.appendingPathComponent("Scripts", isDirectory: true)
    let appDirectory = sourceRoot.appendingPathComponent("Sources/BryanTools/App", isDirectory: true)
    try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    try Data("#!/usr/bin/env bash\n".utf8).write(to: scriptsDirectory.appendingPathComponent("update.sh"))
    try Data(
        """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "BryanTools",
            products: [
                .executable(name: "BryanTools", targets: ["BryanTools"])
            ]
        )
        """.utf8
    ).write(to: sourceRoot.appendingPathComponent("Package.swift"))
    try Data("import SwiftUI\n".utf8).write(to: appDirectory.appendingPathComponent("BryanToolsApp.swift"))
}

private func testBryanToolsUpdateScriptResolver() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BryanToolsUpdater-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let codeSourceRoot = root.appendingPathComponent("code/BryanTools", isDirectory: true)
    let configuredSourceRoot = root.appendingPathComponent("custom/BryanTools", isDirectory: true)
    for sourceRoot in [codeSourceRoot, configuredSourceRoot] {
        try createValidUpdaterSourceRoot(sourceRoot)
    }

    let defaultResolution = try require(
        BryanToolsUpdateScriptResolver.resolve(homeDirectory: root, bundleURL: nil),
        "Expected Bryan Tools updater to resolve source from home candidates"
    )
    try expect(
        defaultResolution.sourceRoot.standardizedFileURL == codeSourceRoot.standardizedFileURL,
        "Expected Bryan Tools updater to prefer ~/code/BryanTools"
    )

    let configuredResolution = try require(
        BryanToolsUpdateScriptResolver.resolve(
            configuredSourceRoot: configuredSourceRoot,
            homeDirectory: root,
            bundleURL: nil
        ),
        "Expected Bryan Tools updater to resolve configured source root"
    )
    try expect(
        configuredResolution.sourceRoot.standardizedFileURL == configuredSourceRoot.standardizedFileURL,
        "Expected Bryan Tools updater to prefer configured source root"
    )

    let buildSourceRoot = root.appendingPathComponent("buildSource/BryanTools", isDirectory: true)
    try createValidUpdaterSourceRoot(buildSourceRoot)

    let buildBundleURL = buildSourceRoot
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("Bryan Tools.app", isDirectory: true)
    let buildResolution = try require(
        BryanToolsUpdateScriptResolver.resolve(
            homeDirectory: root.appendingPathComponent("emptyHome", isDirectory: true),
            bundleURL: buildBundleURL
        ),
        "Expected Bryan Tools updater to resolve source root for a .build app bundle"
    )
    try expect(
        buildResolution.sourceRoot.standardizedFileURL == buildSourceRoot.standardizedFileURL,
        "Expected Bryan Tools updater to resolve the source root from a .build app bundle"
    )

    let scriptOnlyRoot = root.appendingPathComponent("scriptOnly/BryanTools", isDirectory: true)
    let scriptOnlyDirectory = scriptOnlyRoot.appendingPathComponent("Scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: scriptOnlyDirectory, withIntermediateDirectories: true)
    try Data("#!/usr/bin/env bash\n".utf8).write(to: scriptOnlyDirectory.appendingPathComponent("update.sh"))

    try expect(
        BryanToolsUpdateScriptResolver.resolve(
            configuredSourceRoot: scriptOnlyRoot,
            homeDirectory: root.appendingPathComponent("emptyHome2", isDirectory: true),
            bundleURL: nil
        ) == nil,
        "Expected updater resolver to reject a script-only source root"
    )
}

private func testBryanToolsAutoStartDefaultsAndLaunchAgent() throws {
    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try expect(
        BryanToolsAutoStart.isEnabledByDefault(defaults: defaults),
        "Expected Bryan Tools auto start to default on"
    )

    defaults.set(false, forKey: BryanToolsAutoStart.defaultsKey)
    try expect(
        !BryanToolsAutoStart.isEnabledByDefault(defaults: defaults),
        "Expected Bryan Tools auto start preference to persist disabled state"
    )

    let home = URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
    try expect(
        BryanToolsAutoStart.launchAgentURL(homeDirectory: home).path
            == "/tmp/test-home/Library/LaunchAgents/com.local.BryanTools.autostart.plist",
        "Expected auto start LaunchAgent to live under the user LaunchAgents folder"
    )

    let plist = BryanToolsAutoStart.launchAgentPlist()
    try expect(
        plist["Label"] as? String == BryanToolsAutoStart.launchAgentLabel,
        "Expected auto start LaunchAgent label"
    )
    try expect(
        plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "/Applications/Bryan Tools.app"],
        "Expected auto start LaunchAgent to open the installed Applications app"
    )
    try expect(plist["RunAtLoad"] as? Bool == true, "Expected auto start LaunchAgent to run at login")
}

private func testShotFloatDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultShotFloatValue.displayString == "Command-Shift-2",
        "Expected ShotFloat default hotkey to be Command-Shift-2"
    )
}

private func testScreenOCRDefaultHotKey() throws {
    try expect(
        AppHotKey.defaultScreenOCRValue.displayString == "Command-Shift-Y",
        "Expected Screen OCR default hotkey to be Command-Shift-Y"
    )
}

private func trayCalTestCalendar() -> Calendar {
    TrayCalCalendar.defaultCalendar(timeZone: TimeZone(secondsFromGMT: 0)!)
}

private func trayCalDate(year: Int, month: Int, day: Int) throws -> Date {
    let calendar = trayCalTestCalendar()
    let components = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day
    )
    return try require(components.date, "Expected TrayCal test date")
}

private func testTrayCalToolIdentifier() throws {
    try expect(ToolIdentifier.trayCal.displayName == "TrayCal", "Expected TrayCal tool display name")
}

private func testTrayCalStatusTitleFormatting() throws {
    let date = try trayCalDate(year: 2026, month: 5, day: 22)
    try expect(
        TrayCalCalendar.statusTitle(for: date, calendar: trayCalTestCalendar()) == "Fri, May 22",
        "Expected TrayCal status title to use fixed format"
    )

    let september = try trayCalDate(year: 2026, month: 9, day: 3)
    try expect(
        TrayCalCalendar.statusTitle(for: september, calendar: trayCalTestCalendar()) == "Thu, Sep 3",
        "Expected TrayCal status title to truncate longer month names"
    )
}

private func testTrayCalPopupMonthNameFormatting() throws {
    let january = try trayCalDate(year: 2026, month: 1, day: 22)
    try expect(
        TrayCalCalendar.monthName(for: january, calendar: trayCalTestCalendar()) == "Jan",
        "Expected TrayCal popup month header to use a three-character month"
    )
}

private func testTrayCalMay2026MonthGrid() throws {
    let calendar = trayCalTestCalendar()
    let may = try trayCalDate(year: 2026, month: 5, day: 22)
    let grid = TrayCalCalendar.monthGrid(displayedMonth: may, today: may, calendar: calendar)

    try expect(grid.count == 42, "Expected TrayCal month grid to contain six weeks")
    try expect(grid.first?.day == 26 && grid.first?.isInDisplayedMonth == false, "Expected May 2026 grid to begin with Apr 26")
    try expect(grid[5].day == 1 && grid[5].isInDisplayedMonth, "Expected May 1 to land on Friday")
    try expect(grid[6].day == 2 && grid[6].isInDisplayedMonth, "Expected May 2 to land on Saturday")
    try expect(grid.last?.day == 6 && grid.last?.isInDisplayedMonth == false, "Expected May 2026 grid to end with Jun 6")
    try expect(grid.filter(\.isToday).map(\.day) == [22], "Expected May 22 to be highlighted as today")
}

private func testTrayCalPaydaySchedule() throws {
    let calendar = trayCalTestCalendar()
    let may = try trayCalDate(year: 2026, month: 5, day: 22)
    let grid = TrayCalCalendar.monthGrid(displayedMonth: may, today: may, calendar: calendar)
    let paydays = grid
        .filter { $0.isInDisplayedMonth && $0.isPayday }
        .map(\.day)

    try expect(paydays == [1, 15, 29], "Expected TrayCal to flag every other Friday from the May 29, 2026 anchor")
    try expect(
        TrayCalCalendar.isPayday(try trayCalDate(year: 2026, month: 6, day: 12), calendar: calendar),
        "Expected June 12, 2026 to be a payday"
    )
    try expect(
        !TrayCalCalendar.isPayday(try trayCalDate(year: 2026, month: 6, day: 5), calendar: calendar),
        "Expected June 5, 2026 not to be a payday"
    )
}

private func testTrayCalTodayResetState() throws {
    let calendar = trayCalTestCalendar()
    let today = try trayCalDate(year: 2026, month: 5, day: 22)
    var state = TrayCalCalendarState(
        displayedMonth: try trayCalDate(year: 2026, month: 8, day: 4),
        calendar: calendar
    )

    state.returnToToday(today, calendar: calendar)

    try expect(
        calendar.isDate(state.displayedMonth, equalTo: today, toGranularity: .month),
        "Expected TrayCal today reset to return to the current month"
    )
}

private func testTrayCalPopoverResetAfterCloseThreshold() throws {
    let openingDate = try trayCalDate(year: 2026, month: 5, day: 22)

    try expect(
        !TrayCalCalendar.shouldResetPopoverAfterClose(
            closedAt: openingDate.addingTimeInterval(-119),
            openingAt: openingDate
        ),
        "Expected TrayCal popover to preserve the displayed month before the two-minute close threshold"
    )
    try expect(
        TrayCalCalendar.shouldResetPopoverAfterClose(
            closedAt: openingDate.addingTimeInterval(-120),
            openingAt: openingDate
        ),
        "Expected TrayCal popover to reset to today after being closed for two minutes"
    )
    try expect(
        !TrayCalCalendar.shouldResetPopoverAfterClose(closedAt: nil, openingAt: openingDate),
        "Expected TrayCal popover to preserve the displayed month when it has no close timestamp"
    )
}

private func testTrayCalMonthAndYearJumpState() throws {
    let calendar = trayCalTestCalendar()
    var state = TrayCalCalendarState(
        displayedMonth: try trayCalDate(year: 2026, month: 5, day: 22),
        calendar: calendar
    )

    state.showMonth(11, calendar: calendar)
    try expect(
        TrayCalCalendar.month(for: state.displayedMonth, calendar: calendar) == 11
            && TrayCalCalendar.year(for: state.displayedMonth, calendar: calendar) == 2026,
        "Expected TrayCal month picker state to preserve year while changing month"
    )

    state.showYear(2031, calendar: calendar)
    try expect(
        TrayCalCalendar.month(for: state.displayedMonth, calendar: calendar) == 11
            && TrayCalCalendar.year(for: state.displayedMonth, calendar: calendar) == 2031,
        "Expected TrayCal year picker state to preserve month while changing year"
    )
}

private func utcHourTestDate() throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = UTCHourDisplay.utcTimeZone
    return try require(
        calendar.date(from: DateComponents(
            timeZone: UTCHourDisplay.utcTimeZone,
            year: 2026,
            month: 6,
            day: 16,
            hour: 20,
            minute: 37
        )),
        "Expected UTC Hour test date"
    )
}

private func testUTCHourToolIdentifier() throws {
    try expect(ToolIdentifier.utcHour.displayName == "UTC Hour", "Expected UTC Hour tool display name")
}

private func testUTCHourStatusTitleFormatting() throws {
    let date = try utcHourTestDate()
    try expect(
        UTCHourDisplay.statusTitle(for: date) == "2026-06-16T20",
        "Expected UTC Hour status title to use yyyy-MM-dd'T'HH format"
    )
}

private func testUTCHourPacificLookupRows() throws {
    let date = try utcHourTestDate()
    let rows = UTCHourDisplay.lookupRows(centeredAt: date)
    let currentRows = rows.filter(\.isCurrentHour)

    try expect(rows.count == 145, "Expected UTC Hour lookup to load 72 prior, current, and 72 future hours")
    try expect(currentRows.count == 1, "Expected UTC Hour lookup to mark one current hour")
    try expect(currentRows.first?.utcTitle == "2026-06-16T20", "Expected current UTC lookup row")
    try expect(currentRows.first?.pacificTitle == "June 16,  1:00pm", "Expected current Pacific lookup row to include date and padded 12-hour time")
    try expect(currentRows.first?.isPacificMidnight == false, "Expected current Pacific lookup row not to be marked as midnight")
    try expect(rows.first?.utcTitle == "2026-06-13T20", "Expected first UTC lookup row to be 72 hours prior")
    try expect(rows.last?.utcTitle == "2026-06-19T20", "Expected last UTC lookup row to be 72 hours ahead")

    let midnightRow = try require(
        rows.first { $0.utcTitle == "2026-06-17T07" },
        "Expected UTC lookup row for Pacific midnight"
    )
    try expect(
        midnightRow.pacificTitle == "June 17, 12:00am",
        "Expected Pacific midnight row to include the date"
    )
    try expect(midnightRow.isPacificMidnight, "Expected Pacific midnight row to be marked for outline styling")

    let oneAMRow = try require(
        rows.first { $0.utcTitle == "2026-06-17T08" },
        "Expected UTC lookup row for Pacific 1am"
    )
    try expect(oneAMRow.pacificTitle == "June 17,  1:00am", "Expected single-digit Pacific hour to include left padding")
    try expect(!oneAMRow.isPacificMidnight, "Expected non-midnight Pacific row not to be outlined")

    let tenAMRow = try require(
        rows.first { $0.utcTitle == "2026-06-17T17" },
        "Expected UTC lookup row for Pacific 10am"
    )
    try expect(tenAMRow.pacificTitle == "June 17, 10:00am", "Expected two-digit Pacific hour not to include left padding")
}

private func testUTCHourPreferenceDefaults() throws {
    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try expect(
        UTCHourPreferences.load(defaults: defaults).isEnabled == UTCHourPreferences.defaultEnabled,
        "Expected UTC Hour menu bar item to default on"
    )

    UTCHourPreferences(isEnabled: false).save(defaults: defaults)
    try expect(!UTCHourPreferences.load(defaults: defaults).isEnabled, "Expected UTC Hour enabled setting to persist")
}

private func testDiskSpaceDisplayFormatting() throws {
    let sample = DiskSpaceSample(
        sampledAt: Date(),
        availableBytes: 100_999_999_999,
        totalBytes: 500_000_000_000
    )

    try expect(sample.freeGB == 100, "Expected decimal GB conversion to round down")
    try expect(
        DiskSpaceMonitorDisplay.trayTitle(availableBytes: sample.availableBytes) == "100GB",
        "Expected disk-space tray title to use whole decimal GB"
    )
}

private func testDiskSpaceWarningThreshold() throws {
    try expect(
        DiskSpaceMonitorDisplay.isBelowWarningThreshold(
            availableBytes: 49_999_999_999,
            thresholdGB: 50
        ),
        "Expected disk-space warning below threshold"
    )
    try expect(
        !DiskSpaceMonitorDisplay.isBelowWarningThreshold(
            availableBytes: 50_000_000_000,
            thresholdGB: 50
        ),
        "Expected disk-space warning not to trigger at threshold"
    )
}

private func testDiskSpacePreferencesDefaults() throws {
    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preferences = DiskSpaceMonitorPreferences.load(defaults: defaults)
    try expect(preferences.isEnabled, "Expected Disk Space Monitor to default enabled")
    try expect(
        preferences.warningThresholdGB == 50,
        "Expected Disk Space Monitor warning threshold to default to 50GB"
    )
    try expect(
        DiskSpaceMonitorPreferences.pollInterval == 5 * 60,
        "Expected Disk Space Monitor poll interval to be five minutes"
    )
    try expect(
        preferences.visibleHistoryHours == nil,
        "Expected Disk Space Monitor to default to full graph history"
    )
}

private func testDiskSpaceVisibleHistoryPreferences() throws {
    let (defaults, suiteName) = try makeTemporaryDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var preferences = DiskSpaceMonitorPreferences(isEnabled: true, warningThresholdGB: 50, visibleHistoryHours: 12)
    preferences.save(defaults: defaults)

    try expect(
        DiskSpaceMonitorPreferences.load(defaults: defaults).visibleHistoryHours == 12,
        "Expected Disk Space Monitor visible graph hours to persist"
    )

    preferences.visibleHistoryHours = nil
    preferences.save(defaults: defaults)

    try expect(
        DiskSpaceMonitorPreferences.load(defaults: defaults).visibleHistoryHours == nil,
        "Expected blank Disk Space Monitor visible graph hours to persist as full history"
    )
}

private func testDiskSpaceVisibleHistoryFilteringAndSelection() throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let samples = [
        DiskSpaceSample(
            sampledAt: baseDate.addingTimeInterval(-10 * 3_600),
            availableBytes: 90_000_000_000,
            totalBytes: 500_000_000_000
        ),
        DiskSpaceSample(
            sampledAt: baseDate.addingTimeInterval(-2 * 3_600),
            availableBytes: 100_000_000_000,
            totalBytes: 500_000_000_000
        ),
        DiskSpaceSample(
            sampledAt: baseDate,
            availableBytes: 101_000_000_000,
            totalBytes: 500_000_000_000
        )
    ]

    try expect(
        DiskSpaceMonitorDisplay.samples(samples, visibleHistoryHours: nil) == samples,
        "Expected blank Disk Space Monitor visible graph hours to show full history"
    )
    try expect(
        DiskSpaceMonitorDisplay.samples(samples, visibleHistoryHours: 3) == Array(samples.dropFirst()),
        "Expected Disk Space Monitor visible graph hours to filter from the latest sample"
    )
    try expect(
        DiskSpaceMonitorPreferences.selectedHistoryHours(startTime: baseDate.timeIntervalSince1970 - 2.4 * 3_600, endTime: baseDate.timeIntervalSince1970) == 3,
        "Expected dragged Disk Space Monitor graph selection to round up to whole hours"
    )
}

private func testDiskSpaceSampleStoreRetention() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BryanToolsDiskSpace-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try DiskSpaceSampleStore(rootDirectory: root)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let oldSample = DiskSpaceSample(
        sampledAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
        availableBytes: 80_000_000_000,
        totalBytes: 500_000_000_000
    )
    let recentSample = DiskSpaceSample(
        sampledAt: now.addingTimeInterval(-24 * 60 * 60),
        availableBytes: 100_000_000_000,
        totalBytes: 500_000_000_000
    )
    let latestSample = DiskSpaceSample(
        sampledAt: now,
        availableBytes: 101_000_000_000,
        totalBytes: 500_000_000_000
    )

    try store.insert(oldSample)
    try store.insert(recentSample)
    try store.insert(latestSample)
    try expect(try store.latestSample() == latestSample, "Expected Disk Space Monitor latest sample query")

    try store.purgeOlderThan(now: now)
    let samples = try store.samples(since: now.addingTimeInterval(-30 * 24 * 60 * 60))
    let limitedSamples = try store.samples(since: now.addingTimeInterval(-30 * 24 * 60 * 60), limit: 1)

    try expect(samples == [recentSample, latestSample], "Expected Disk Space Monitor to purge samples older than 30 days")
    try expect(limitedSamples == [latestSample], "Expected limited Disk Space Monitor sample query to keep the latest samples")
}

private func testScreenOCRTextFormatterSortsAndTrimsLines() throws {
    let text = ScreenOCRTextFormatter.text(from: [
        ScreenOCRRecognizedLine(text: "  bottom  ", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
        ScreenOCRRecognizedLine(text: "top right", boundingBox: CGRect(x: 0.7, y: 0.8, width: 0.2, height: 0.1)),
        ScreenOCRRecognizedLine(text: "top left", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)),
        ScreenOCRRecognizedLine(text: "   ", boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.2, height: 0.1))
    ])

    try expect(
        text == "top left\ntop right\nbottom",
        "Expected OCR text formatter to trim empty lines and sort top-to-bottom, left-to-right"
    )
}

private func testClipboardHistoryTextRecorderCapturesRecognizedText() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    let record = try require(
        try ClipboardHistoryTextRecorder.recordText(
            "recognized text",
            to: pasteboard,
            store: fixture.store,
            sourceApplication: nil
        ),
        "Expected recognized text to be captured"
    )

    try expect(pasteboard.string(forType: .string) == "recognized text", "Expected recognized text on pasteboard")
    try expect(record.summary == "recognized text", "Expected recognized text record summary")
    try expect(try fixture.store.search("recognized").map(\.id) == [record.id], "Expected recognized text in history search")
}

private func testClipboardHistoryTextRecorderIgnoresEmptyText() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }

    let pasteboard = namedPasteboard()
    try writeString("existing clipboard text", to: pasteboard)

    let record = try ClipboardHistoryTextRecorder.recordText(
        "",
        to: pasteboard,
        store: fixture.store,
        sourceApplication: nil
    )

    try expect(record == nil, "Expected empty OCR text not to create history")
    try expect(pasteboard.string(forType: .string) == "existing clipboard text", "Expected empty OCR text to leave pasteboard unchanged")
    try expect(try fixture.store.search().isEmpty, "Expected empty OCR text to leave history unchanged")
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
    ("clipboard storage encryption restore", testClipboardStorageEncryptsSearchableContentAndRestores),
    ("clipboard orphan blob cleanup", testClipboardStorageRemovesOrphanedBlobDirectories),
    ("90-day retention purge", testRetentionPurgeRemovesOldItems),
    ("immediate duplicate refresh", testImmediateDuplicateRefreshesExistingRecord),
    ("duplicate copy moves existing record to top", testDuplicateCopyMovesExistingRecordToTop),
    ("rich representation serialization/search", testRichRepresentationsAreSerializedAndSearchable),
    ("named pasteboard restore round trip", testRestoreRoundTripUsesNamedPasteboard),
    ("1Password pasteboard marker skip", testOnePasswordMarkerIsSkipped),
    ("1Password app source skip", testOnePasswordAppSourceIsSkipped),
    ("Chrome secret-shaped text skip", testChromeSecretShapedTextIsSkippedWithoutMarker),
    ("Chrome short password skip", testChromeShortPasswordIsSkippedWithoutMarker),
    ("Chrome memorable password skip", testChromeMemorablePasswordIsSkippedWithoutMarker),
    ("Chrome OTP-shaped text capture", testChromeOTPIsCapturedWithoutMarker),
    ("Chrome UUID capture", testChromeUUIDIsCapturedWithoutMarker),
    ("normal Chrome text capture", testNormalChromeTextIsCaptured),
    ("non-browser secret-shaped text capture", testLikelyPasswordFromNonBrowserIsCapturedWithoutMarker),
    ("plain text extractor string", testPlainTextExtractorReadsString),
    ("plain text extractor HTML", testPlainTextExtractorReadsHTML),
    ("plain text extractor RTF", testPlainTextExtractorReadsRTF),
    ("plain text extractor image ignore", testPlainTextExtractorIgnoresImages),
    ("image thumbnail high-resolution preview", testImageThumbnailUsesHighResolutionPreview),
    ("ColorPicker default hotkey", testColorPickerDefaultHotKey),
    ("MacroText default hotkey", testMacroTextDefaultHotKey),
    ("MacroText date template hour offset", testMacroTextDateTemplateHourOffset),
    ("MacroText date template day offset", testMacroTextDateTemplateDayOffset),
    ("MacroText non-date braces", testMacroTextTemplateLeavesNonDateBracesUntouched),
    ("QuickTask default hotkey", testQuickTaskDefaultHotKey),
    ("QuickTask command line prefix", testQuickTaskCommandLinePrefix),
    ("MouseMacro command parser", testMouseMacroCommandParser),
    ("Bryan Tools update script resolver", testBryanToolsUpdateScriptResolver),
    ("Bryan Tools auto start defaults", testBryanToolsAutoStartDefaultsAndLaunchAgent),
    ("ShotFloat default hotkey", testShotFloatDefaultHotKey),
    ("Screen OCR default hotkey", testScreenOCRDefaultHotKey),
    ("TrayCal tool identifier", testTrayCalToolIdentifier),
    ("TrayCal status title", testTrayCalStatusTitleFormatting),
    ("TrayCal popup month name", testTrayCalPopupMonthNameFormatting),
    ("TrayCal May 2026 grid", testTrayCalMay2026MonthGrid),
    ("TrayCal payday schedule", testTrayCalPaydaySchedule),
    ("TrayCal today reset", testTrayCalTodayResetState),
    ("TrayCal popover close reset", testTrayCalPopoverResetAfterCloseThreshold),
    ("TrayCal month/year jump", testTrayCalMonthAndYearJumpState),
    ("UTC Hour tool identifier", testUTCHourToolIdentifier),
    ("UTC Hour status title", testUTCHourStatusTitleFormatting),
    ("UTC Hour Pacific lookup rows", testUTCHourPacificLookupRows),
    ("UTC Hour preference defaults", testUTCHourPreferenceDefaults),
    ("Disk Space display formatting", testDiskSpaceDisplayFormatting),
    ("Disk Space warning threshold", testDiskSpaceWarningThreshold),
    ("Disk Space preference defaults", testDiskSpacePreferencesDefaults),
    ("Disk Space visible history preferences", testDiskSpaceVisibleHistoryPreferences),
    ("Disk Space visible history filtering and selection", testDiskSpaceVisibleHistoryFilteringAndSelection),
    ("Disk Space sample store retention", testDiskSpaceSampleStoreRetention),
    ("Screen OCR text formatter", testScreenOCRTextFormatterSortsAndTrimsLines),
    ("Screen OCR text history capture", testClipboardHistoryTextRecorderCapturesRecognizedText),
    ("Screen OCR empty text ignore", testClipboardHistoryTextRecorderIgnoresEmptyText),
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
