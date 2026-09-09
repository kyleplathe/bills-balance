import Foundation

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
