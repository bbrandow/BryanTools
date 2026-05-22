import BryanToolsShared
import Foundation

struct ScreenOCRPreferences: Equatable {
    var hotKey: AppHotKey

    static func load(defaults: UserDefaults = .standard) -> ScreenOCRPreferences {
        let keyCode = UInt32(
            defaults.object(forKey: "screenOCR.hotKey.keyCode") as? Int
                ?? Int(AppHotKey.defaultScreenOCRValue.keyCode)
        )
        let modifiers = UInt32(
            defaults.object(forKey: "screenOCR.hotKey.modifiers") as? Int
                ?? Int(AppHotKey.defaultScreenOCRValue.modifiers)
        )
        return ScreenOCRPreferences(hotKey: AppHotKey(keyCode: keyCode, modifiers: modifiers))
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: "screenOCR.hotKey.keyCode")
        defaults.set(Int(hotKey.modifiers), forKey: "screenOCR.hotKey.modifiers")
    }
}
