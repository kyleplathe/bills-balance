import Foundation

extension LedgerEntry {
    var amountDecimal: Decimal {
        amount?.decimalValue ?? .zero
    }

    var btcAmountDecimal: Decimal {
        btcAmount?.decimalValue ?? .zero
    }

    var usdAmountDecimal: Decimal {
        usdAmount?.decimalValue ?? .zero
    }

    var btcPriceAtTransactionDecimal: Decimal {
        btcPriceAtTransaction?.decimalValue ?? .zero
    }

    var feeAmountDecimal: Decimal {
        feeAmount?.decimalValue ?? .zero
    }

    func amountInCurrency(for account: Account) -> Decimal {
        if account.currencyCode == "BTC" {
            if btcAmountDecimal != .zero {
                return btcAmountDecimal
            } else if usdAmountDecimal != .zero && btcPriceAtTransactionDecimal > 0 {
                return usdAmountDecimal / btcPriceAtTransactionDecimal
            }
            return .zero
        } else {
            if usdAmountDecimal != .zero {
                return usdAmountDecimal
            }
            return amountDecimal
        }
    }

    var signedAmount: Decimal {
        isCredit ? amountDecimal : amountDecimal * -1
    }

    func signedAmountInCurrency(for account: Account) -> Decimal {
        let amount = amountInCurrency(for: account)
        return isCredit ? amount : amount * -1
    }

    var isReconciledFlag: Bool {
        get { value(forKey: "isReconciled") as? Bool ?? false }
        set { setValue(newValue, forKey: "isReconciled") }
    }
}

extension Account {
    var startingBalanceDecimal: Decimal {
        startingBalance?.decimalValue ?? .zero
    }

    var isSnapshotFlag: Bool {
        get { value(forKey: "isSnapshot") as? Bool ?? false }
        set { setValue(newValue, forKey: "isSnapshot") }
    }

    var isHiddenFlag: Bool {
        get { value(forKey: "isHidden") as? Bool ?? false }
        set { setValue(newValue, forKey: "isHidden") }
    }

    var snapshotBalanceDecimal: Decimal {
        get { snapshotBalance?.decimalValue ?? startingBalanceDecimal }
        set { snapshotBalance = NSDecimalNumber(decimal: newValue) }
    }

    var currencyCode: String {
        get { value(forKey: "currency") as? String ?? "USD" }
        set { setValue(newValue, forKey: "currency") }
    }

    var feePercentageDecimal: Decimal {
        get { (value(forKey: "feePercentage") as? NSDecimalNumber)?.decimalValue ?? 0 }
        set { setValue(NSDecimalNumber(decimal: newValue), forKey: "feePercentage") }
    }

    var startingBalanceUSDDecimal: Decimal {
        (value(forKey: "startingBalanceUSD") as? NSDecimalNumber)?.decimalValue ?? .zero
    }

    var startingBalanceBTCPriceDecimal: Decimal {
        (value(forKey: "startingBalanceBTCPrice") as? NSDecimalNumber)?.decimalValue ?? .zero
    }
}
