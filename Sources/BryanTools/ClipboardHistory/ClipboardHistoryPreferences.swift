import BryanToolsShared
import ClipboardHistoryCore
import Foundation

struct ClipboardHistoryPreferences: Equatable {
    var hotKey: AppHotKey
    var plainTextPasteHotKey: AppHotKey
    var retentionDays: Int
    var storagePath: String

    static let minimumRetentionDays = 1
    static let maximumRetentionDays = 3650

    private enum Key {
        static let hotKeyCode = "clipboardHistory.hotKeyCode"
        static let hotKeyModifiers = "clipboardHistory.hotKeyModifiers"
        static let plainTextPasteHotKeyCode = "clipboardHistory.plainTextPasteHotKeyCode"
        static let plainTextPasteHotKeyModifiers = "clipboardHistory.plainTextPasteHotKeyModifiers"
        static let retentionDays = "clipboardHistory.retentionDays"
        static let storagePath = "clipboardHistory.storagePath"
    }

    static func load(defaults: UserDefaults = .standard) throws -> ClipboardHistoryPreferences {
        let legacyDefaults = UserDefaults(suiteName: "com.local.ClipMan")
        let defaultPath = try ClipStore.defaultRootDirectory().path
        let keyCode = intValue(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Key.hotKeyCode,
            legacyKey: "hotKeyCode",
            defaultValue: Int(AppHotKey.defaultValue.keyCode)
        )
        let modifiers = intValue(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Key.hotKeyModifiers,
            legacyKey: "hotKeyModifiers",
            defaultValue: Int(AppHotKey.defaultValue.modifiers)
        )
        let plainTextPasteKeyCode = intValue(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Key.plainTextPasteHotKeyCode,
            legacyKey: "plainTextPasteHotKeyCode",
            defaultValue: Int(AppHotKey.defaultPlainTextPasteValue.keyCode)
        )
        let plainTextPasteModifiers = intValue(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Key.plainTextPasteHotKeyModifiers,
            legacyKey: "plainTextPasteHotKeyModifiers",
            defaultValue: Int(AppHotKey.defaultPlainTextPasteValue.modifiers)
        )
        let retentionDays = intValue(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            key: Key.retentionDays,
            legacyKey: "retentionDays",
            defaultValue: ClipStore.defaultRetentionDays
        )
        let storagePath = defaults.string(forKey: Key.storagePath) ?? defaultPath

        return ClipboardHistoryPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)),
            plainTextPasteHotKey: AppHotKey(
                keyCode: UInt32(plainTextPasteKeyCode),
                modifiers: UInt32(plainTextPasteModifiers)
            ),
            retentionDays: Self.clampedRetentionDays(retentionDays),
            storagePath: storagePath
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
        defaults.set(Int(plainTextPasteHotKey.keyCode), forKey: Key.plainTextPasteHotKeyCode)
        defaults.set(Int(plainTextPasteHotKey.modifiers), forKey: Key.plainTextPasteHotKeyModifiers)
        defaults.set(retentionDays, forKey: Key.retentionDays)
        defaults.set(storagePath, forKey: Key.storagePath)
    }

    static func clampedRetentionDays(_ days: Int) -> Int {
        min(max(days, minimumRetentionDays), maximumRetentionDays)
    }

    private static func intValue(
        defaults: UserDefaults,
        legacyDefaults: UserDefaults?,
        key: String,
        legacyKey: String,
        defaultValue: Int
    ) -> Int {
        if let value = defaults.object(forKey: key) as? Int {
            return value
        }
        if let value = legacyDefaults?.object(forKey: legacyKey) as? Int {
            return value
        }
        return defaultValue
    }
}
