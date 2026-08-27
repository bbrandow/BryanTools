import Foundation

public enum SafeHTMLTextExtractor {
    private static let suppressedTags: Set<String> = [
        "head", "noscript", "script", "style", "svg", "template"
    ]

    private static let lineBreakTags: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "dd", "div", "dl", "dt",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table",
        "tbody", "tfoot", "thead", "tr", "ul"
    ]

    private static let spacingTags: Set<String> = ["td", "th"]

    public static func plainText(from data: Data) -> String? {
        guard let html = decodeHTML(data) else {
            return nil
        }
        return plainText(from: html)
    }

    public static func plainText(from html: String) -> String? {
        let bytes = Array(html.utf8)
        guard !bytes.isEmpty else {
            return nil
        }

        var output: [UInt8] = []
        output.reserveCapacity(min(bytes.count, 64 * 1_024))
        var index = 0

        while index < bytes.count {
            if bytes[index] == ascii("<"), looksLikeTag(bytes, at: index) {
                if startsWith(bytes, ascii: "<!--", at: index) {
                    index = indexAfter(bytes, ascii: "-->", from: index + 4) ?? bytes.count
                    continue
                }

                guard let openingTagEnd = tagEnd(in: bytes, from: index + 1) else {
                    output.append(bytes[index])
                    index += 1
                    continue
                }

                let tag = parseTag(bytes[(index + 1)..<openingTagEnd])
                index = openingTagEnd + 1
                guard let tag else {
                    continue
                }

                if !tag.isClosing, suppressedTags.contains(tag.name) {
                    let closingPrefix = "</\(tag.name)"
                    guard let closingStart = firstASCIICaseInsensitiveMatch(
                        in: bytes,
                        ascii: closingPrefix,
                        from: index
                    ),
                    let closingEnd = tagEnd(in: bytes, from: closingStart + closingPrefix.utf8.count) else {
                        break
                    }
                    index = closingEnd + 1
                    appendSeparator(to: &output, byte: ascii("\n"))
                    continue
                }

                if lineBreakTags.contains(tag.name) {
                    appendSeparator(to: &output, byte: ascii("\n"))
                } else if spacingTags.contains(tag.name) {
                    appendSeparator(to: &output, byte: ascii(" "))
                }
                continue
            }

            if bytes[index] == ascii("&"),
               let entityEnd = entityEnd(in: bytes, from: index + 1),
               let decoded = decodeEntity(bytes[(index + 1)..<entityEnd]) {
                output.append(contentsOf: decoded.utf8)
                index = entityEnd + 1
                continue
            }

            output.append(bytes[index])
            index += 1
        }

        let text = normalizeWhitespace(String(decoding: output, as: UTF8.self))
        return text.isEmpty ? nil : text
    }

    private static func decodeHTML(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252,
            .isoLatin1
        ]
        return encodings.lazy.compactMap { String(data: data, encoding: $0) }.first
    }

    private static func looksLikeTag(_ bytes: [UInt8], at index: Int) -> Bool {
        var cursor = index + 1
        while cursor < bytes.count, isASCIISpace(bytes[cursor]) {
            cursor += 1
        }
        guard cursor < bytes.count else {
            return false
        }
        let byte = bytes[cursor]
        return byte == ascii("/") || byte == ascii("!") || byte == ascii("?") || isASCIILetter(byte)
    }

    private static func tagEnd(in bytes: [UInt8], from start: Int) -> Int? {
        var quote: UInt8?
        var cursor = start
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if let currentQuote = quote {
                if byte == currentQuote {
                    quote = nil
                }
            } else if byte == ascii("\"") || byte == ascii("'") {
                quote = byte
            } else if byte == ascii(">") {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func parseTag(_ bytes: ArraySlice<UInt8>) -> (name: String, isClosing: Bool)? {
        var cursor = bytes.startIndex
        while cursor < bytes.endIndex, isASCIISpace(bytes[cursor]) {
            cursor += 1
        }
        guard cursor < bytes.endIndex else {
            return nil
        }

        let isClosing = bytes[cursor] == ascii("/")
        if isClosing {
            cursor += 1
        }
        while cursor < bytes.endIndex, isASCIISpace(bytes[cursor]) {
            cursor += 1
        }

        let nameStart = cursor
        while cursor < bytes.endIndex, isTagNameByte(bytes[cursor]) {
            cursor += 1
        }
        guard cursor > nameStart else {
            return nil
        }

        let nameBytes = bytes[nameStart..<cursor].map(asciiLowercased)
        return (String(decoding: nameBytes, as: UTF8.self), isClosing)
    }

    private static func entityEnd(in bytes: [UInt8], from start: Int) -> Int? {
        let maximumLength = 32
        let upperBound = min(bytes.count, start + maximumLength)
        var cursor = start
        while cursor < upperBound {
            let byte = bytes[cursor]
            if byte == ascii(";") {
                return cursor
            }
            guard isASCIIAlphaNumeric(byte) || byte == ascii("#") else {
                return nil
            }
            cursor += 1
        }
        return nil
    }

    private static func decodeEntity(_ bytes: ArraySlice<UInt8>) -> String? {
        let value = String(decoding: bytes, as: UTF8.self)
        if value.hasPrefix("#x") || value.hasPrefix("#X") {
            return unicodeScalar(from: String(value.dropFirst(2)), radix: 16)
        }
        if value.hasPrefix("#") {
            return unicodeScalar(from: String(value.dropFirst()), radix: 10)
        }

        switch value.lowercased() {
        case "amp": return "&"
        case "apos": return "'"
        case "copy": return "(c)"
        case "emsp", "ensp", "nbsp", "thinsp": return " "
        case "gt": return ">"
        case "hellip": return "..."
        case "lt": return "<"
        case "mdash": return "-"
        case "ndash": return "-"
        case "quot": return "\""
        case "reg": return "(R)"
        case "trade": return "(TM)"
        default: return nil
        }
    }

    private static func unicodeScalar(from value: String, radix: Int) -> String? {
        guard let scalarValue = UInt32(value, radix: radix),
              let scalar = UnicodeScalar(scalarValue),
              !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\t" else {
            return nil
        }
        return String(scalar)
    }

    private static func normalizeWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map {
                $0.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendSeparator(to output: inout [UInt8], byte: UInt8) {
        guard let last = output.last, last != byte else {
            return
        }
        if byte == ascii("\n"), last == ascii(" ") {
            output.removeLast()
        }
        output.append(byte)
    }

    private static func firstASCIICaseInsensitiveMatch(
        in bytes: [UInt8],
        ascii value: String,
        from start: Int
    ) -> Int? {
        let needle = value.utf8.map(asciiLowercased)
        guard !needle.isEmpty, start <= bytes.count - needle.count else {
            return nil
        }
        for offset in start...(bytes.count - needle.count) {
            var matches = true
            for needleIndex in needle.indices where asciiLowercased(bytes[offset + needleIndex]) != needle[needleIndex] {
                matches = false
                break
            }
            if matches {
                return offset
            }
        }
        return nil
    }

    private static func startsWith(_ bytes: [UInt8], ascii value: String, at index: Int) -> Bool {
        let needle = Array(value.utf8)
        guard index <= bytes.count - needle.count else {
            return false
        }
        return bytes[index..<(index + needle.count)].elementsEqual(needle)
    }

    private static func indexAfter(_ bytes: [UInt8], ascii value: String, from start: Int) -> Int? {
        let needle = Array(value.utf8)
        guard !needle.isEmpty, start <= bytes.count - needle.count else {
            return nil
        }
        for offset in start...(bytes.count - needle.count) where bytes[offset..<(offset + needle.count)].elementsEqual(needle) {
            return offset + needle.count
        }
        return nil
    }

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue!
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    private static func isASCIISpace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIILetter(byte) || (48...57).contains(byte)
    }

    private static func isTagNameByte(_ byte: UInt8) -> Bool {
        isASCIIAlphaNumeric(byte) || byte == ascii("-") || byte == ascii(":")
    }
}
