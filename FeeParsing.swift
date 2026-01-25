//
//  FeeParsing.swift
//  BillsAndBalance
//
//  Extracts digital wallet fee amounts from transaction notes.
//  Fees are stored as lines on each transaction; this parses those lines.
//

import Foundation

enum FeeParsing {
    /// Extracts USD fee amounts from transaction notes. Data is pulled from the
    /// "digital wallet fees" line on each transaction. Supports:
    /// - "Fee: 6.36 USD (0.796%)" or "Fee: $6.36 USD" (transaction card format)
    /// - "Strike fee: $6.36" or "Strike fee: 6.36" (Strike/bill flow format)
    /// Sums all matching amounts (multiple fee lines per transaction supported).
    static func feeFromNotes(_ notes: String?) -> Decimal {
        guard let notes = notes else { return 0 }
        var total: Decimal = 0
        for line in notes.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Fee:"), t.contains(" USD") {
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
