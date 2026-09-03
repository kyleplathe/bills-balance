import Foundation

/// Checkbook and projected-available math, kept pure for unit tests.
enum BalanceMath {
    /// Starting balance plus signed amounts of reconciled (cleared) entries.
    static func cleared(startingBalance: Decimal, reconciledSignedAmounts: [Decimal]) -> Decimal {
        reconciledSignedAmounts.reduce(startingBalance, +)
    }

    /// Current ledger total minus unpaid bills in the window, plus expected income in the window.
    static func available(currentBalance: Decimal, pendingBills: Decimal, pendingIncome: Decimal) -> Decimal {
        currentBalance - (pendingBills - pendingIncome)
    }

    static func windowEnd(from start: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(days, 1), to: calendar.startOfDay(for: start)) ?? start
    }

    static func isInProjectionWindow(_ date: Date, start: Date, days: Int, calendar: Calendar = .current) -> Bool {
        let windowStart = calendar.startOfDay(for: start)
        let windowEnd = windowEnd(from: start, days: days, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        return day >= windowStart && day < windowEnd
    }

    /// Headline net worth: hidden accounts never contribute, even when shown in the list.
    static func totalVisible(amounts: [(amount: Decimal, isHidden: Bool)]) -> Decimal {
        amounts.reduce(.zero) { partial, item in
            item.isHidden ? partial : partial + item.amount
        }
    }
}
