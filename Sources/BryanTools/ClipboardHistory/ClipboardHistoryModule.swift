import AppKit
import BryanToolsShared
import ClipboardHistoryCore
import Foundation
import SwiftUI

@MainActor
final class ClipboardHistoryModule: ObservableObject, ToolModule {
    static let shared = ClipboardHistoryModule.makeShared()

    let id = ToolIdentifier.clipboardHistory
    let displayName = ToolIdentifier.clipboardHistory.displayName
    let systemImage = "square.stack"

    @Published var searchQuery = "" {
        didSet {
            refreshSearch()
        }
    }

    @Published var searchResults: [ClipRecord] = []
    @Published var capturePaused = false {
        didSet {
            monitor?.isPaused = capturePaused
        }
    }
    @Published private(set) var hotKey: AppHotKey
    @Published private(set) var plainTextPasteHotKey: AppHotKey
    @Published private(set) var retentionDays: Int
    @Published private(set) var storagePath: String
    @Published private(set) var focusRequestID = 0
    @Published var lastErrorMessage: String?

    @Published private(set) var store: ClipStore

    private enum HotKeyID {
        static let openHistory: HotKeyController.Identifier = 1
        static let pastePlainText: HotKeyController.Identifier = 2
    }

    private let hotKeyController = HotKeyController()
    private var preferences: ClipboardHistoryPreferences
    private var monitor: PasteboardMonitor?
    private var isRunning = false
    private var appToRestoreFocus: NSRunningApplication?
    private var searchClearWorkItem: DispatchWorkItem?
    private var searchClearToken: UUID?
    private var thumbnailImageCache: [UUID: NSImage] = [:]
    private var thumbnailMisses = Set<UUID>()

    private lazy var historyPanelController = HistoryPanelController(environment: self)

    private init(preferences: ClipboardHistoryPreferences, store: ClipStore) {
        self.preferences = preferences
        self.store = store
        self.hotKey = preferences.hotKey
        self.plainTextPasteHotKey = preferences.plainTextPasteHotKey
        self.retentionDays = preferences.retentionDays
        self.storagePath = preferences.storagePath
    }

