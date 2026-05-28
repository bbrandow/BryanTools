import Foundation

public enum ToolIdentifier: String, CaseIterable, Codable, Identifiable {
    case clipboardHistory
    case colorPicker
    case macroText
    case mouseMacro
    case quickTask
    case shotFloat
    case screenOCR
    case trayCal
    case diskSpaceMonitor

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
        case .mouseMacro:
            return "MouseMacro"
        case .quickTask:
            return "QuickTask"
        case .shotFloat:
            return "ShotFloat"
        case .screenOCR:
            return "Screen OCR"
        case .trayCal:
            return "TrayCal"
        case .diskSpaceMonitor:
            return "Disk Space Monitor"
        }
    }

    public var storageDirectoryName: String {
        displayName
    }
}
