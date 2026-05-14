import Foundation

public enum BryanToolsError: Error, LocalizedError {
    case hotKey(String)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .hotKey(let message):
            return "Hotkey error: \(message)"
        case .storage(let message):
            return "Storage error: \(message)"
        }
    }
}
