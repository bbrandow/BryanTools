import AppKit
import BryanToolsShared
import Carbon
import ClipboardHistoryCore
import CoreGraphics
import Foundation

enum PlainTextPasteResult {
    case pasted
    case noText
    case copiedOnlyAccessibilityMissing
}

enum PlainTextPasteService {
    static func ensureAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        AccessibilityPermissionService.ensurePermission(promptIfNeeded: promptIfNeeded)
    }

    static func snapshotItems(from pasteboard: NSPasteboard = .general) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map(copyPasteboardItem(_:)) ?? []
    }

    static func writePlainTextToClipboard(from pasteboard: NSPasteboard = .general) -> String? {
        guard let plainText = PasteboardPlainTextExtractor.plainText(from: pasteboard),
              !plainText.isEmpty else {
            return nil
        }

        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
        return plainText
    }

    static func restoreItems(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    static func postPasteCommandAfterKeyRelease() -> PlainTextPasteResult {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCommandV()
        }
        return .pasted
    }

    private static func copyPasteboardItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) {
                copy.setData(data, forType: type)
            } else if let string = item.string(forType: type) {
                copy.setString(string, forType: type)
            }
        }
        return copy
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
