import Foundation

public enum MacroTextTemplateRenderer {
    public static func render(
        _ template: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var result = ""
        var index = template.startIndex

        while index < template.endIndex {
            if template[index] == "{",
               let closeIndex = template[index...].firstIndex(of: "}") {
                let contentStart = template.index(after: index)
                let content = String(template[contentStart..<closeIndex])

                if let rendered = renderDateToken(
                    content,
                    now: now,
                    calendar: calendar,
                    timeZone: timeZone
                ) {
                    result.append(rendered)
                    index = template.index(after: closeIndex)
                    continue
                }
            }

            result.append(template[index])
            index = template.index(after: index)
        }

        return result
    }

    private static func renderDateToken(
        _ content: String,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String? {
        guard contentContainsDateField(content) else {
            return nil
        }

        let parsed = parseTrailingOffset(from: content)
        let format = parsed.format
        guard !format.isEmpty else {
            return nil
        }

        var calendar = calendar
        calendar.timeZone = timeZone

        let date: Date
        if let offset = parsed.offset {
            guard let adjustedDate = calendar.date(byAdding: offset, to: now) else {
                return nil
            }
            date = adjustedDate
        } else {
            date = now
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = normalizedDateFormat(format)
        return formatter.string(from: date)
    }

    private static func parseTrailingOffset(from content: String) -> (format: String, offset: DateComponents?) {
        guard let colonIndex = content.lastIndex(of: ":") else {
            return (content, nil)
        }

        let offsetStart = content.index(after: colonIndex)
        guard offsetStart < content.endIndex else {
            return (content, nil)
        }

        let offsetText = String(content[offsetStart...])
        guard let offset = dateOffset(from: offsetText) else {
            return (content, nil)
        }

        return (String(content[..<colonIndex]), offset)
    }

    private static func dateOffset(from text: String) -> DateComponents? {
        guard let sign = text.first, sign == "+" || sign == "-" else {
            return nil
        }
        guard let unit = text.last else {
            return nil
        }

        let valueStart = text.index(after: text.startIndex)
        let valueEnd = text.index(before: text.endIndex)
        guard valueStart < valueEnd,
              let rawValue = Int(text[valueStart..<valueEnd]) else {
            return nil
        }

        let signedValue = sign == "-" ? -rawValue : rawValue
        switch unit {
        case "s":
            return DateComponents(second: signedValue)
        case "m":
            return DateComponents(minute: signedValue)
        case "h":
            return DateComponents(hour: signedValue)
        case "d":
            return DateComponents(day: signedValue)
        case "w":
            return DateComponents(day: signedValue * 7)
        case "M":
            return DateComponents(month: signedValue)
        case "y":
            return DateComponents(year: signedValue)
        default:
            return nil
        }
    }

    private static func contentContainsDateField(_ content: String) -> Bool {
        content.contains("y")
            || content.contains("M")
            || content.contains("d")
            || content.contains("H")
            || content.contains("hh")
    }

    private static func normalizedDateFormat(_ format: String) -> String {
        var normalized = ""
        var index = format.startIndex
        var isInsideQuote = false

        while index < format.endIndex {
            let character = format[index]

            if character == "'" {
                normalized.append(character)
                let nextIndex = format.index(after: index)
                if nextIndex < format.endIndex, format[nextIndex] == "'" {
                    normalized.append(format[nextIndex])
                    index = format.index(after: nextIndex)
                } else {
                    isInsideQuote.toggle()
                    index = nextIndex
                }
                continue
            }

            if !isInsideQuote,
               character == "h",
               format.index(after: index) < format.endIndex,
               format[format.index(after: index)] == "h" {
                normalized.append("HH")
                index = format.index(index, offsetBy: 2)
                continue
            }

            normalized.append(character)
            index = format.index(after: index)
        }

        return normalized
    }
}
