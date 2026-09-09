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
        currentPrice: Decimal,
        now: Date = Date(),
        calendar: Calendar = .current
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
        guard let hist = historicalPrice, hist > 0 else { return nil }
        let usd = inflationAdjustedUsd(template.amount.magnitude, on: dueDate, now: now, calendar: calendar)
        return MonthAmount(usd: usd, btc: usd / hist, price: hist, isEstimate: true)
    }

    /// Annual CPI-U (1982-84=100). Years after the table grow at 3%.
    static let cpiYearIndex: [Int: Decimal] = [
        2013: Decimal(string: "232.957")!,
        2014: Decimal(string: "236.736")!,
        2015: Decimal(string: "237.017")!,
        2016: Decimal(string: "240.007")!,
        2017: Decimal(string: "245.120")!,
        2018: Decimal(string: "251.107")!,
        2019: Decimal(string: "255.657")!,
        2020: Decimal(string: "258.811")!,
        2021: Decimal(string: "270.970")!,
        2022: Decimal(string: "292.655")!,
        2023: Decimal(string: "304.702")!,
        2024: Decimal(string: "313.689")!,
        2025: Decimal(string: "322.1")!,
        2026: Decimal(string: "329.0")!
    ]

    static func cpiIndex(on date: Date, calendar: Calendar = .current) -> Decimal {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let knownYears = cpiYearIndex.keys.sorted()
        guard let firstYear = knownYears.first, let lastYear = knownYears.last else { return 1 }
        let startYear = min(max(year, firstYear), lastYear)
        let start = cpiYearIndex[startYear] ?? 1
        let next: Decimal = {
            if let listed = cpiYearIndex[startYear + 1] { return listed }
            return start * Decimal(string: "1.03")!
        }()
        let fraction = Decimal(month - 1) / 12
        return start + (next - start) * fraction
    }

    /// Scales a current payment back to `date` using CPI so estimated USD isn't a flat line.
    static func inflationAdjustedUsd(_ amount: Decimal, on date: Date, now: Date = Date(), calendar: Calendar = .current) -> Decimal {
        let thenCpi = cpiIndex(on: date, calendar: calendar)
        let nowCpi = cpiIndex(on: now, calendar: calendar)
        guard nowCpi > 0, thenCpi > 0 else { return amount }
        return amount * thenCpi / nowCpi
    }

    static func shareTitle(billNames: [String]) -> String {
        let names = billNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.count == 1 { return "\(names[0]) USD vs BTC" }
        if names.count == 2 { return "\(names[0]) & \(names[1]) USD vs BTC" }
        if names.count > 2 { return "\(names.joined(separator: ", ")) USD vs BTC" }
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

    static let minLookbackMonths = 12
    static let maxSliderLookbackMonths = 96
    static let bitcoinHistoryStartComponents = DateComponents(year: 2013, month: 4, day: 1)

    static func clampLookbackMonths(_ months: Int) -> Int {
        min(maxSliderLookbackMonths, max(minLookbackMonths, months))
    }

    static func isFullHistoryLookback(_ months: Int) -> Bool {
        months > maxSliderLookbackMonths
    }

    static func monthsSince2013(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let start = calendar.date(from: bitcoinHistoryStartComponents) else {
            return maxSliderLookbackMonths
        }
        let months = calendar.dateComponents([.month], from: start, to: now).month ?? maxSliderLookbackMonths
        return max(maxSliderLookbackMonths, months)
    }

    static func resolvedLookbackMonths(_ months: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        if isFullHistoryLookback(months) {
            return monthsSince2013(now: now, calendar: calendar)
        }
        return clampLookbackMonths(months)
    }

    struct MonthlyAverages: Equatable {
        var monthlyUsd: Decimal
        var monthlyBtc: Decimal
        var monthCount: Int
    }

    static func monthlyAverages(usdAmounts: [Decimal], btcAmounts: [Decimal]) -> MonthlyAverages? {
        let pairs = zip(usdAmounts, btcAmounts).filter { $0.0 > 0 || $0.1 > 0 }
        guard !pairs.isEmpty else { return nil }
        let count = Decimal(pairs.count)
        return MonthlyAverages(
            monthlyUsd: pairs.map(\.0).reduce(0, +) / count,
            monthlyBtc: pairs.map(\.1).reduce(0, +) / count,
            monthCount: pairs.count
        )
    }

    static func plotMax(_ values: [Double]) -> Double {
        max((values.max() ?? 1) * 1.08, 1)
    }

    static func compactUsd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = abs(value) >= 100 ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func compactSats(_ sats: Double) -> String {
        if sats >= 1_000_000 {
            let millions = sats / 1_000_000
            return String(format: millions >= 10 ? "%.0fM" : "%.1fM", millions)
        }
        if sats >= 10_000 {
            return String(format: "%.0fk", sats / 1_000)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }

    static func satsValue(fromBTC btc: Decimal) -> Double {
        (btc as NSDecimalNumber).doubleValue * 100_000_000
    }

    static func sharePunchline(billName: String) -> String {
        let name = billName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Same bill. Fewer sats." }
        return "Same \(name). Fewer sats."
    }

    struct IndexedPoint: Equatable {
        var usd: Double
        var sats: Double
    }

    /// Both series start at 100 using the first month with a positive USD and BTC amount.
    static func indexedSeries(usdAmounts: [Decimal], btcAmounts: [Decimal]) -> [IndexedPoint] {
        guard usdAmounts.count == btcAmounts.count, usdAmounts.count > 1 else { return [] }
        let usdVals = usdAmounts.map { ($0 as NSDecimalNumber).doubleValue }
        let satsVals = btcAmounts.map { ($0 as NSDecimalNumber).doubleValue }
        guard let base = zip(usdVals, satsVals).first(where: { $0.0 > 0 && $0.1 > 0 }) else { return [] }
        let usdBase = base.0
        let satsBase = base.1
        return zip(usdVals, satsVals).map { usd, sats in
            IndexedPoint(usd: usd / usdBase * 100, sats: sats / satsBase * 100)
        }
    }

    /// Inclusive start / exclusive end for consecutive estimated months.
    static func estimateBands(dates: [Date], estimates: [Bool], calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        guard dates.count == estimates.count, !dates.isEmpty else { return [] }
        var bands: [(Date, Date)] = []
        var bandStart: Date?
        for index in dates.indices {
            if estimates[index] {
                if bandStart == nil { bandStart = dates[index] }
            } else if let start = bandStart {
                bands.append((start, dates[index]))
                bandStart = nil
            }
        }
        if let start = bandStart, let last = dates.last {
            let end = calendar.date(byAdding: .month, value: 1, to: last) ?? last
            bands.append((start, end))
        }
        return bands
    }

    /// A month is estimated when every series that has that month is an estimate (or none have actuals).
    static func combinedEstimates(dates: [[Date]], estimates: [[Bool]], axis: [Date]) -> [Bool] {
        axis.map { date in
            var sawActual = false
            var sawAny = false
            for index in dates.indices {
                guard let monthIndex = dates[index].firstIndex(of: date) else { continue }
                sawAny = true
                if !estimates[index][monthIndex] {
                    sawActual = true
                }
            }
            return sawAny ? !sawActual : true
        }
    }

    /// Positive `percentLess` means later payments used less Bitcoin than earlier ones.
    struct BitcoinSpendChange: Equatable {
        var percentLess: Decimal
        var years: Int
        var monthCount: Int
    }

    static func spendChange(amounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        let values = amounts.filter { $0 > 0 }
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

    static func bitcoinSpendChange(btcAmounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        spendChange(amounts: btcAmounts, monthCount: monthCount)
    }

    static func usdSpendChange(usdAmounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        spendChange(amounts: usdAmounts, monthCount: monthCount)
    }

    static func changeSentence(_ change: BitcoinSpendChange) -> String {
        let percent = abs((change.percentLess * 100 as NSDecimalNumber).intValue)
        if change.percentLess >= 0 {
            return "Paid \(percent)% less Bitcoin than \(change.years) years ago"
        }
        return "Paid \(percent)% more Bitcoin than \(change.years) years ago"
    }

    static func trailingAverages(usdAmounts: [Decimal], btcAmounts: [Decimal], window: Int = 12) -> MonthlyAverages? {
        let pairs = Array(zip(usdAmounts, btcAmounts).filter { $0.0 > 0 || $0.1 > 0 }.suffix(max(window, 1)))
        guard !pairs.isEmpty else { return nil }
        let count = Decimal(pairs.count)
        return MonthlyAverages(
            monthlyUsd: pairs.map(\.0).reduce(0, +) / count,
            monthlyBtc: pairs.map(\.1).reduce(0, +) / count,
            monthCount: pairs.count
        )
    }

    static func signedPercentLabel(_ change: BitcoinSpendChange) -> String {
        let percent = abs((change.percentLess * 100 as NSDecimalNumber).intValue)
        if abs((change.percentLess as NSDecimalNumber).doubleValue) < 0.005 {
            return "0%"
        }
        if change.percentLess >= 0 {
            return "−\(percent)%"
        }
        return "+\(percent)%"
    }
}
