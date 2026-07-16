import BryanToolsShared
import Foundation

struct MouseMacroPreferences: Equatable {
    var mappings: [MouseMacroMapping]

    private enum Key {
        static let mappings = "mouseMacro.mappings"
    }

    static func load(defaults: UserDefaults = .standard) -> MouseMacroPreferences {
        if let data = defaults.data(forKey: Key.mappings),
           let mappings = try? JSONDecoder().decode([MouseMacroMapping].self, from: data) {
            return MouseMacroPreferences(mappings: mappings.sortedForDisplay())
        }

        return MouseMacroPreferences(mappings: [])
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(mappings.sortedForDisplay()) {
            defaults.set(data, forKey: Key.mappings)
        }
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
