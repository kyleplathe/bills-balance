import Foundation
import CoreData

/// Strike account-statement CSV: bill pay is a Withdrawal + Sale pair.
/// The Sale row is the source of truth for history (USD amount, fee, BTC, price).
enum StrikeCSVParser {
    static let referenceNotePrefix = "Strike ref:"

    static func isStrikeCSV(_ data: Data) -> Bool {
        guard let table = try? CSVSupport.table(from: data) else { return false }
        return isStrikeHeader(table.header)
    }

    static func isStrikeHeader(_ header: [String]) -> Bool {
        let hasType = CSVSupport.index(in: header, names: ["transaction type", "type"]) != nil
        let hasUSD = CSVSupport.index(in: header, names: ["amount usd", "amount (usd)"]) != nil
        let hasBTC = CSVSupport.index(in: header, names: ["amount btc", "amount (btc)"]) != nil
        let hasDate = CSVSupport.index(
            in: header,
            names: ["date & time (utc)", "date and time (utc)", "date & time", "date"]
        ) != nil
        return hasType && hasUSD && hasBTC && hasDate
    }

    static func parse(data: Data, calendar: Calendar = .current) throws -> [ParsedStatementTransaction] {
        let table = try CSVSupport.table(from: data)
        guard isStrikeHeader(table.header) else {
            throw CSVParseError.missingRequiredColumns("Transaction Type, Amount USD, Amount BTC")
        }

        let rows = try parseRows(table: table, calendar: calendar)
        let events = collapseBillPays(from: rows)
        guard !events.isEmpty else { throw TransactionCSVParseError.noValidTransactions }
        return events.sorted { $0.date < $1.date }
    }

    static func notes(payee: String, feeUSD: Decimal?, reference: String?) -> String {
        var lines: [String] = []
        let trimmedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPayee.isEmpty {
            lines.append(trimmedPayee.hasPrefix("Bill pay") ? trimmedPayee : "Bill pay to \(trimmedPayee)")
        }
        if let fee = feeUSD, fee > 0 {
            let formatted = CSVSupport.formatDecimal(fee, fractionDigits: 2)
            lines.append("Strike fee: $\(formatted)")
        }
        if let reference, !reference.isEmpty {
            lines.append("\(referenceNotePrefix) \(reference)")
        }
        return lines.joined(separator: "\n")
    }

