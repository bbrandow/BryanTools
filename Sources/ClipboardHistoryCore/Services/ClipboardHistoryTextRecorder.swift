import AppKit
import Foundation

public enum ClipboardHistoryTextRecorder {
    @discardableResult
    public static func recordText(
        _ text: String,
        to pasteboard: NSPasteboard = .general,
        store: ClipStore,
        sourceApplication: NSRunningApplication? = NSRunningApplication.current
    ) throws -> ClipRecord? {
        guard !text.isEmpty else {
            return nil
        }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardHistoryError.pasteboard("Unable to write OCR text to the pasteboard.")
        }

        return try store.captureCurrentPasteboard(
            pasteboard,
            sourceApplication: sourceApplication
        )
    }
}
