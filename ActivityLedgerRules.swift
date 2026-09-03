import Foundation

/// Paired debit/credit created by an in-app account transfer.
enum LedgerTransfer {
    static let category = "Transfer"
    private static let markerKey = "__TRANSFER_ID__:"

    static func isCreditAccount(_ type: String?) -> Bool {
        ActivityLedgerRules.isCreditAccount(type)
    }

    static func isTransfer(category: String?, title: String) -> Bool {
        if let category, category.caseInsensitiveCompare(Self.category) == .orderedSame {
            return true
        }
        let lower = title.lowercased()
        return lower.contains("transfer to") || lower.contains("transfer from")
    }

    static func debitTitle(toAccountName: String, toIsCreditAccount: Bool) -> String {
        toIsCreditAccount ? "Payment to \(toAccountName)" : "Transfer to \(toAccountName)"
    }

    static func creditTitle(fromAccountName: String, fromIsCreditAccount: Bool) -> String {
        fromIsCreditAccount ? "Payment from \(fromAccountName)" : "Transfer from \(fromAccountName)"
    }

    static func appendingPairId(to notes: String?, pairId: UUID) -> String {
        let marker = "\u{200B}\(markerKey)\(pairId.uuidString)\u{200B}"
        let existing = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.contains(markerKey) { return notes ?? marker }
        return existing.isEmpty ? marker : "\(existing)\n\(marker)"
    }

    static func pairId(from notes: String?) -> UUID? {
        guard let notes, let range = notes.range(of: markerKey) else { return nil }
        let hex = notes[range.upperBound...].prefix(36)
        return UUID(uuidString: String(hex))
    }

    static func searchToken(for pairId: UUID) -> String {
        "\(markerKey)\(pairId.uuidString)"
    }
}

/// How Activity totals treat checking vs credit-card ledger rows so importing both does not double-count.
enum ActivityLedgerRules {
    static func isCreditAccount(_ type: String?) -> Bool {
        (type ?? "").lowercased() == "credit"
    }

    static func isCardPaymentTitle(_ title: String, cardNames: [String], isCreditEntry: Bool) -> Bool {
        let titleLower = title.lowercased()
        if titleLower.contains("credit card payment") { return true }
        if titleLower.contains("credit card") && titleLower.contains("payment") { return true }
        if titleLower.contains("credit crd") { return true }
        for cardName in cardNames where !cardName.isEmpty {
            let cardLower = cardName.lowercased()
            if titleLower.contains(cardLower) && (titleLower.contains("payment") || titleLower.contains("epay") || isCreditEntry) {
                return true
            }
        }
        return false
    }

    static func isCardSpendingTitle(_ title: String, cardNames: [String], isCreditEntry: Bool) -> Bool {
        if isCardPaymentTitle(title, cardNames: cardNames, isCreditEntry: isCreditEntry) { return false }
        let titleLower = title.lowercased()
        if titleLower.contains("credit card") && !titleLower.contains("payment") { return true }
        guard !isCreditEntry else { return false }
        for cardName in cardNames where !cardName.isEmpty {
            if titleLower.contains(cardName.lowercased()) && !titleLower.contains("payment") {
                return true
            }
        }
        return false
    }

    /// Include in income/expense totals. Credit-account purchases count; card payments and in-app transfers do not.
    static func includeInTotals(accountType: String?, isCredit: Bool, title: String, cardNames: [String], category: String? = nil) -> Bool {
        if LedgerTransfer.isTransfer(category: category, title: title) {
            return false
        }
        if isCreditAccount(accountType) {
            return !isCredit
        }
        if !isCredit && isCardPaymentTitle(title, cardNames: cardNames, isCreditEntry: false) {
            return false
        }
        return true
    }
}
