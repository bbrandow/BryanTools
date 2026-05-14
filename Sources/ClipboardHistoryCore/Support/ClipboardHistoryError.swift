import Foundation

public enum ClipboardHistoryError: Error, LocalizedError {
    case database(String)
    case storage(String)
    case pasteboard(String)
    case notFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .database(let message):
            return "Database error: \(message)"
        case .storage(let message):
            return "Storage error: \(message)"
        case .pasteboard(let message):
            return "Pasteboard error: \(message)"
        case .notFound(let id):
            return "Clip not found: \(id.uuidString)"
        }
    }
}
