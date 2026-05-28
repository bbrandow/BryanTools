import AppKit
import Carbon
import Foundation

public struct MouseMacroKeyCommand: Equatable {
    public let keyCode: UInt16
    public let flags: CGEventFlags

    public init(keyCode: UInt16, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

public enum MouseMacroCommandParser {
    public static func parse(_ input: String) -> [MouseMacroKeyCommand]? {
        let commandTexts = input
            .split { character in
                character == "," || character == ";" || character.isNewline
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !commandTexts.isEmpty else {
            return nil
        }

        var commands: [MouseMacroKeyCommand] = []
        for commandText in commandTexts {
            guard let command = parseSingleCommand(commandText) else {
                return nil
            }
            commands.append(command)
        }
        return commands
    }

    private static func parseSingleCommand(_ input: String) -> MouseMacroKeyCommand? {
        let parts = input
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return nil
        }

        var flags = CGEventFlags()
        var parsedKeyCode: UInt16?

        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            default:
                guard parsedKeyCode == nil,
                      let keyCode = keyCode(for: part) else {
                    return nil
                }
                parsedKeyCode = keyCode
            }
        }

        guard let parsedKeyCode else {
            return nil
        }
        return MouseMacroKeyCommand(keyCode: parsedKeyCode, flags: flags)
    }

    private static func keyCode(for token: String) -> UInt16? {
        if token.count == 1, let character = token.first {
            switch character {
            case "a": return UInt16(kVK_ANSI_A)
            case "b": return UInt16(kVK_ANSI_B)
            case "c": return UInt16(kVK_ANSI_C)
            case "d": return UInt16(kVK_ANSI_D)
            case "e": return UInt16(kVK_ANSI_E)
            case "f": return UInt16(kVK_ANSI_F)
            case "g": return UInt16(kVK_ANSI_G)
            case "h": return UInt16(kVK_ANSI_H)
            case "i": return UInt16(kVK_ANSI_I)
            case "j": return UInt16(kVK_ANSI_J)
            case "k": return UInt16(kVK_ANSI_K)
            case "l": return UInt16(kVK_ANSI_L)
            case "m": return UInt16(kVK_ANSI_M)
            case "n": return UInt16(kVK_ANSI_N)
            case "o": return UInt16(kVK_ANSI_O)
            case "p": return UInt16(kVK_ANSI_P)
            case "q": return UInt16(kVK_ANSI_Q)
            case "r": return UInt16(kVK_ANSI_R)
            case "s": return UInt16(kVK_ANSI_S)
            case "t": return UInt16(kVK_ANSI_T)
            case "u": return UInt16(kVK_ANSI_U)
            case "v": return UInt16(kVK_ANSI_V)
            case "w": return UInt16(kVK_ANSI_W)
            case "x": return UInt16(kVK_ANSI_X)
            case "y": return UInt16(kVK_ANSI_Y)
            case "z": return UInt16(kVK_ANSI_Z)
            case "0": return UInt16(kVK_ANSI_0)
            case "1": return UInt16(kVK_ANSI_1)
            case "2": return UInt16(kVK_ANSI_2)
            case "3": return UInt16(kVK_ANSI_3)
            case "4": return UInt16(kVK_ANSI_4)
            case "5": return UInt16(kVK_ANSI_5)
            case "6": return UInt16(kVK_ANSI_6)
            case "7": return UInt16(kVK_ANSI_7)
            case "8": return UInt16(kVK_ANSI_8)
            case "9": return UInt16(kVK_ANSI_9)
            case "`", "~": return UInt16(kVK_ANSI_Grave)
            case "/": return UInt16(kVK_ANSI_Slash)
            default: return nil
            }
        }

        switch token {
        case "space": return UInt16(kVK_Space)
        case "return", "enter": return UInt16(kVK_Return)
        case "tab": return UInt16(kVK_Tab)
        case "escape", "esc": return UInt16(kVK_Escape)
        case "delete", "backspace": return UInt16(kVK_Delete)
        case "forwarddelete": return UInt16(kVK_ForwardDelete)
        case "left": return UInt16(kVK_LeftArrow)
        case "right": return UInt16(kVK_RightArrow)
        case "up": return UInt16(kVK_UpArrow)
        case "down": return UInt16(kVK_DownArrow)
        case "f1": return UInt16(kVK_F1)
        case "f2": return UInt16(kVK_F2)
        case "f3": return UInt16(kVK_F3)
        case "f4": return UInt16(kVK_F4)
        case "f5": return UInt16(kVK_F5)
        case "f6": return UInt16(kVK_F6)
        case "f7": return UInt16(kVK_F7)
        case "f8": return UInt16(kVK_F8)
        case "f9": return UInt16(kVK_F9)
        case "f10": return UInt16(kVK_F10)
        case "f11": return UInt16(kVK_F11)
        case "f12": return UInt16(kVK_F12)
        case "f13": return UInt16(kVK_F13)
        case "f14": return UInt16(kVK_F14)
        case "f15": return UInt16(kVK_F15)
        case "f16": return UInt16(kVK_F16)
        case "f17": return UInt16(kVK_F17)
        case "f18": return UInt16(kVK_F18)
        case "f19": return UInt16(kVK_F19)
        case "f20": return UInt16(kVK_F20)
        default: return nil
        }
    }
}
