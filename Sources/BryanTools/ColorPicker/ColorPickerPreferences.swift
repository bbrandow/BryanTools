import BryanToolsShared
import Foundation

struct ColorPickerPreferences: Equatable {
    var hotKey: AppHotKey
    var lastHexColor: String?

    private enum Key {
        static let hotKeyCode = "colorPicker.hotKeyCode"
        static let hotKeyModifiers = "colorPicker.hotKeyModifiers"
        static let lastHexColor = "colorPicker.lastHexColor"
    }

    static func load(defaults: UserDefaults = .standard) -> ColorPickerPreferences {
        let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int
            ?? Int(AppHotKey.defaultColorPickerValue.keyCode)
        let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int
            ?? Int(AppHotKey.defaultColorPickerValue.modifiers)

        return ColorPickerPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)),
            lastHexColor: defaults.string(forKey: Key.lastHexColor)
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
        defaults.set(lastHexColor, forKey: Key.lastHexColor)
    }
}
