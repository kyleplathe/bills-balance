//
//  TransactionCSVParser.swift
//  BillsAndBalance
//
//  Parses bank/credit card transaction CSV exports (Chase, Amex, Citi, etc.).
//  Best practice: use CSV export from your bank; PDF parsing is unreliable.
//

import Foundation

/// Shared type for both CSV and (legacy) PDF import.
struct ParsedStatementTransaction: Identifiable, Equatable {
    let id = UUID()
    var date: Date
    var title: String
    var amount: Decimal
    /// true = payment/credit, false = purchase/debit
    var isCredit: Bool
}

enum TransactionCSVParseError: LocalizedError {
    case invalidEncoding
    case emptyOrNoData
    case missingRequiredColumns
    case noValidTransactions

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Could not read the CSV file."
        case .emptyOrNoData: return "CSV is empty or has no data rows."
        case .missingRequiredColumns: return "CSV must have Date and Description (or Payee/Memo) and Amount columns."
        case .noValidTransactions: return "No valid transactions were found."
        }
    }
}

enum TransactionCSVParser {

    private static let dateFormats: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy", "M/d/yyyy",
            "MM/dd/yy", "M/d/yy",
            "dd-MMM-yyyy", "d MMM yyyy",
            "MMM d, yyyy", "MMMM d, yyyy",
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    /// Parse CSV data into transactions. Supports common bank export column names.
    static func parse(data: Data) throws -> [ParsedStatementTransaction] {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw TransactionCSVParseError.invalidEncoding
        }
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            throw TransactionCSVParseError.emptyOrNoData
        }

        let header = parseCSVLine(lines[0])
        let headerLower = header.map { $0.lowercased() }

        let dateIdx = indexOf(headerLower, keys: ["date", "trans date", "post date", "transaction date", "posting date"])
        let descIdx = indexOf(headerLower, keys: ["description", "payee", "memo", "name", "details", "merchant", "reference"])
        let amountIdx = indexOf(headerLower, keys: ["amount"])
        let debitIdx = indexOf(headerLower, keys: ["debit", "debits"])
        let creditIdx = indexOf(headerLower, keys: ["credit", "credits"])
        let categoryIdx = indexOf(headerLower, keys: ["category", "type"])

        let hasAmount = amountIdx != nil
        let hasDebitCredit = debitIdx != nil && creditIdx != nil

        guard dateIdx != nil, descIdx != nil, hasAmount || hasDebitCredit else {
            throw TransactionCSVParseError.missingRequiredColumns
        }

        var transactions: [ParsedStatementTransaction] = []
        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard let tx = parseRow(
                fields: fields,
                dateIdx: dateIdx!,
                descIdx: descIdx!,
                amountIdx: amountIdx,
                debitIdx: debitIdx,
                creditIdx: creditIdx,
                categoryIdx: categoryIdx
            ) else { continue }
            transactions.append(tx)
        }

        guard !transactions.isEmpty else {
            throw TransactionCSVParseError.noValidTransactions
        }

        return transactions.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    private static func indexOf(_ headerLower: [String], keys: [String]) -> Int? {
        for k in keys {
            if let i = headerLower.firstIndex(of: k) { return i }
        }
        return nil
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for c in line {
            if c == "\"" {
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                fields.append(trimField(current))
                current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(trimField(current))
        return fields
    }

    private static func trimField(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") && t.hasSuffix("\"") {
            t = String(t.dropFirst().dropLast())
        }
        return t.replacingOccurrences(of: "\"\"", with: "\"")
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        for f in dateFormats {
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    private static func parseAmount(_ raw: String) -> Decimal? {
        let t = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
        return Decimal(string: t)
    }

    private static func parseRow(
        fields: [String],
        dateIdx: Int,
        descIdx: Int,
        amountIdx: Int?,
        debitIdx: Int?,
        creditIdx: Int?,
        categoryIdx: Int?
    ) -> ParsedStatementTransaction? {
        guard fields.count > max(dateIdx, descIdx) else { return nil }
        guard let date = parseDate(fields[dateIdx]) else { return nil }
        let title = fields[descIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var amount: Decimal = 0
        var isCredit = false

        if let ai = amountIdx, fields.count > ai {
            guard let a = parseAmount(fields[ai]) else { return nil }
            amount = a.magnitude
            isCredit = a <= 0 // negative amount = payment/credit in typical exports
        } else if let di = debitIdx, let ci = creditIdx, fields.count > max(di, ci) {
            let db = parseAmount(fields[di]) ?? 0
            let cr = parseAmount(fields[ci]) ?? 0
            if db > 0 && cr == 0 {
                amount = db
                isCredit = false
            } else if cr > 0 && db == 0 {
                amount = cr
                isCredit = true
            } else {
                return nil
            }
        } else {
            return nil
        }

        guard amount > 0 else { return nil }
        return ParsedStatementTransaction(date: date, title: title, amount: amount, isCredit: isCredit)
    }
}
