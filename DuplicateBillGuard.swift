import Foundation

/// In-memory duplicate detection for recurring bills (name + day + amount, or series + day).
enum DuplicateBillGuard {
    static let amountTolerance: Double = 0.01

    static func pendingKey(seriesId: UUID, date: Date, calendar: Calendar = .current) -> String {
        let dateKey = calendar.startOfDay(for: date).timeIntervalSince1970
        return "\(seriesId.uuidString)-\(dateKey)"
    }

    static func identityKey(name: String, date: Date, amount: Decimal, calendar: Calendar = .current) -> String {
        let dateKey = calendar.startOfDay(for: date).timeIntervalSince1970
        return "\(name)-\(dateKey)-\(amount)"
    }

    static func amountsMatch(_ lhs: Decimal, _ rhs: Decimal, tolerance: Double = amountTolerance) -> Bool {
        abs(NSDecimalNumber(decimal: lhs - rhs).doubleValue) < tolerance
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// Returns true when `candidate` matches an existing bill by series+day or name+day+amount.
    static func isDuplicate(
        name: String,
        amount: Decimal,
        dueDate: Date,
        seriesId: UUID?,
        existing: [(name: String, amount: Decimal, dueDate: Date, seriesId: UUID?)],
        calendar: Calendar = .current
    ) -> Bool {
        existing.contains { bill in
            let sameDay = isSameDay(bill.dueDate, dueDate, calendar: calendar)
            guard sameDay else { return false }
            if let seriesId, bill.seriesId == seriesId {
                return true
            }
            return bill.name == name && amountsMatch(bill.amount, amount)
        }
    }
}
