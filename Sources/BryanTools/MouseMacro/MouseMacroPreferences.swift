import Foundation

struct MouseMacroPreferences: Equatable {
    var mappings: [MouseMacroMapping]

    private enum Key {
        static let mappings = "mouseMacro.mappings"
        static let legacyMappedButtonNumber = "mouseMacro.mappedButtonNumber"
        static let legacyMacroText = "mouseMacro.macroText"
    }

    static func load(defaults: UserDefaults = .standard) -> MouseMacroPreferences {
        if let data = defaults.data(forKey: Key.mappings),
           let mappings = try? JSONDecoder().decode([MouseMacroMapping].self, from: data) {
            return MouseMacroPreferences(mappings: mappings.sortedForDisplay())
        }

        if let legacyButtonNumber = defaults.object(forKey: Key.legacyMappedButtonNumber) as? Int64 {
            let legacyMacroText = defaults.string(forKey: Key.legacyMacroText) ?? Self.defaultMacroText
            return MouseMacroPreferences(mappings: [
                MouseMacroMapping(buttonNumber: legacyButtonNumber, macroText: legacyMacroText)
            ])
        }

        return MouseMacroPreferences(mappings: [])
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(mappings.sortedForDisplay()) {
            defaults.set(data, forKey: Key.mappings)
        }
        defaults.removeObject(forKey: Key.legacyMappedButtonNumber)
        defaults.removeObject(forKey: Key.legacyMacroText)
    }

    static let defaultMacroText = "cmd+shift+ctrl+4"
}

private extension Array where Element == MouseMacroMapping {
    func sortedForDisplay() -> [MouseMacroMapping] {
        sorted {
            if $0.buttonNumber != $1.buttonNumber {
                return $0.buttonNumber < $1.buttonNumber
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
