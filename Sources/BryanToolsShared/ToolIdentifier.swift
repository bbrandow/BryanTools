import Foundation

public enum ToolIdentifier: String, CaseIterable, Codable, Identifiable {
    case clipboardHistory
    case colorPicker
    case macroText
    case logiShot
    case quickTask
    case shotFloat

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .clipboardHistory:
            return "Clipboard History"
        case .colorPicker:
            return "ColorPicker"
        case .macroText:
            return "MacroText"
        case .logiShot:
            return "LogiShot"
        case .quickTask:
            return "QuickTask"
        case .shotFloat:
            return "ShotFloat"
        }
    }

    public var storageDirectoryName: String {
        displayName
    }
}
