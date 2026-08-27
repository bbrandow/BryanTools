import AppKit
import Foundation

public enum PasteboardPlainTextExtractor {
    public static func plainText(from pasteboard: NSPasteboard) -> String? {
        guard let items = pasteboard.pasteboardItems else {
            return nil
        }
        return plainText(from: items)
    }

    public static func plainText(from items: [NSPasteboardItem]) -> String? {
        let textValues = items.compactMap(plainText(from:))
        guard !textValues.isEmpty else {
            return nil
        }
        return textValues.joined(separator: "\n")
    }

    private static func plainText(from item: NSPasteboardItem) -> String? {
        if let string = item.string(forType: .string), !string.isEmpty {
            return string
        }

        for type in item.types {
            let normalized = type.rawValue.lowercased()
            guard let data = item.data(forType: type) else {
                continue
            }

            if normalized.contains("html"),
               let string = SafeHTMLTextExtractor.plainText(from: data) {
                return string
            }
            if normalized.contains("rtf"),
               let string = rtfString(from: data) {
                return string
            }
            if normalized.contains("plain-text") || normalized.contains("utf8-plain-text"),
               let string = String(data: data, encoding: .utf8),
               !string.isEmpty {
                return string
            }
        }

        return nil
    }

    private static func rtfString(from data: Data) -> String? {
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let string = attributed?.string
        return string?.isEmpty == false ? string : nil
    }
}
