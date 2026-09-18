//
//  FeeParsing.swift
//  BillsAndBalance
//
//  Extracts fee and sales-tax amounts from transaction notes.
//

import Foundation

enum FeeParsing {
    /// Extracts USD fee amounts from transaction notes. Supports:
    /// - "Fee: 6.36 USD (0.796%)" or "Fee: $6.36 USD"
    /// - "Strike fee: $6.36" or "Strike fee: 6.36"
    /// - "Digital Wallet Fee: 6.36 USD (0.796%)"
    /// - "Transfer Fee: 2.50 USD"
    static func feeFromNotes(_ notes: String?) -> Decimal {
        guard let notes = notes else { return 0 }
        var total: Decimal = 0
        for line in notes.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Digital Wallet Fee:") {
                if let num = extractLeadingNumber(from: t, after: "Digital Wallet Fee:") {
                    total += num
                }
            } else if t.contains("Transfer Fee:") {
                if let num = extractLeadingNumber(from: t, after: "Transfer Fee:") {
                    total += num
                }
            } else if t.contains("Fee:"), t.contains(" USD") {
                if let num = extractLeadingNumber(from: t, after: "Fee:") {
                    total += num
                }
            } else if t.contains("Strike fee:") {
                if let num = extractLeadingNumber(from: t, after: "Strike fee:") {
                    total += num
                }
            }
        }
        return total
    }

    /// Extracts sales tax from notes: "Sales Tax: 1.25 USD" or "Sales Tax: $1.25".
    static func salesTaxFromNotes(_ notes: String?) -> Decimal {
        guard let notes = notes else { return 0 }
        var total: Decimal = 0
        for line in notes.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Sales Tax:") {
                if let num = extractLeadingNumber(from: t, after: "Sales Tax:") {
                    total += num
                }
            }
        }
        return total
    }

    static func appendingSalesTaxNote(to notes: String?, tax: Decimal) -> String? {
        guard tax > 0 else { return notes }
        let taxDouble = (tax as NSDecimalNumber).doubleValue
        let line = "Sales Tax: \(String(format: "%.2f", taxDouble)) USD"
        if let notes, !notes.isEmpty {
            return notes.contains("Sales Tax:") ? notes : "\(notes)\n\(line)"
        }
        return line
    }

    static func appendingWalletFeeNote(to notes: String?, fee: Decimal, percentage: Decimal?) -> String? {
        guard fee > 0 else { return notes }
        let feeDouble = (fee as NSDecimalNumber).doubleValue
        let line: String
        if let percentage, percentage > 0 {
            let pct = (percentage as NSDecimalNumber).doubleValue
            line = "Digital Wallet Fee: \(String(format: "%.2f", feeDouble)) USD (\(String(format: "%.3f", pct))%)"
        } else {
            line = "Digital Wallet Fee: \(String(format: "%.2f", feeDouble)) USD"
        }
        if let notes, !notes.isEmpty {
            return notes.contains("Digital Wallet Fee:") ? notes : "\(notes)\n\(line)"
        }
        return line
    }

    private static func extractLeadingNumber(from s: String, after prefix: String) -> Decimal? {
        guard let r = s.range(of: prefix) else { return nil }
        var rest = String(s[r.upperBound...])
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("$") {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let numPart = rest.prefix(while: { $0.isNumber || $0 == "." || $0 == "," })
        let cleaned = String(numPart).replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }
}
