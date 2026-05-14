import BryanToolsShared
import Foundation

struct MacroTextPreferences: Equatable {
    var hotKey: AppHotKey
    var replacements: [MacroTextReplacement]

    private enum Key {
        static let hotKeyCode = "macroText.hotKeyCode"
        static let hotKeyModifiers = "macroText.hotKeyModifiers"
        static let replacements = "macroText.replacements"
    }

    static func load(defaults: UserDefaults = .standard) -> MacroTextPreferences {
        let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int
            ?? Int(AppHotKey.defaultMacroTextValue.keyCode)
        let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int
            ?? Int(AppHotKey.defaultMacroTextValue.modifiers)
        let replacements = loadReplacements(defaults: defaults)

        return MacroTextPreferences(
            hotKey: AppHotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)),
            replacements: replacements
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
        if let data = try? JSONEncoder().encode(replacements) {
            defaults.set(data, forKey: Key.replacements)
        }
    }

    private static func loadReplacements(defaults: UserDefaults) -> [MacroTextReplacement] {
        guard let data = defaults.data(forKey: Key.replacements),
              let replacements = try? JSONDecoder().decode([MacroTextReplacement].self, from: data) else {
            return []
        }
        return replacements.sorted { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
    }
}
