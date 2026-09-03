import Foundation

enum BillBtcBacktest {
    struct Template: Equatable {
        var name: String
        var amount: Decimal
        var dueDay: Int
        var seriesId: UUID?
        var category: String?
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
}