    func start() {
        do {
            isRunning = true
            try store.purgeExpired()
            refreshSearch()
            startMonitor()
            try registerHotKey()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func stop() {
        isRunning = false
        monitor?.stop()
        monitor = nil
        hotKeyController.unregisterAll()
    }

    func showHistory() {
        cancelDeferredSearchClear()
        rememberAppForFocusRestore()
        refreshSearch()
        historyPanelController.show()
        requestSearchFocus()
    }

    func closeHistory() {
        historyPanelController.close()
        historyPanelDidClose()
    }

    func historyPanelDidClose() {
        scheduleDeferredSearchClear()
        restorePreviousAppFocus()
    }

    func cancelDeferredSearchClear() {
        searchClearWorkItem?.cancel()
        searchClearWorkItem = nil
        searchClearToken = nil
    }

    private func requestSearchFocus() {
        focusRequestID += 1
    }

    func menuContent() -> AnyView {
        AnyView(ClipboardHistoryMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(ClipboardHistorySettingsView(environment: self))
    }

    func updateHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }
        guard newHotKey != plainTextPasteHotKey else {
            lastErrorMessage = "Open Clipboard History and Paste Plain Text shortcuts must be different."
            return
        }

        let previousHotKey = hotKey
        do {
            if isRunning {
                try hotKeyController.register(newHotKey, identifier: HotKeyID.openHistory) { [weak self] in
                    self?.showHistory()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.openHistory) { [weak self] in
                    self?.showHistory()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultValue)
    }

    func updatePlainTextPasteHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }
        guard newHotKey != hotKey else {
            lastErrorMessage = "Paste Plain Text and Open Clipboard History shortcuts must be different."
            return
        }

        let previousHotKey = plainTextPasteHotKey
        do {
            if isRunning {
                try hotKeyController.register(
                    newHotKey,
                    identifier: HotKeyID.pastePlainText,
                    trigger: .released
                ) { [weak self] in
                    self?.pasteClipboardAsPlainText()
                }
            }
            plainTextPasteHotKey = newHotKey
            preferences.plainTextPasteHotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(
                    previousHotKey,
                    identifier: HotKeyID.pastePlainText,
                    trigger: .released
                ) { [weak self] in
                    self?.pasteClipboardAsPlainText()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetPlainTextPasteHotKey() {
        updatePlainTextPasteHotKey(.defaultPlainTextPasteValue)
    }

    func updateRetentionDays(_ days: Int) {
        let clampedDays = ClipboardHistoryPreferences.clampedRetentionDays(days)
        guard clampedDays != retentionDays else {
            return
        }

        do {
            let newStore = try makeStore(storagePath: storagePath, retentionDays: clampedDays)
            try replaceStore(newStore)
            retentionDays = clampedDays
            preferences.retentionDays = clampedDays
            preferences.save()
            try store.purgeExpired()
            refreshSearch()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Clipboard History Storage Location"
        panel.message = "Choose the folder where Bryan Tools should store clipboard history."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: storagePath, isDirectory: true)

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        updateStorageLocation(url)
    }

    func resetStorageLocation() {
        do {
            updateStorageLocation(try ClipStore.defaultRootDirectory())
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateStorageLocation(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        do {
            let newStore = try makeStore(storagePath: standardizedURL.path, retentionDays: retentionDays)
            try replaceStore(newStore)
            storagePath = standardizedURL.path
            preferences.storagePath = standardizedURL.path
            preferences.save()
            refreshSearch()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copyToClipboard(_ record: ClipRecord) {
        do {
            try store.restoreClip(id: record.id, to: .general)
            monitor?.noteInternalPasteboardWrite()
            closeHistory()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func pasteClipboardAsPlainText() {
        guard PlainTextPasteService.ensureAccessibilityPermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Accessibility permission for Bryan Tools to paste plain text automatically."
            return
        }

        let originalItems = PlainTextPasteService.snapshotItems(from: .general)
        var plainTextChangeCount = NSPasteboard.general.changeCount
        let writePlainText = {
            let plainText = PlainTextPasteService.writePlainTextToClipboard(from: .general)
            plainTextChangeCount = NSPasteboard.general.changeCount
            return plainText
        }
        let plainText: String?
        if let monitor = monitor {
            plainText = monitor.performIgnoringPasteboardChanges(writePlainText)
        } else {
            plainText = writePlainText()
        }

        guard plainText != nil else {
            lastErrorMessage = "Clipboard does not contain text to paste as plain text."
            return
        }

        switch PlainTextPasteService.postPasteCommandAfterKeyRelease() {
        case .pasted:
            lastErrorMessage = nil
        case .noText:
            lastErrorMessage = "Clipboard does not contain text to paste as plain text."
        case .copiedOnlyAccessibilityMissing:
            lastErrorMessage = "Plain text copied. Enable Accessibility permission for Bryan Tools to paste automatically."
        }

        restoreOriginalClipboardAfterPlainTextPaste(originalItems, plainTextChangeCount: plainTextChangeCount)
    }

    func delete(_ record: ClipRecord) {
        do {
            try store.deleteClip(id: record.id)
            thumbnailImageCache.removeValue(forKey: record.id)
            thumbnailMisses.remove(record.id)
            refreshSearch()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearHistory() {
        do {
            try store.clearHistory()
            thumbnailImageCache.removeAll()
            thumbnailMisses.removeAll()
            refreshSearch()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addImageToHistory(_ image: NSImage) {
        guard let pngData = pngData(from: image) else {
            lastErrorMessage = "Unable to encode ShotFloat image for Clipboard History."
            return
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BryanToolsShotFloat-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(pngData, forType: NSPasteboard.PasteboardType("public.png"))
        guard pasteboard.writeObjects([item]) else {
            lastErrorMessage = "Unable to add ShotFloat image to Clipboard History."
            return
        }

        do {
            _ = try store.captureCurrentPasteboard(
                pasteboard,
                sourceApplication: NSRunningApplication.current
            )
            refreshSearch()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copyTextToClipboardAndHistory(_ text: String) throws {
        let recordText = {
            try ClipboardHistoryTextRecorder.recordText(
                text,
                to: .general,
                store: self.store,
                sourceApplication: NSRunningApplication.current
            )
        }

        if let monitor {
            _ = try monitor.performIgnoringPasteboardChanges(recordText)
        } else {
            _ = try recordText()
        }

        refreshSearch()
        lastErrorMessage = nil
    }

    func refreshSearch() {
        do {
            searchResults = try store.search(searchQuery)
            pruneThumbnailCache(to: searchResults)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func thumbnailImage(for record: ClipRecord) -> NSImage? {
        if let cachedImage = thumbnailImageCache[record.id] {
            return cachedImage
        }
        if thumbnailMisses.contains(record.id) {
            return nil
        }

        do {
            if let image = try store.thumbnailImage(for: record) {
                thumbnailImageCache[record.id] = image
                return image
            }
            thumbnailMisses.insert(record.id)
            return nil
        } catch {
            lastErrorMessage = error.localizedDescription
            thumbnailMisses.insert(record.id)
            return nil
        }
    }

    func canFloatImage(_ record: ClipRecord) -> Bool {
        record.thumbnailPath != nil
    }

    func floatImage(_ record: ClipRecord) {
        guard canFloatImage(record) else {
            return
        }

        do {
            guard let image = try store.image(for: record) else {
                lastErrorMessage = "Unable to load selected image for ShotFloat."
                return
            }
            ShotFloatModule.shared.floatImage(image)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func registerHotKey() throws {
        try hotKeyController.register(hotKey, identifier: HotKeyID.openHistory) { [weak self] in
            self?.showHistory()
        }
        do {
            try hotKeyController.register(
                plainTextPasteHotKey,
                identifier: HotKeyID.pastePlainText,
                trigger: .released
            ) { [weak self] in
                self?.pasteClipboardAsPlainText()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func restoreOriginalClipboardAfterPlainTextPaste(
        _ originalItems: [NSPasteboardItem],
        plainTextChangeCount: Int
    ) {
        guard !originalItems.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard NSPasteboard.general.changeCount == plainTextChangeCount else {
                return
            }

            if let monitor = self?.monitor {
                monitor.performIgnoringPasteboardChanges {
                    PlainTextPasteService.restoreItems(originalItems, to: .general)
                }
            } else {
                PlainTextPasteService.restoreItems(originalItems, to: .general)
            }
        }
    }

    private func startMonitor() {
        monitor?.stop()
        let newMonitor = PasteboardMonitor(
            store: store,
            onCapture: { [weak self] _ in
                self?.refreshSearch()
            },
            onError: { [weak self] error in
                self?.lastErrorMessage = error.localizedDescription
            }
        )
        newMonitor.isPaused = capturePaused
        newMonitor.start()
        monitor = newMonitor
    }

    private func replaceStore(_ newStore: ClipStore) throws {
        let shouldRestartMonitor = isRunning
        monitor?.stop()
        monitor = nil
        store = newStore
        thumbnailImageCache.removeAll()
        thumbnailMisses.removeAll()
        if shouldRestartMonitor {
            startMonitor()
        }
    }

    private func makeStore(storagePath: String, retentionDays: Int) throws -> ClipStore {
        try ClipStore(
            rootDirectory: URL(fileURLWithPath: storagePath, isDirectory: true),
            retentionDays: retentionDays
        )
    }

    private func rememberAppForFocusRestore() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        appToRestoreFocus = frontmostApp
    }

    private func restorePreviousAppFocus() {
        guard let app = appToRestoreFocus,
              !app.isTerminated else {
            appToRestoreFocus = nil
            return
        }

        appToRestoreFocus = nil
        DispatchQueue.main.async {
            app.activate(options: [])
        }
    }

    private static func makeShared() -> ClipboardHistoryModule {
        do {
            _ = try ClipboardHistoryMigration.migrateClipManDataIfNeeded()
            let preferences = try ClipboardHistoryPreferences.load()
            let store = try ClipStore(
                rootDirectory: URL(fileURLWithPath: preferences.storagePath, isDirectory: true),
                retentionDays: preferences.retentionDays
            )
            return ClipboardHistoryModule(preferences: preferences, store: store)
        } catch {
            fatalError("Unable to initialize Clipboard History: \(error.localizedDescription)")
        }
    }

    private func scheduleDeferredSearchClear() {
        searchClearWorkItem?.cancel()
        let token = UUID()
        searchClearToken = token
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.searchClearToken == token else {
                    return
                }
                self.searchQuery = ""
                self.searchClearWorkItem = nil
                self.searchClearToken = nil
            }
        }
        searchClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: workItem)
    }

    private func pruneThumbnailCache(to records: [ClipRecord]) {
        let ids = Set(records.map(\.id))
        thumbnailImageCache = thumbnailImageCache.filter { ids.contains($0.key) }
        thumbnailMisses = thumbnailMisses.intersection(ids)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
