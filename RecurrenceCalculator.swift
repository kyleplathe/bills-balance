import Foundation

/// Pure recurrence date math used by bill generation and tests.
enum RecurrenceCalculator {
    static func nextDate(from date: Date, type: String, interval: Int, calendar: Calendar = .current) -> Date {
        shiftedDate(from: date, type: type, interval: interval, step: 1, calendar: calendar)
    }

    static func previousDate(from date: Date, type: String, interval: Int, calendar: Calendar = .current) -> Date {
        shiftedDate(from: date, type: type, interval: interval, step: -1, calendar: calendar)
    }

    private static func shiftedDate(from date: Date, type: String, interval: Int, step: Int, calendar: Calendar) -> Date {
        let actualInterval = max(interval, 1) * step

        switch type {
        case "daily":
            return calendar.date(byAdding: .day, value: actualInterval, to: date) ?? date
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: actualInterval, to: date) ?? date
        case "biweekly":
            return calendar.date(byAdding: .weekOfYear, value: 2 * step, to: date) ?? date
        case "monthly":
            return calendar.date(byAdding: .month, value: actualInterval, to: date) ?? date
        case "bimonthly":
            return calendar.date(byAdding: .month, value: 2 * step, to: date) ?? date
        case "quarterly":
            return calendar.date(byAdding: .month, value: 3 * actualInterval, to: date) ?? date
        case "semiannually":
            return calendar.date(byAdding: .month, value: 6 * step, to: date) ?? date
        case "yearly":
            return calendar.date(byAdding: .year, value: actualInterval, to: date) ?? date
        default:
            return date
        }
    }

    static func dates(
        from start: Date,
        type: String,
        interval: Int,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        var dates: [Date] = [start]
        var current = start
        for _ in 1..<count {
            let next = nextDate(from: current, type: type, interval: interval, calendar: calendar)
            if next <= current { break }
            dates.append(next)
            current = next
        }
        return dates
    }

    /// Recurrence dates walking backward from `start` (inclusive) until `end` (inclusive). `end` should be earlier than `start`.
    static func datesGoingBack(
        from start: Date,
        through end: Date,
        type: String,
        interval: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard end <= start else { return [start] }
        var dates: [Date] = [start]
        var current = start
        for _ in 0..<600 {
            let previous = previousDate(from: current, type: type, interval: interval, calendar: calendar)
            if previous >= current { break }
            if previous < calendar.startOfDay(for: end) { break }
            dates.append(previous)
            current = previous
        }
        return dates
    }
}