    static func reference(from notes: String?) -> String? {
        guard let notes else { return nil }
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(referenceNotePrefix.lowercased()) {
                let value = trimmed.dropFirst(referenceNotePrefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    static func payeeName(from description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["bill pay to ", "bill pay "]
        let lower = trimmed.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: - Rows

    struct RawRow {
        var reference: String
        var date: Date
        var type: String
        var amountUSD: Decimal
        var feeUSD: Decimal
        var amountBTC: Decimal
        var btcPrice: Decimal
        var description: String
    }

    private static func parseRows(table: (header: [String], rows: [[String]]), calendar: Calendar) throws -> [RawRow] {
        let header = table.header
        let dateIdx = CSVSupport.index(
            in: header,
            names: ["date & time (utc)", "date and time (utc)", "date & time", "date"]
        )
        let typeIdx = CSVSupport.index(in: header, names: ["transaction type", "type"])
        let usdIdx = CSVSupport.index(in: header, names: ["amount usd", "amount (usd)"])
        let feeUSDIdx = CSVSupport.index(in: header, names: ["fee usd", "fee (usd)"])
        let btcIdx = CSVSupport.index(in: header, names: ["amount btc", "amount (btc)"])
        let priceIdx = CSVSupport.index(in: header, names: ["btc price", "price"])
        let refIdx = CSVSupport.index(in: header, names: ["reference", "id"])
        let descIndexes = header.enumerated().compactMap { index, name -> Int? in
            name.contains("description") || name == "memo" || name == "note" || name == "notes" ? index : nil
        }

        guard let dateIdx, let typeIdx, let usdIdx else {
            throw CSVParseError.missingRequiredColumns("Date, Transaction Type, Amount USD")
        }

        var rows: [RawRow] = []
        for fields in table.rows {
            let dateRaw = CSVSupport.field(fields, at: dateIdx)
            guard let date = CSVSupport.parseCalendarDate(dateRaw, calendar: calendar) else { continue }
            let type = CSVSupport.field(fields, at: typeIdx)
            guard !type.isEmpty else { continue }
            let usd = CSVSupport.parseDecimal(CSVSupport.field(fields, at: usdIdx)) ?? 0
            let fee = CSVSupport.parseDecimal(CSVSupport.field(fields, at: feeUSDIdx)) ?? 0
            let btc = CSVSupport.parseDecimal(CSVSupport.field(fields, at: btcIdx)) ?? 0
            let price = CSVSupport.parseDecimal(CSVSupport.field(fields, at: priceIdx)) ?? 0
            let reference = CSVSupport.field(fields, at: refIdx)
            let description = combinedDescription(fields: fields, indexes: descIndexes)

            rows.append(
                RawRow(
                    reference: reference,
                    date: date,
                    type: type,
                    amountUSD: usd,
                    feeUSD: fee,
                    amountBTC: btc,
                    btcPrice: price,
                    description: description
                )
            )
        }
        return rows
    }

    private static func combinedDescription(fields: [String], indexes: [Int]) -> String {
        let parts = indexes.map { CSVSupport.field(fields, at: $0) }.filter { !$0.isEmpty }
        if let billPay = parts.first(where: { $0.lowercased().contains("bill pay") }) {
            return billPay
        }
        return parts.last ?? ""
    }

    private static func collapseBillPays(from rows: [RawRow]) -> [ParsedStatementTransaction] {
        var usedSaleIndexes = Set<Int>()
        let sales = rows.enumerated().filter { $0.element.type.caseInsensitiveCompare("Sale") == .orderedSame }

        var events: [ParsedStatementTransaction] = []

        for row in rows {
            let type = row.type.lowercased()
            let isBillPay = row.description.lowercased().contains("bill pay")

            if type == "withdrawal" && isBillPay {
                if let saleMatch = bestSale(for: row, sales: sales, excluding: usedSaleIndexes) {
                    usedSaleIndexes.insert(saleMatch.offset)
                    events.append(billPayEvent(withdrawal: row, sale: saleMatch.element))
                } else {
                    events.append(billPayEvent(withdrawal: row, sale: nil))
                }
                continue
            }

            if type == "sale" && isBillPay {
                continue
            }

            if type == "sale" {
                if let idx = sales.first(where: { $0.element.reference == row.reference && $0.element.date == row.date })?.offset,
                   usedSaleIndexes.contains(idx) {
                    continue
                }
            }

            guard let event = event(from: row) else { continue }
            events.append(event)
        }

        for sale in sales where !usedSaleIndexes.contains(sale.offset) {
            let desc = sale.element.description.lowercased()
            if desc.contains("bill pay") {
                events.append(billPayEvent(withdrawal: nil, sale: sale.element))
            }
        }

        return events
    }

    private static func bestSale(
        for withdrawal: RawRow,
        sales: [(offset: Int, element: RawRow)],
        excluding used: Set<Int>
    ) -> (offset: Int, element: RawRow)? {
        let merchant = payeeName(from: withdrawal.description).lowercased()
        let amount = withdrawal.amountUSD.magnitude
        let candidates = sales.filter { sale in
            guard !used.contains(sale.offset) else { return false }
            guard DuplicateBillGuard.amountsMatch(sale.element.amountUSD.magnitude, amount) else { return false }
            let saleMerchant = payeeName(from: sale.element.description).lowercased()
            let saleIsBillPay = sale.element.description.lowercased().contains("bill pay")
            guard saleIsBillPay else { return false }
            if !merchant.isEmpty, !saleMerchant.isEmpty, merchant != saleMerchant {
                return false
            }
            let delta = abs(sale.element.date.timeIntervalSince(withdrawal.date))
            return delta <= 60 * 60 * 72
        }
        return candidates.min { lhs, rhs in
            abs(lhs.element.date.timeIntervalSince(withdrawal.date)) < abs(rhs.element.date.timeIntervalSince(withdrawal.date))
        }
    }

    private static func billPayEvent(withdrawal: RawRow?, sale: RawRow?) -> ParsedStatementTransaction {
        let source = sale ?? withdrawal!
        let payee = payeeName(from: withdrawal?.description ?? sale?.description ?? source.description)
        let usd = (sale?.amountUSD ?? withdrawal?.amountUSD ?? 0).magnitude
        let btc = (sale?.amountBTC ?? 0).magnitude
        let fee = sale?.feeUSD.magnitude ?? withdrawal?.feeUSD.magnitude ?? 0
        let price = sale?.btcPrice ?? 0
        let reference = [sale?.reference, withdrawal?.reference].compactMap { $0 }.first { !$0.isEmpty }
        return ParsedStatementTransaction(
            date: source.date,
            title: payee.isEmpty ? "Bill pay" : payee,
            amount: usd,
            isCredit: false,
            btcAmount: btc > 0 ? btc : nil,
            feeUSD: fee > 0 ? fee : nil,
            btcPrice: price > 0 ? price : nil,
            sourceReference: reference,
            kind: .billPay
        )
    }

    private static func event(from row: RawRow) -> ParsedStatementTransaction? {
        let type = row.type.lowercased()
        switch type {
        case "purchase":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Bitcoin purchase"),
                amount: row.amountUSD.magnitude,
                isCredit: true,
                btcAmount: row.amountBTC.magnitude > 0 ? row.amountBTC.magnitude : nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: row.btcPrice > 0 ? row.btcPrice : nil,
                sourceReference: row.reference,
                kind: .purchase
            )
        case "sale":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Bitcoin sale"),
                amount: row.amountUSD.magnitude,
                isCredit: false,
                btcAmount: row.amountBTC.magnitude > 0 ? row.amountBTC.magnitude : nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: row.btcPrice > 0 ? row.btcPrice : nil,
                sourceReference: row.reference,
                kind: .sale
            )
        case "send":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Send Bitcoin"),
                amount: row.amountUSD.magnitude,
                isCredit: false,
                btcAmount: row.amountBTC.magnitude > 0 ? row.amountBTC.magnitude : nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: row.btcPrice > 0 ? row.btcPrice : nil,
                sourceReference: row.reference,
                kind: .send
            )
        case "receive":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Receive Bitcoin"),
                amount: row.amountUSD.magnitude,
                isCredit: true,
                btcAmount: row.amountBTC.magnitude > 0 ? row.amountBTC.magnitude : nil,
                feeUSD: nil,
                btcPrice: row.btcPrice > 0 ? row.btcPrice : nil,
                sourceReference: row.reference,
                kind: .receive
            )
        case "deposit":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Deposit"),
                amount: row.amountUSD.magnitude,
                isCredit: true,
                btcAmount: nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: nil,
                sourceReference: row.reference,
                kind: .deposit
            )
        case "withdrawal":
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: "Withdrawal"),
                amount: row.amountUSD.magnitude,
                isCredit: false,
                btcAmount: nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: nil,
                sourceReference: row.reference,
                kind: .withdrawal
            )
        default:
            guard row.amountUSD != 0 || row.amountBTC != 0 else { return nil }
            return ParsedStatementTransaction(
                date: row.date,
                title: title(for: row, fallback: row.type),
                amount: row.amountUSD.magnitude,
                isCredit: row.amountUSD >= 0 || row.amountBTC > 0,
                btcAmount: row.amountBTC != 0 ? row.amountBTC.magnitude : nil,
                feeUSD: row.feeUSD.magnitude > 0 ? row.feeUSD.magnitude : nil,
                btcPrice: row.btcPrice > 0 ? row.btcPrice : nil,
                sourceReference: row.reference,
                kind: .generic
            )
        }
    }

    private static func title(for row: RawRow, fallback: String) -> String {
        let description = row.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty { return fallback }
        if description.lowercased().hasPrefix("lnbc") || description.count > 48 {
            return fallback
        }
        return description
    }
}

