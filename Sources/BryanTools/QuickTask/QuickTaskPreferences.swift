import BryanToolsShared
import Foundation

struct QuickTaskPreferences: Equatable {
    var hotKey: AppHotKey

    private enum Key {
        static let hotKeyCode = "quickTask.hotKeyCode"
        static let hotKeyModifiers = "quickTask.hotKeyModifiers"
    }

    static func load(defaults: UserDefaults = .standard) -> QuickTaskPreferences {
        let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int
            ?? Int(AppHotKey.defaultQuickTaskValue.keyCode)
        let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int
            ?? Int(AppHotKey.defaultQuickTaskValue.modifiers)
        return QuickTaskPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
    }
}
