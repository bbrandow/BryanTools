import AppKit
import BryanToolsShared
import Carbon
import CoreGraphics
import Foundation

@MainActor
enum MacroTextTextInjector {
    static func replaceTypedCommand(commandLength: Int, with replacement: String) {
        guard commandLength > 0, !replacement.isEmpty else {
            return
        }

        let originalItems = snapshotItems(from: .general)
        for _ in 0..<commandLength {
            postKey(CGKeyCode(kVK_Delete), flags: [])
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(replacement, forType: .string)
        let replacementChangeCount = NSPasteboard.general.changeCount
        PasteboardChangeSuppressor.suppress(changeCount: replacementChangeCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        }

        restoreOriginalClipboardIfUnchanged(originalItems, replacementChangeCount: replacementChangeCount)
    }

    private static func restoreOriginalClipboardIfUnchanged(
        _ originalItems: [NSPasteboardItem],
        replacementChangeCount: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard NSPasteboard.general.changeCount == replacementChangeCount else {
                return
            }
            NSPasteboard.general.clearContents()
            if !originalItems.isEmpty {
                NSPasteboard.general.writeObjects(originalItems)
            }
            PasteboardChangeSuppressor.suppress()
        }
    }

    private static func snapshotItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map(copyPasteboardItem(_:)) ?? []
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

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