enum BillPayMatcher {
    static func match(
        payee: String,
        amount: Decimal,
        on date: Date,
        among bills: [Bill],
        calendar: Calendar = .current
    ) -> Bill? {
        let unpaid = bills.filter { !$0.isPaid }
        guard !unpaid.isEmpty else { return nil }

        let scored: [(Bill, Int)] = unpaid.compactMap { bill in
            guard let due = bill.dueDate else { return nil }
            let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: due), to: calendar.startOfDay(for: date)).day ?? 999)
            guard days <= 16 else { return nil }
            let billAmount = bill.amount?.decimalValue ?? 0
            let amountOK = DuplicateBillGuard.amountsMatch(billAmount, amount, tolerance: max(1.0, NSDecimalNumber(decimal: amount).doubleValue * 0.02))
            let nameScore = nameScore(payee: payee, billName: bill.name ?? "")
            var score = 0
            if amountOK { score += 50 }
            if nameScore > 0 { score += nameScore }
            score += max(0, 16 - days)
            if score < 50 { return nil }
            if !amountOK && nameScore < 80 { return nil }
            return (bill, score)
        }
        .sorted { $0.1 > $1.1 }

        guard let best = scored.first else { return nil }
        if scored.count > 1, scored[1].1 == best.1, nameScore(payee: payee, billName: best.0.name ?? "") == 0 {
            return nil
        }
        return best.0
    }

    static func nameScore(payee: String, billName: String) -> Int {
        let a = normalize(payee)
        let b = normalize(billName)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 100 }
        if a.contains(b) || b.contains(a) { return 90 }
        let tokensA = Set(a.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let tokensB = Set(b.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let overlap = tokensA.intersection(tokensB)
        if overlap.isEmpty { return 0 }
        return min(80, overlap.count * 25)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "bill pay to ", with: "")
            .replacingOccurrences(of: "bill pay ", with: "")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
