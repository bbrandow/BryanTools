import Foundation

public struct AlarmPanelPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct AlarmPreferences: Equatable, Sendable {
    public static let defaultShowsFloatingTimer = true

    public var targetDate: Date?
    public var countdownPosition: AlarmPanelPosition?
    public var showsFloatingTimer: Bool

    public init(
        targetDate: Date? = nil,
        countdownPosition: AlarmPanelPosition? = nil,
        showsFloatingTimer: Bool = AlarmPreferences.defaultShowsFloatingTimer
    ) {
        self.targetDate = targetDate
        self.countdownPosition = countdownPosition
        self.showsFloatingTimer = showsFloatingTimer
    }

    public static func load(defaults: UserDefaults = .standard) -> AlarmPreferences {
        let targetDate = defaults.object(forKey: Key.targetDate) as? Date
        let position: AlarmPanelPosition?
        if defaults.object(forKey: Key.positionX) != nil,
           defaults.object(forKey: Key.positionY) != nil {
            position = AlarmPanelPosition(
                x: defaults.double(forKey: Key.positionX),
                y: defaults.double(forKey: Key.positionY)
            )
        } else {
            position = nil
        }
        let showsFloatingTimer = defaults.object(forKey: Key.showsFloatingTimer) == nil
            ? defaultShowsFloatingTimer
            : defaults.bool(forKey: Key.showsFloatingTimer)
        return AlarmPreferences(
            targetDate: targetDate,
            countdownPosition: position,
            showsFloatingTimer: showsFloatingTimer
        )
    }

    public func save(defaults: UserDefaults = .standard) {
        if let targetDate {
            defaults.set(targetDate, forKey: Key.targetDate)
        } else {
            defaults.removeObject(forKey: Key.targetDate)
        }

        if let countdownPosition {
            defaults.set(countdownPosition.x, forKey: Key.positionX)
            defaults.set(countdownPosition.y, forKey: Key.positionY)
        } else {
            defaults.removeObject(forKey: Key.positionX)
            defaults.removeObject(forKey: Key.positionY)
        }
        defaults.set(showsFloatingTimer, forKey: Key.showsFloatingTimer)
    }

    private enum Key {
        static let targetDate = "alarm.targetDate"
        static let positionX = "alarm.countdownPosition.x"
        static let positionY = "alarm.countdownPosition.y"
        static let showsFloatingTimer = "alarm.showsFloatingTimer"
    }
}

public struct AlarmState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case inactive
        case scheduled
        case firing
    }

    public private(set) var phase: Phase
    public private(set) var targetDate: Date?

    public init(targetDate: Date? = nil) {
        self.targetDate = targetDate
        self.phase = targetDate == nil ? .inactive : .scheduled
    }

    public var isActive: Bool {
        targetDate != nil
    }

    public mutating func set(targetDate: Date) {
        self.targetDate = targetDate
        phase = .scheduled
    }

    public mutating func markFiring() {
        guard targetDate != nil else {
            return
        }
        phase = .firing
    }

    public mutating func clear() {
        targetDate = nil
        phase = .inactive
    }
}

public enum AlarmValidationError: Error, Equatable, LocalizedError {
    case invalidDuration
    case notInFuture
    case notToday

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Enter a duration greater than zero using 0-23 hours and 0-59 minutes."
        case .notInFuture:
            return "Choose a time later than the current time."
        case .notToday:
            return "Alarms must be scheduled before the end of today."
        }
    }
}

public enum AlarmReconciliation: Equatable, Sendable {
    case none
    case schedule
    case fireNow
    case clear
}

public enum AlarmSchedule {
    public static func target(
        afterHours hours: Int,
        minutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result<Date, AlarmValidationError> {
        guard (0...23).contains(hours), (0...59).contains(minutes), hours > 0 || minutes > 0 else {
            return .failure(.invalidDuration)
        }
        guard let target = calendar.date(
            byAdding: .second,
            value: hours * 3_600 + minutes * 60,
            to: now
        ) else {
            return .failure(.invalidDuration)
        }
        return validated(target: target, now: now, calendar: calendar)
    }

    public static func targetToday(
        matching time: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result<Date, AlarmValidationError> {
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = 0
        guard let target = calendar.date(from: components) else {
            return .failure(.notToday)
        }
        return validated(target: target, now: now, calendar: calendar)
    }

    public static func validated(
        target: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Result<Date, AlarmValidationError> {
        guard calendar.isDate(target, inSameDayAs: now) else {
            return .failure(.notToday)
        }
        guard target > now else {
            return .failure(.notInFuture)
        }
        return .success(target)
    }

    public static func reconciliation(
        target: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AlarmReconciliation {
        guard let target else {
            return .none
        }
        guard calendar.isDate(target, inSameDayAs: now) else {
            return .clear
        }
        return target > now ? .schedule : .fireNow
    }

    public static func remainingText(target: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(0, Int(ceil(target.timeIntervalSince(now))))
        let hours = remainingSeconds / 3_600
        let minutes = remainingSeconds % 3_600 / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public static func timeTitle(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
