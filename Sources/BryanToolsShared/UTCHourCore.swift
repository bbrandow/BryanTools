import Foundation

public struct UTCHourPreferences: Equatable {
    public static let defaultEnabled = true

    public var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public static func load(defaults: UserDefaults = .standard) -> UTCHourPreferences {
        let enabled: Bool
        if defaults.object(forKey: "utcHour.isEnabled") == nil {
            enabled = defaultEnabled
        } else {
            enabled = defaults.bool(forKey: "utcHour.isEnabled")
        }
        return UTCHourPreferences(isEnabled: enabled)
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: "utcHour.isEnabled")
    }
}

public struct UTCHourRow: Equatable, Identifiable {
    public let utcHour: Date
    public let utcTitle: String
    public let pacificTitle: String
    public let isPacificMidnight: Bool
    public let isCurrentHour: Bool

    public var id: Date { utcHour }
}

public enum UTCHourDisplay {
    public static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
    public static let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!
    public static let defaultPastHours = 72
    public static let defaultFutureHours = 72

    public static func currentUTCHour(now: Date = Date()) -> Date {
        hourStart(for: now, timeZone: utcTimeZone)
    }

    public static func statusTitle(for date: Date, timeZone: TimeZone = utcTimeZone) -> String {
        formattedUTCHour(hourStart(for: date, timeZone: timeZone), timeZone: timeZone)
    }

    public static func lookupRows(
        centeredAt date: Date = Date(),
        pastHours: Int = defaultPastHours,
        futureHours: Int = defaultFutureHours
    ) -> [UTCHourRow] {
        let currentHour = currentUTCHour(now: date)
        let clampedPastHours = max(0, pastHours)
        let clampedFutureHours = max(0, futureHours)
        let calendar = calendar(timeZone: utcTimeZone)

        return (-clampedPastHours...clampedFutureHours).compactMap { offset in
            guard let utcHour = calendar.date(byAdding: .hour, value: offset, to: currentHour) else {
                return nil
            }
            return UTCHourRow(
                utcHour: utcHour,
                utcTitle: formattedUTCHour(utcHour, timeZone: utcTimeZone),
                pacificTitle: formattedPacificHour(utcHour),
                isPacificMidnight: isPacificMidnight(utcHour),
                isCurrentHour: utcHour == currentHour
            )
        }
    }

    public static func hourStart(for date: Date, timeZone: TimeZone) -> Date {
        let calendar = calendar(timeZone: timeZone)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func formattedUTCHour(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar(timeZone: timeZone)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        return formatter.string(from: date)
    }

    private static func formattedPacificHour(_ date: Date) -> String {
        let calendar = calendar(timeZone: pacificTimeZone)
        let hour = calendar.component(.hour, from: date)
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = pacificTimeZone
        formatter.dateFormat = "MMMM d"
        let paddedHour = displayHour < 10 ? " \(displayHour)" : "\(displayHour)"
        return "\(formatter.string(from: date)), \(paddedHour):00\(hour < 12 ? "am" : "pm")"
    }

    private static func isPacificMidnight(_ date: Date) -> Bool {
        calendar(timeZone: pacificTimeZone).component(.hour, from: date) == 0
    }

    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
