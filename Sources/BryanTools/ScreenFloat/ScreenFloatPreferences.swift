import BryanToolsShared
import Foundation

struct ScreenFloatPreferences: Equatable {
    var hotKey: AppHotKey

    private enum Key {
        static let hotKeyCode = "screenFloat.hotKeyCode"
        static let hotKeyModifiers = "screenFloat.hotKeyModifiers"
    }

    static func load(defaults: UserDefaults = .standard) -> ScreenFloatPreferences {
        let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int
            ?? Int(AppHotKey.defaultScreenFloatValue.keyCode)
        let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int
            ?? Int(AppHotKey.defaultScreenFloatValue.modifiers)
        return ScreenFloatPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
    }
}
