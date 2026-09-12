import Foundation

enum BillBtcBacktest {
    struct Template: Equatable {
        var name: String
        var amount: Decimal
        var dueDay: Int
        var seriesId: UUID?
        var category: String?
    }

    struct BillSource: Equatable {
        var groupingKey: String
        var name: String
        var amount: Decimal
        var dueDate: Date?
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

    static func hasUsdAndBitcoinPayment(isCredit: Bool, usdAmount: Decimal, btcAmount: Decimal) -> Bool {
        !isCredit && usdAmount > 0 && btcAmount > 0
    }

    static func isTrackedBitcoinPayment(
        isCredit: Bool,
        usdAmount: Decimal,
        btcAmount: Decimal,
        paysFromBitcoinWallet: Bool
    ) -> Bool {
        guard !isCredit else { return false }
        if usdAmount > 0 && btcAmount > 0 { return true }
        if paysFromBitcoinWallet && (usdAmount > 0 || btcAmount > 0) { return true }
        return false
    }

    static func isUsdBillPaidInBitcoin(isCredit: Bool, usdAmount: Decimal, btcAmount: Decimal) -> Bool {
        hasUsdAndBitcoinPayment(isCredit: isCredit, usdAmount: usdAmount, btcAmount: btcAmount)
            || (!isCredit && btcAmount > 0)
    }

    /// BTC to store when a dollar bill is marked paid from a Bitcoin wallet.
    static func btcFilledFromUsd(usd: Decimal, satsAmount: Decimal?, btcUsdRate: Decimal) -> (btc: Decimal, price: Decimal)? {
        if let sats = satsAmount, sats > 0 {
            let btc = sats / 100_000_000
            guard btc > 0 else { return nil }
            let price = usd > 0 ? usd / btc : btcUsdRate
            return (btc, price > 0 ? price : btcUsdRate)
        }
        guard usd > 0, btcUsdRate > 0 else { return nil }
        return (usd / btcUsdRate, btcUsdRate)
    }

    /// Ignore stored BTC that is clearly the wrong unit versus USD ÷ that month’s price.
    static func isPlausibleActualBtc(_ stored: Decimal, estimated: Decimal) -> Bool {
        guard stored > 0, estimated > 0 else { return false }
        let ratio = stored / estimated
        return ratio >= Decimal(string: "0.25")! && ratio <= 4
    }

    static func groupingKey(seriesId: UUID?, billId: UUID?, objectURI: String) -> String {
        seriesId?.uuidString ?? billId?.uuidString ?? objectURI
    }

