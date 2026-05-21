import BryanToolsShared
import Foundation

struct ShotFloatPreferences: Equatable {
    var hotKey: AppHotKey

    private enum Key {
        static let hotKeyCode = "shotFloat.hotKeyCode"
        static let hotKeyModifiers = "shotFloat.hotKeyModifiers"
    }

    static func load(defaults: UserDefaults = .standard) -> ShotFloatPreferences {
        let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int
            ?? Int(AppHotKey.defaultShotFloatValue.keyCode)
        let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int
            ?? Int(AppHotKey.defaultShotFloatValue.modifiers)
        return ShotFloatPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
    }
}
