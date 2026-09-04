import Foundation

enum BillBtcBacktest {
    struct Template: Equatable {
        var name: String
        var amount: Decimal
        var dueDay: Int
        var seriesId: UUID?
        var category: String?
    }

    /// A bill instance used to decide which recurring series appear in USD vs Bitcoin.
    struct BillSource: Equatable {
        var groupingKey: String
        var name: String
        var amount: Decimal
        var dueDate: Date?
        var seriesId: UUID?
        var category: String?
        var trackInBitcoin: Bool
        var paidInBitcoin: Bool
    }

    struct LedgerCandidate {
        var date: Date
        var title: String
        var usd: Decimal
        var btc: Decimal?
        var price: Decimal?
        var billName: String?
        var billSeriesId: UUID?
        var category: String?
    }

    struct MonthAmount: Equatable {
        var usd: Decimal
        var btc: Decimal
        var price: Decimal
        var isEstimate: Bool
    }

    /// Dollar bill paid with an actual BTC/sats amount (not merely assigned to a BTC account).
    static func isUsdBillPaidInBitcoin(isCredit: Bool, usdAmount: Decimal, btcAmount: Decimal) -> Bool {
        !isCredit && usdAmount > 0 && btcAmount > 0
    }

    static func groupingKey(seriesId: UUID?, billId: UUID?, objectURI: String) -> String {
        seriesId?.uuidString ?? billId?.uuidString ?? objectURI
    }

    /// Latest bill in each series that was paid in BTC/sats, or explicitly flagged Track in Bitcoin.
    static func templates(from bills: [BillSource], calendar: Calendar = .current) -> [Template] {
        var trackedKeys = Set<String>()
        for bill in bills where bill.trackInBitcoin || bill.paidInBitcoin {
            trackedKeys.insert(bill.groupingKey)
        }

        var latest: [String: BillSource] = [:]
        for bill in bills {
            guard trackedKeys.contains(bill.groupingKey) else { continue }
            if let existing = latest[bill.groupingKey], let existingDue = existing.dueDate, let due = bill.dueDate {
                if due > existingDue { latest[bill.groupingKey] = bill }
            } else if latest[bill.groupingKey] == nil {
                latest[bill.groupingKey] = bill
            } else if latest[bill.groupingKey]?.dueDate == nil, bill.dueDate != nil {
                latest[bill.groupingKey] = bill
            }
        }

        return latest.values.compactMap { bill in
            let name = bill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let dueDay = calendar.component(.day, from: bill.dueDate ?? Date())
            return Template(
                name: name,
                amount: bill.amount,
                dueDay: dueDay,
                seriesId: bill.seriesId,
                category: bill.category
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func dueDate(inMonth monthStart: Date, day: Int, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: monthStart)
        let range = calendar.range(of: .day, in: .month, for: monthStart)
        let clamped = min(max(day, 1), range?.count ?? 28)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: clamped)) ?? monthStart
    }

    static func amountsClose(_ a: Decimal, _ b: Decimal) -> Bool {
        let magA = a.magnitude
        let magB = b.magnitude
        let diff = abs(magA - magB)
        if diff <= 1 { return true }
        let base = max(magA, magB)
        guard base > 0 else { return diff == 0 }
        return diff / base <= Decimal(string: "0.02") ?? 0.02
    }

    static func matchingIndex(
        template: Template,
        in candidates: [LedgerCandidate],
        used: Set<Int>,
        monthStart: Date,
        monthEnd: Date,
        calendar: Calendar = .current
    ) -> Int? {
        let nameNorm = StatementImportMatching.normalizeTitle(template.name)
        var ranked: [(index: Int, score: Int)] = []

        for (idx, row) in candidates.enumerated() {
            guard !used.contains(idx) else { continue }
            guard row.date >= monthStart && row.date < monthEnd else { continue }

            var score = 0
            if let series = template.seriesId, series == row.billSeriesId {
                score += 100
            }
            if StatementImportMatching.normalizeTitle(row.billName ?? "") == nameNorm, !nameNorm.isEmpty {
                score += 80
            }
            if nameNorm.count >= 3, StatementImportMatching.normalizeTitle(row.title).contains(nameNorm) {
                score += 60
            }
            let categoryMatch: Bool = {
                guard let cat = template.category, !cat.isEmpty else { return false }
                return (row.category ?? "").caseInsensitiveCompare(cat) == .orderedSame
            }()
            if categoryMatch && amountsClose(row.usd, template.amount) {
                score += 40
            }
            if amountsClose(row.usd, template.amount) {
                score += 15
            }
            if score >= 50 {
                ranked.append((idx, score))
            }
        }

        return ranked.max(by: { $0.score < $1.score })?.index
    }

    static func monthAmount(
        template: Template,
        dueDate: Date,
        actual: LedgerCandidate?,
        historicalPrice: Decimal?,
        currentPrice: Decimal
    ) -> MonthAmount? {
        if let actual {
            let usd = actual.usd.magnitude
            let price: Decimal = {
                if let stored = actual.price, stored > 0 { return stored }
                if let hist = historicalPrice, hist > 0 { return hist }
                return currentPrice
            }()
            let btc: Decimal = {
                if let stored = actual.btc, stored > 0 { return stored.magnitude }
                guard price > 0 else { return 0 }
                return usd / price
            }()
            return MonthAmount(usd: usd, btc: btc, price: price, isEstimate: false)
        }

        guard template.amount > 0 else { return nil }
        let price = (historicalPrice ?? 0) > 0 ? (historicalPrice ?? 0) : currentPrice
        guard price > 0 else { return nil }
        let usd = template.amount.magnitude
        return MonthAmount(usd: usd, btc: usd / price, price: price, isEstimate: true)
    }

    static func shareTitle(billNames: [String]) -> String {
        let names = billNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.count == 1 { return "\(names[0]) USD vs BTC" }
        if names.count == 2 { return "\(names[0]) & \(names[1]) USD vs BTC" }
        if names.count > 2 { return "Bills USD vs BTC" }
        return "USD vs BTC"
    }

    static func shareHeadlineName(from title: String) -> String {
        let suffix = " USD vs BTC"
        if title.hasSuffix(suffix) {
            let name = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return title
    }

    /// Positive `percentLess` means later payments used less Bitcoin than earlier ones.
    struct BitcoinSpendChange: Equatable {
        var percentLess: Decimal
        var years: Int
        var monthCount: Int
    }

    static func bitcoinSpendChange(btcAmounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        let values = btcAmounts.filter { $0 > 0 }
        guard values.count >= 6 else { return nil }
        let window = min(12, max(3, values.count / 4))
        let first = Array(values.prefix(window))
        let last = Array(values.suffix(window))
        let firstAvg = first.reduce(0, +) / Decimal(first.count)
        let lastAvg = last.reduce(0, +) / Decimal(last.count)
        guard firstAvg > 0 else { return nil }
        let years = max(1, Int((Double(max(monthCount, 1)) / 12.0).rounded()))
        return BitcoinSpendChange(
            percentLess: (firstAvg - lastAvg) / firstAvg,
            years: years,
            monthCount: monthCount
        )
    }
}
