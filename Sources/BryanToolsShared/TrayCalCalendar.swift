import Foundation

public struct TrayCalDayCell: Equatable, Identifiable {
    public let date: Date
    public let day: Int
    public let isInDisplayedMonth: Bool
    public let isToday: Bool

    public var id: Date {
        date
    }

    public init(date: Date, day: Int, isInDisplayedMonth: Bool, isToday: Bool) {
        self.date = date
        self.day = day
        self.isInDisplayedMonth = isInDisplayedMonth
        self.isToday = isToday
    }
}

public struct TrayCalCalendarState: Equatable {
    public private(set) var displayedMonth: Date

    public init(displayedMonth: Date, calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        self.displayedMonth = TrayCalCalendar.monthStart(containing: displayedMonth, calendar: calendar)
    }

    public mutating func showPreviousMonth(calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        displayedMonth = TrayCalCalendar.addingMonths(-1, to: displayedMonth, calendar: calendar)
    }

    public mutating func showNextMonth(calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        displayedMonth = TrayCalCalendar.addingMonths(1, to: displayedMonth, calendar: calendar)
    }

    public mutating func returnToToday(_ today: Date, calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        displayedMonth = TrayCalCalendar.monthStart(containing: today, calendar: calendar)
    }

    public mutating func showMonth(_ month: Int, calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        displayedMonth = TrayCalCalendar.replacingMonth(month, in: displayedMonth, calendar: calendar)
    }

    public mutating func showYear(_ year: Int, calendar: Calendar = TrayCalCalendar.defaultCalendar()) {
        displayedMonth = TrayCalCalendar.replacingYear(year, in: displayedMonth, calendar: calendar)
    }
}

public enum TrayCalCalendar {
    public static func defaultCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        return calendar
    }

    public static func statusTitle(for date: Date, calendar: Calendar = defaultCalendar()) -> String {
        formatted(date, format: "EEE, MMM d", calendar: calendar)
    }

    public static func monthTitle(for date: Date, calendar: Calendar = defaultCalendar()) -> String {
        formatted(monthStart(containing: date, calendar: calendar), format: "MMMM yyyy", calendar: calendar)
    }

    public static func monthName(for date: Date, calendar: Calendar = defaultCalendar()) -> String {
        formatted(monthStart(containing: date, calendar: calendar), format: "MMM", calendar: calendar)
    }

    public static func year(for date: Date, calendar: Calendar = defaultCalendar()) -> Int {
        calendar.component(.year, from: date)
    }

    public static func month(for date: Date, calendar: Calendar = defaultCalendar()) -> Int {
        calendar.component(.month, from: date)
    }

    public static func monthSymbols(calendar: Calendar = defaultCalendar()) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.shortMonthSymbols
    }

    public static func monthStart(containing date: Date, calendar: Calendar = defaultCalendar()) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    public static func addingMonths(_ months: Int, to date: Date, calendar: Calendar = defaultCalendar()) -> Date {
        let monthStart = monthStart(containing: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: months, to: monthStart) ?? monthStart
    }

    public static func replacingMonth(_ month: Int, in date: Date, calendar: Calendar = defaultCalendar()) -> Date {
        let clampedMonth = min(max(month, 1), 12)
        let year = calendar.component(.year, from: date)
        return monthDate(year: year, month: clampedMonth, calendar: calendar)
    }

    public static func replacingYear(_ year: Int, in date: Date, calendar: Calendar = defaultCalendar()) -> Date {
        let month = calendar.component(.month, from: date)
        return monthDate(year: year, month: month, calendar: calendar)
    }

    public static func monthDate(year: Int, month: Int, calendar: Calendar = defaultCalendar()) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: min(max(month, 1), 12),
            day: 1
        )
        return calendar.date(from: components) ?? Date()
    }

    public static func monthGrid(
        displayedMonth: Date,
        today: Date,
        calendar: Calendar = defaultCalendar()
    ) -> [TrayCalDayCell] {
        let monthStart = monthStart(containing: displayedMonth, calendar: calendar)
        let normalizedToday = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let isInDisplayedMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            return TrayCalDayCell(
                date: date,
                day: calendar.component(.day, from: date),
                isInDisplayedMonth: isInDisplayedMonth,
                isToday: isInDisplayedMonth && calendar.isDate(calendar.startOfDay(for: date), inSameDayAs: normalizedToday)
            )
        }
    }

    private static func formatted(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
