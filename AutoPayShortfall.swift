import Foundation

/// Eligibility for the launch-time auto-pay pass. Unmarking paid skips that due date
/// so a rebuild/relaunch cannot immediately mark the same occurrence paid again.
enum AutoPayProcessing {
    static let newBillGracePeriod: TimeInterval = 5

    static func occurrenceKey(billId: UUID, dueDate: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: dueDate)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(billId.uuidString)|\(formatter.string(from: day))"
    }

    static func shouldProcess(
        autoPay: Bool,
        isPaid: Bool,
        hasAccount: Bool,
        createdAt: Date?,
        processingDate: Date?,
        isSkipped: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard autoPay, !isPaid, hasAccount, !isSkipped else { return false }
        if let createdAt, now.timeIntervalSince(createdAt) < newBillGracePeriod { return false }
        guard let processingDate else { return false }
        return calendar.startOfDay(for: processingDate) <= calendar.startOfDay(for: now)
    }
}

enum AutoPaySkipStore {
    static var defaults: UserDefaults = .standard
    private static let defaultsKey = "autoPaySkippedOccurrences"

    static func isSkipped(billId: UUID?, dueDate: Date?) -> Bool {
        guard let billId, let dueDate else { return false }
        return skippedKeys.contains(AutoPayProcessing.occurrenceKey(billId: billId, dueDate: dueDate))
    }

    static func skip(billId: UUID?, dueDate: Date?) {
        guard let billId, let dueDate else { return }
        var keys = skippedKeys
        keys.insert(AutoPayProcessing.occurrenceKey(billId: billId, dueDate: dueDate))
        skippedKeys = keys
    }

    static func clear(billId: UUID?, dueDate: Date?) {
        guard let billId, let dueDate else { return }
        var keys = skippedKeys
        keys.remove(AutoPayProcessing.occurrenceKey(billId: billId, dueDate: dueDate))
        skippedKeys = keys
    }

    static func resetForTests() {
        defaults.removeObject(forKey: defaultsKey)
    }

    private static var skippedKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: defaultsKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: defaultsKey) }
    }
}

/// Whether an auto-pay debit would land an account below its reserve. USD accounts only.
enum AutoPayShortfall {
    static func debitAmount(billAmount: Decimal, feePercentage: Decimal) -> Decimal {
        guard billAmount > 0 else { return .zero }
        guard feePercentage > 0 else { return billAmount }
        return billAmount + billAmount * (feePercentage / 100)
    }

    static func remainingBalance(currentBalance: Decimal, debit: Decimal) -> Decimal {
        currentBalance - debit
    }

    static func wouldHold(
        autoPay: Bool,
        isPaid: Bool,
        currencyCode: String,
        currentBalance: Decimal,
        billAmount: Decimal,
        feePercentage: Decimal,
        reserve: Decimal
    ) -> Bool {
        guard autoPay, !isPaid else { return false }
        guard currencyCode.uppercased() == "USD" else { return false }
        let debit = debitAmount(billAmount: billAmount, feePercentage: feePercentage)
        guard debit > 0 else { return false }
        return remainingBalance(currentBalance: currentBalance, debit: debit) < reserve
    }

    static func notificationIdentifier(billId: UUID) -> String {
        "shortfall-\(billId.uuidString)"
    }

    static func notificationBody(billName: String, accountName: String, reserve: Decimal) -> String {
        if reserve > 0 {
            return "\(billName) would leave \(accountName) below your \(MoneyFormatting.currencyString(reserve)) reserve."
        }
        return "\(billName) would overdraw \(accountName)."
    }
}