    static func paymentDisplayTitle(title: String, billName: String?, notes: String? = nil) -> String {
        if let preferred = ImportTitleRewriteStore.rewrite(for: title)?.preferredTitle {
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let payee = StrikeCSVParser.originalPayee(from: notes),
           let preferred = ImportTitleRewriteStore.rewrite(for: payee)?.preferredTitle {
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let linked = (billName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !linked.isEmpty { return linked }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One template per bill name: latest amount in the series.
    static func templates(from bills: [BillSource], calendar: Calendar = .current) -> [Template] {
        var latest: [String: BillSource] = [:]
        for bill in bills {
            let name = bill.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, bill.amount > 0 else { continue }
            if let existing = latest[bill.groupingKey], let existingDue = existing.dueDate, let due = bill.dueDate {
                if due > existingDue { latest[bill.groupingKey] = bill }
            } else if latest[bill.groupingKey] == nil {
                latest[bill.groupingKey] = bill
            } else if latest[bill.groupingKey]?.dueDate == nil, bill.dueDate != nil {
                latest[bill.groupingKey] = bill
            }
        }

        let latestTemplates = latest.values.map { bill -> Template in
            Template(
                name: bill.name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: bill.amount,
                dueDay: calendar.component(.day, from: bill.dueDate ?? Date()),
                seriesId: bill.seriesId,
                category: bill.category
            )
        }
        let uniqueByName = Dictionary(grouping: latestTemplates, by: \.name).values.compactMap { group in
            group.max(by: { $0.amount < $1.amount })
        }
        return uniqueByName.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            let displayName = paymentDisplayTitle(title: row.title, billName: row.billName)
            if nameNorm.count >= 3, StatementImportMatching.normalizeTitle(displayName) == nameNorm {
                score += 80
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
                // Strike bill pay: payee often differs, but same category + dollar invoice + sats.
                if categoryMatch, (row.btc ?? 0) > 0 {
                    score += 45
                }
            }
            if score >= 50 {
                ranked.append((idx, score))
            }
        }

        return ranked.max(by: { $0.score < $1.score })?.index
    }

    /// True when a debit with stored sats matches this bill (Strike bill pay, linked or by name/amount).
    static func hasBitcoinPayment(template: Template, in candidates: [LedgerCandidate]) -> Bool {
        matchingIndex(
            template: template,
            in: candidates.filter { ($0.btc ?? 0) > 0 },
            used: [],
            monthStart: .distantPast,
            monthEnd: .distantFuture
        ) != nil
    }

    static func bitcoinPaidTemplates(from templates: [Template], candidates: [LedgerCandidate]) -> [Template] {
        let btcCandidates = candidates.filter { ($0.btc ?? 0) > 0 }
        var used = Set<Int>()
        var paid: [Template] = []
        for template in templates {
            guard let idx = matchingIndex(
                template: template,
                in: btcCandidates,
                used: used,
                monthStart: .distantPast,
                monthEnd: .distantFuture
            ) else { continue }
            used.insert(idx)
            paid.append(template)
        }
        for template in templates where !paid.contains(where: { $0.name == template.name }) {
            let uniqueAmount = templates.filter { amountsClose($0.amount, template.amount) }.count == 1
            guard uniqueAmount else { continue }
            guard let idx = btcCandidates.enumerated().first(where: { index, row in
                !used.contains(index) && amountsClose(row.usd, template.amount)
            })?.offset else { continue }
            used.insert(idx)
            paid.append(template)
        }
        return paid.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func satsNeeded(usd: Decimal, btcUsdPrice: Decimal) -> Decimal {
        guard btcUsdPrice > 0 else { return 0 }
        return usd / btcUsdPrice
    }

    /// Matched months prefer the real payment; unmatched months use the current bill average × that month’s BTC-USD price.
    static func monthAmount(
        template: Template,
        dueDate: Date,
        actual: LedgerCandidate?,
        historicalPrice: Decimal?,
        currentPrice: Decimal,
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackStart _: Date? = nil
    ) -> MonthAmount? {
        _ = now
        let billUsd: Decimal = {
            if let actual, actual.usd > 0 { return actual.usd }
            return template.amount.magnitude
        }()
        guard billUsd > 0 else { return nil }

        let price: Decimal? = {
            if let hist = historicalPrice, hist > 0 { return hist }
            if let stored = actual?.price, stored > 0 { return stored }
            let fallback = fallbackBtcUsd(on: dueDate, calendar: calendar)
            if fallback > 0 { return fallback }
            return currentPrice > 0 ? currentPrice : nil
        }()
        guard let price, price > 0 else { return nil }

        let estimated = satsNeeded(usd: billUsd, btcUsdPrice: price)
        let stored = actual?.btc ?? 0
        let useActual = isPlausibleActualBtc(stored, estimated: estimated)
        return MonthAmount(
            usd: billUsd,
            btc: useActual ? stored : estimated,
            price: price,
            isEstimate: actual == nil
        )
    }

    static let fallbackBtcUsdByYear: [Int: Decimal] = [
        2013: Decimal(string: "150")!,
        2014: Decimal(string: "550")!,
        2015: Decimal(string: "270")!,
        2016: Decimal(string: "570")!,
        2017: Decimal(string: "2500")!,
        2018: Decimal(string: "7500")!,
        2019: Decimal(string: "5200")!,
        2020: Decimal(string: "11000")!,
        2021: Decimal(string: "35000")!,
        2022: Decimal(string: "28000")!,
        2023: Decimal(string: "28000")!,
        2024: Decimal(string: "64000")!,
        2025: Decimal(string: "95000")!,
        2026: Decimal(string: "100000")!
    ]

    static func fallbackBtcUsd(on date: Date, calendar: Calendar = .current) -> Decimal {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let knownYears = fallbackBtcUsdByYear.keys.sorted()
        guard let firstYear = knownYears.first, let lastYear = knownYears.last else { return 0 }
        let startYear = min(max(year, firstYear), lastYear)
        let start = fallbackBtcUsdByYear[startYear] ?? 0
        let next = fallbackBtcUsdByYear[startYear + 1] ?? (start * Decimal(string: "1.2")!)
        let fraction = Decimal(month - 1) / 12
        return start + (next - start) * fraction
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
    static let minMatchedMonths = 6

    enum LookbackPreset: Int, CaseIterable, Identifiable {
        case oneYear = 12
        case threeYears = 36
        case fiveYears = 60
        case max = 96

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .oneYear: return "1Y"
            case .threeYears: return "3Y"
            case .fiveYears: return "5Y"
            case .max: return "Max"
            }
        }

        static let `default` = LookbackPreset.fiveYears

        /// Snaps leftover slider values to the nearest preset. Ties prefer the longer window (old 48-month default → 5Y).
        static func fromStoredMonths(_ months: Int) -> LookbackPreset {
            guard months >= minLookbackMonths else { return .fiveYears }
            return allCases.min { a, b in
                let da = abs(a.rawValue - months)
                let db = abs(b.rawValue - months)
                if da != db { return da < db }
                return a.rawValue > b.rawValue
            } ?? .fiveYears
        }
    }

    static func clampLookbackMonths(_ months: Int) -> Int {
        min(maxSliderLookbackMonths, max(minLookbackMonths, months))
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

    static func smoothingWindow(monthCount: Int) -> Int {
        min(12, max(3, monthCount / 4))
    }

    static func rollingAverage(_ values: [Decimal], window: Int) -> [Decimal] {
        guard window > 0, !values.isEmpty else { return values }
        return values.indices.map { index in
            let start = max(0, index - window + 1)
            let slice = values[start...index].filter { $0 > 0 }
            guard !slice.isEmpty else { return 0 }
            return slice.reduce(0, +) / Decimal(slice.count)
        }
    }

    struct IndexedAverageLine: Equatable {
        var dates: [Date]
        var sats: [Double]
    }

    struct ChartKeyItem: Identifiable, Equatable {
        var name: String
        var monthlyUsd: Decimal
        var percentLess: Decimal
        var actualMonths: Int
        var id: String { name }
    }

    static func chartKeyItems(from bills: [UsdBtcBillSeries]) -> [ChartKeyItem] {
        bills.compactMap { bill in
            guard let line = indexedAverageLine(from: bill.months) else { return nil }
            guard let first = line.sats.first(where: { $0 > 0 }), first > 0 else { return nil }
            let last = line.sats.last ?? first
            let percentLess = Decimal((first - last) / first)
            let averages = trailingAverages(
                usdAmounts: bill.months.map(\.usdExpenses),
                btcAmounts: bill.months.map(\.btcAmount)
            )
            return ChartKeyItem(
                name: bill.name,
                monthlyUsd: averages?.monthlyUsd ?? bill.months.last?.usdExpenses ?? 0,
                percentLess: percentLess,
                actualMonths: bill.months.filter { !$0.isEstimate }.count
            )
        }
    }

    static func orderedBills(_ bills: [UsdBtcBillSeries], by names: [String]) -> [UsdBtcBillSeries] {
        let lookup = Dictionary(uniqueKeysWithValues: bills.map { ($0.name, $0) })
        let ordered = names.compactMap { lookup[$0] }
        let leftover = bills.filter { bill in !names.contains(bill.name) }
        return ordered + leftover
    }

    static func orderedNames(_ names: [String], by order: [String]) -> [String] {
        let known = order.filter { names.contains($0) }
        let unknown = names.filter { !order.contains($0) }
        return known + unknown
    }

    static func indexedAverageLine(from points: [UsdBtcMonthPoint], window: Int? = nil) -> IndexedAverageLine? {
        guard points.count > 1 else { return nil }
        let resolvedWindow = window ?? smoothingWindow(monthCount: points.count)
        return IndexedAverageLine(
            dates: points.map(\.month),
            sats: rollingAverage(points.map(\.btcAmount), window: resolvedWindow).map { satsValue(fromBTC: $0) }
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

    static func satsCaption(_ sats: Double) -> String {
        "\(compactSats(sats)) sats"
    }

    static func bitcoinCaption(fromSats sats: Double) -> String {
        compactBitcoin(Decimal(sats) / 100_000_000)
    }

    static func compactBitcoinAxis(_ sats: Double) -> String {
        let caption = bitcoinCaption(fromSats: sats)
        if caption.hasSuffix(" BTC") {
            return String(caption.dropLast(4))
        }
        return caption
    }

    struct ThenNowSnapshot: Equatable {
        var thenLabel: String
        var thenSats: Double
        var nowSats: Double
        var monthlyUsd: Decimal
    }

    static func thenNow(from bills: [UsdBtcBillSeries]) -> ThenNowSnapshot? {
        let combined = combinedBillSeries(from: bills)
        return thenNow(from: combined)
    }

    static func thenNow(from report: UsdBtcReportData) -> ThenNowSnapshot? {
        thenNow(from: combinedMonthlySeries(from: report))
    }

    static func thenNow(from bill: UsdBtcBillSeries) -> ThenNowSnapshot? {
        guard let line = indexedAverageLine(from: bill.months),
              let first = line.sats.first, first > 0,
              let last = line.sats.last,
              let firstDate = line.dates.first else { return nil }
        let averages = trailingAverages(
            usdAmounts: bill.months.map(\.usdExpenses),
            btcAmounts: bill.months.map(\.btcAmount)
        )
        return ThenNowSnapshot(
            thenLabel: String(Calendar.current.component(.year, from: firstDate)),
            thenSats: first,
            nowSats: last,
            monthlyUsd: averages?.monthlyUsd ?? bill.months.last?.usdExpenses ?? 0
        )
    }

    static func compactBitcoin(_ btc: Decimal) -> String {
        let value = abs((btc as NSDecimalNumber).doubleValue)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = value >= 1 ? 2 : 4
        formatter.maximumFractionDigits = value >= 0.01 ? 4 : 6
        let number = formatter.string(from: NSNumber(value: value)) ?? "0"
        return "\(number) BTC"
    }

    static func percentPoints(_ percentLess: Decimal) -> Int {
        Int((abs((percentLess as NSDecimalNumber).doubleValue) * 100).rounded())
    }

    static func lessBitcoinCaption(percentLess: Decimal, billCount: Int = 1) -> String {
        let noun = billCount == 1 ? "bill" : "bills"
        return percentLess >= 0
            ? "less Bitcoin to pay the same \(noun)"
            : "more Bitcoin to pay the same \(noun)"
    }

    static func sameDollarsCaption(billCount: Int) -> String {
        billCount <= 1 ? "Same bill. Less Bitcoin." : "Same bills. Less Bitcoin."
    }

    static func storyHeadline(percentLess: Decimal, billCount: Int) -> String {
        let percent = percentPoints(percentLess)
        let noun = billCount <= 1 ? "bill" : "bills"
        let word = percentLess >= 0 ? "less" : "more"
        return "Same \(noun). \(percent)% \(word) Bitcoin."
    }

    static func actualDataCaption(actualMonths: Int) -> String {
        if actualMonths <= 0 { return "Backtest" }
        if actualMonths == 1 { return "1 mo actual" }
        return "\(actualMonths) mo actual"
    }

    static func lookbackDataStatus(actualMonths: Int) -> String {
        if actualMonths > 0 {
            return "Using your actual payments + historical Bitcoin prices"
        }
        return "Backtested with your current averages + historical prices"
    }

    static func backtestMonthSpan(from dates: [Date], calendar: Calendar = .current) -> Int {
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        let months = calendar.dateComponents([.month], from: first, to: last).month ?? 0
        return max(months + 1, 1)
    }

    static func backtestCaption(monthCount: Int) -> String {
        let years = max(monthCount, 0) / 12
        if years <= 0 { return "Backtest" }
        if years == 1 { return "Backtest 1 year" }
        return "Backtest \(years) years"
    }

    static func shareChartFooter(on date: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Bitcoin Deflation Chart · \(formatter.string(from: date))"
    }

    static let historicalDisclaimer =
        "Not financial advice. Not a wallet."

    static let shareDisclaimer =
        "Paid via Strike. Not financial advice. Not a wallet."

    static func satsValue(fromBTC btc: Decimal) -> Double {
        (btc as NSDecimalNumber).doubleValue * 100_000_000
    }

    struct BitcoinQuote: Equatable {
        var text: String
        var attribution: String
    }

    static let bitcoinQuotes: [BitcoinQuote] = [
        BitcoinQuote(
            text: "The root problem with conventional currency is all the trust that's required to make it work.",
            attribution: "Satoshi Nakamoto"
        ),
        BitcoinQuote(
            text: "Lost coins only make everyone else's coins worth slightly more.",
            attribution: "Satoshi Nakamoto"
        ),
        BitcoinQuote(
            text: "If you don't believe me or don't get it, I don't have time to try to convince you, sorry.",
            attribution: "Satoshi Nakamoto"
        ),
        BitcoinQuote(
            text: "It might make sense just to get some in case it catches on.",
            attribution: "Satoshi Nakamoto"
        ),
        BitcoinQuote(
            text: "We have proposed a system for electronic transactions without relying on trust.",
            attribution: "Satoshi Nakamoto"
        ),
        BitcoinQuote(
            text: "The Times 03/Jan/2009 Chancellor on brink of second bailout for banks.",
            attribution: "Genesis block"
        ),
        BitcoinQuote(
            text: "Don't trust, verify.",
            attribution: "Bitcoin"
        ),
        BitcoinQuote(
            text: "Not your keys, not your coins.",
            attribution: "Bitcoin"
        ),
        BitcoinQuote(
            text: "Fix the money, fix the world.",
            attribution: "Bitcoin"
        ),
        BitcoinQuote(
            text: "Stay humble. Stack sats.",
            attribution: "Bitcoin"
        ),
        BitcoinQuote(
            text: "21 million. Forever.",
            attribution: "Bitcoin"
        ),
        BitcoinQuote(
            text: "Sound money. Same bills.",
            attribution: "Bills & Balance"
        )
    ]

    static func randomBitcoinQuote() -> BitcoinQuote {
        bitcoinQuotes.randomElement() ?? bitcoinQuotes[0]
    }

    /// Splits a quote near the midpoint so two centered lines stay close in length.
    static func twoLineQuote(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 4 else { return text }
        let total = words.joined(separator: " ").count
        var bestIndex = max(1, words.count / 2)
        var bestScore = Int.max
        var running = 0
        for i in 0..<(words.count - 1) {
            running += words[i].count + (i == 0 ? 0 : 1)
            var score = abs(running * 2 - total)
            if words[i].hasSuffix(",") || words[i].hasSuffix(".") {
                score -= 4
            }
            if score < bestScore {
                bestScore = score
                bestIndex = i + 1
            }
        }
        let first = words[..<bestIndex].joined(separator: " ")
        let second = words[bestIndex...].joined(separator: " ")
        return "\(first)\n\(second)"
    }

    static func sharePunchline(billName: String) -> String {
        sharePunchline(billNames: [billName])
    }

    static func sharePunchline(billNames: [String]) -> String {
        let names = billNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.count == 1 { return "Same \(names[0]). Less Bitcoin." }
        if names.count > 1 { return "Same bills. Less Bitcoin." }
        return "Same bill. Less Bitcoin."
    }

    struct BitcoinSpendChange: Equatable {
        var percentLess: Decimal
        var years: Int
        var monthCount: Int
    }

    static func spendChange(amounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        let values = amounts.filter { $0 > 0 }
        guard values.count >= minMatchedMonths else { return nil }
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

    static func storyChange(from report: UsdBtcReportData) -> BitcoinSpendChange? {
        headlineSpendChange(
            btcAmounts: report.months.map(\.btcAmount),
            monthCount: max(report.months.count, report.monthsBack)
        )
    }

    static func hasEnoughBacktestData(from report: UsdBtcReportData) -> Bool {
        !report.bills.isEmpty && report.actualMonths >= minMatchedMonths
    }

    static func combinedMonthlySeries(from report: UsdBtcReportData) -> UsdBtcBillSeries {
        let name = report.bills.count == 1 ? (report.bills.first?.name ?? "Bill") : "Monthly bills"
        return UsdBtcBillSeries(
            name: name,
            months: report.months,
            totalUsd: report.totalUsd,
            totalBtcAtTime: report.totalBtcAtTime,
            totalBtcValueNow: report.totalBtcValueNow
        )
    }

    static func combinedBillSeries(from bills: [UsdBtcBillSeries]) -> UsdBtcBillSeries {
        if bills.count == 1, let only = bills.first { return only }
        let combined = combinedSeries(from: bills)
        let dates = Array(Set(bills.flatMap { $0.months.map(\.month) })).sorted()
        let months = zip(dates, zip(combined.usd, combined.btc)).map { date, pair in
            UsdBtcMonthPoint(
                month: date,
                usdExpenses: pair.0,
                btcAtTime: pair.1,
                btcValueNow: 0,
                btcAmount: pair.1,
                avgBtcPrice: 0,
                isEstimate: false
            )
        }
        return UsdBtcBillSeries(
            name: bills.count <= 1 ? (bills.first?.name ?? "Bill") : "Bills",
            months: months,
            totalUsd: combined.usd.reduce(0, +),
            totalBtcAtTime: combined.btc.reduce(0, +),
            totalBtcValueNow: 0
        )
    }

    static func windowed(_ report: UsdBtcReportData, monthsBack: Int) -> UsdBtcReportData {
        let limit = clampLookbackMonths(monthsBack)
        let months = Array(report.months.suffix(limit))
        let start = months.first?.month
        let bills = report.bills.compactMap { bill -> UsdBtcBillSeries? in
            let points = start.map { startDate in bill.months.filter { $0.month >= startDate } } ?? bill.months
            guard !points.isEmpty else { return nil }
            return UsdBtcBillSeries(
                name: bill.name,
                months: points,
                totalUsd: points.reduce(0) { $0 + $1.usdExpenses },
                totalBtcAtTime: points.reduce(0) { $0 + $1.btcAmount },
                totalBtcValueNow: points.reduce(0) { $0 + $1.btcValueNow }
            )
        }
        return UsdBtcReportData(
            months: months,
            bills: bills,
            totalUsd: months.reduce(0) { $0 + $1.usdExpenses },
            totalBtcAtTime: months.reduce(0) { $0 + $1.btcAmount },
            totalBtcValueNow: months.reduce(0) { $0 + $1.btcValueNow },
            monthsBack: limit,
            trackedBillNames: report.trackedBillNames,
            estimatedMonths: months.filter(\.isEstimate).count,
            actualMonths: months.filter { !$0.isEstimate }.count
        )
    }

    static func headlineSpendChange(btcAmounts: [Decimal], monthCount: Int) -> BitcoinSpendChange? {
        let values = btcAmounts.filter { $0 > 0 }
        guard values.count >= minMatchedMonths, let first = values.first, first > 0, let last = values.last else { return nil }
        let years = max(1, Int((Double(max(monthCount, 1)) / 12.0).rounded()))
        return BitcoinSpendChange(
            percentLess: (first - last) / first,
            years: years,
            monthCount: monthCount
        )
    }

    static func storyAverages(from report: UsdBtcReportData) -> MonthlyAverages? {
        trailingAverages(
            usdAmounts: report.months.map(\.usdExpenses),
            btcAmounts: report.months.map(\.btcAmount)
        )
    }

    static func combinedSeries(from bills: [UsdBtcBillSeries]) -> (usd: [Decimal], btc: [Decimal], monthCount: Int) {
        let dates = Array(Set(bills.flatMap { $0.months.map(\.month) })).sorted()
        let usd = dates.map { date in
            bills.reduce(Decimal(0)) { partial, bill in
                partial + (bill.months.first(where: { $0.month == date })?.usdExpenses ?? 0)
            }
        }
        let btc = dates.map { date in
            bills.reduce(Decimal(0)) { partial, bill in
                partial + (bill.months.first(where: { $0.month == date })?.btcAmount ?? 0)
            }
        }
        return (usd, btc, dates.count)
    }

    static func storyChange(bills: [UsdBtcBillSeries], monthsBack: Int) -> BitcoinSpendChange? {
        let series = combinedSeries(from: bills)
        return headlineSpendChange(btcAmounts: series.btc, monthCount: max(series.monthCount, monthsBack))
    }

    static func storyAverages(bills: [UsdBtcBillSeries]) -> MonthlyAverages? {
        let series = combinedSeries(from: bills)
        return trailingAverages(usdAmounts: series.usd, btcAmounts: series.btc)
    }

    static func changeSentence(_ change: BitcoinSpendChange) -> String {
        let percent = percentPoints(change.percentLess)
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
        if abs((change.percentLess as NSDecimalNumber).doubleValue) < 0.005 {
            return "0%"
        }
        let percent = percentPoints(change.percentLess)
        if change.percentLess >= 0 {
            return "−\(percent)%"
        }
        return "+\(percent)%"
    }
}
