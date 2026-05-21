import AppKit
import Carbon
import Foundation

public struct AppHotKey: Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let defaultValue = AppHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    public static let defaultPlainTextPasteValue = AppHotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey | optionKey)
    )
    public static let defaultColorPickerValue = AppHotKey(
        keyCode: UInt32(kVK_ANSI_Grave),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let defaultMacroTextValue = AppHotKey(
        keyCode: UInt32(kVK_ANSI_Slash),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let defaultQuickTaskValue = AppHotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey)
    )
    public static let defaultShotFloatValue = AppHotKey(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    public static let fallbackQuickTaskValue = AppHotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    public var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        parts.append(Self.keyName(for: keyCode, modifiers: modifiers))
        return parts.joined(separator: "-")
    }

    public var hasPrimaryModifier: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = modifiers
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        return modifiers
    }

    private static func keyName(for keyCode: UInt32, modifiers: UInt32 = 0) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Grave:
            return modifiers & UInt32(shiftKey) != 0 ? "~" : "`"
        case kVK_ANSI_Slash: return "/"
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Escape"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "Left Arrow"
        case kVK_RightArrow: return "Right Arrow"
        case kVK_UpArrow: return "Up Arrow"
        case kVK_DownArrow: return "Down Arrow"
        default: return "Key \(keyCode)"
        }
    }
}
