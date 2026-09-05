//
//  ReportsViewModel.swift
//  BillsAndBalance
//
//  Aggregates ledger data for monthly reports and year‑wrap.
//

import Foundation
import CoreData

// MARK: - Report Data Types

struct MonthlyReportData {
    var income: Decimal
    var expenses: Decimal
    var digitalWalletFees: Decimal
    var byCategory: [(name: String, amount: Decimal)]
    var trendMonths: [(month: Date, income: Decimal, expenses: Decimal)]
    /// Five weeks of spending within the month (1–7, 8–14, 15–21, 22–28, 29–end), for Activity bars.
    var weeklyBreakdown: [Decimal]
    var month: Date
}

struct YearWrapData {
    var year: Int
    var income: Decimal
    var expenses: Decimal
    var digitalWalletFees: Decimal
    var savingsRate: Decimal? // (income - expenses) / income, nil if no income
    var byCategory: [(name: String, amount: Decimal)]
    var monthlyBreakdown: [(month: Date, income: Decimal, expenses: Decimal, fees: Decimal)]
}

struct WeeklyReportData {
    var weekStart: Date
    var income: Decimal
    var expenses: Decimal
    var digitalWalletFees: Decimal
    var byCategory: [(name: String, amount: Decimal)]
    var dailyBreakdown: [(day: Date, expenses: Decimal)]
}

/// Self-contained Activity page for one week/month/year, used for Apple Card-style adjacent peek.
struct ActivityPeriodSnapshot {
    let period: ReportsViewModel.WalletPeriod
    let anchorDate: Date
    let title: String
    let income: Decimal
    let expenses: Decimal
    let digitalWalletFees: Decimal
    let previousComparableSpending: Decimal?
    let isCurrentPeriodInProgress: Bool
    let creditCardSpending: Decimal
    let byCategory: [(name: String, amount: Decimal)]

    var totalSpending: Decimal { expenses + digitalWalletFees }
    var hasActivity: Bool {
        income != 0 || expenses != 0 || digitalWalletFees != 0 || !byCategory.isEmpty
    }
}

struct UsdBtcMonthPoint: Identifiable {
    var month: Date
    var usdExpenses: Decimal
    var btcAtTime: Decimal
    var btcValueNow: Decimal
    var btcAmount: Decimal
    var avgBtcPrice: Decimal
    var isEstimate: Bool
    var id: Date { month }
}

struct UsdBtcBillSeries: Identifiable {
    var name: String
    var months: [UsdBtcMonthPoint]
    var totalUsd: Decimal
    var totalBtcAtTime: Decimal
    var totalBtcValueNow: Decimal
    var id: String { name }
}

/// USD vs Bitcoin for dollar bills paid in BTC/sats (or flagged Track in Bitcoin): actual ledger overlay, else historical-price estimate.
struct UsdBtcReportData {
    var months: [UsdBtcMonthPoint]
    var bills: [UsdBtcBillSeries]
    var totalUsd: Decimal
    var totalBtcAtTime: Decimal
    var totalBtcValueNow: Decimal
    var monthsBack: Int
    var trackedBillNames: [String]
    var estimatedMonths: Int
    var actualMonths: Int
}

/// Expense report: date range, optional account filter, list of expenses + by-category summary.
struct ExpenseReportRow: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let amount: Decimal
    let category: String
    let accountName: String
}

struct ExpenseReportData {
    var start: Date
    var end: Date
    var accountId: UUID?
    var rows: [ExpenseReportRow]
    var byCategory: [(name: String, amount: Decimal)]
    var total: Decimal
}

// MARK: - Helpers

private func isDigitalWallet(_ account: Account?) -> Bool {
    guard let account = account else { return false }
    return (account.type ?? "").lowercased() == "digital wallet"
}

// MARK: - USD Amount for Reporting

private func reportUSDAmount(for entry: LedgerEntry, account: Account, btcService: BitcoinPriceService) -> Decimal {
    let signed: Decimal
    if account.currencyCode == "BTC" {
        let usd = entry.usdAmountDecimal
        if usd != 0 {
            signed = entry.isCredit ? usd : -usd
        } else {
            let btc = entry.amountInCurrency(for: account)
            let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : btcService.btcToUsdRate
            let usdVal = btc * price
            signed = entry.isCredit ? usdVal : -usdVal
        }
    } else {
        let amt = entry.usdAmountDecimal != 0 ? entry.usdAmountDecimal : entry.amountDecimal
        signed = entry.isCredit ? amt : -amt
    }
    return signed
}

// MARK: - Digital Wallet Fee Calculation

/// Calculates the fee amount for a transaction on a digital wallet account
/// Fee is calculated as: transaction_amount * (feePercentage / 100)
private func calculateDigitalWalletFee(for entry: LedgerEntry, account: Account, btcService: BitcoinPriceService) -> Decimal {
    guard isDigitalWallet(account) else { return 0 }

    if entry.feeAmountDecimal > 0 {
        return entry.feeAmountDecimal
    }

    let fromNotes = FeeParsing.feeFromNotes(entry.notes)
    if fromNotes > 0 {
        return fromNotes
    }

    guard account.feePercentageDecimal > 0 else { return 0 }
    let transactionAmount = abs(reportUSDAmount(for: entry, account: account, btcService: btcService))
    return transactionAmount * (account.feePercentageDecimal / 100)
}

// MARK: - ReportsViewModel

@MainActor
final class ReportsViewModel: ObservableObject {
    enum WalletPeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    enum CreditCardViewMode: String, CaseIterable {
        case payments = "Payments"
        case transactions = "Transactions"
    }

    private static let lastPeriodKey = "ReportsLastWalletPeriod"
    private static let lastCreditCardViewModeKey = "ReportsLastCreditCardViewMode"
    private static let categorySortDescendingKey = "ReportsCategorySortDescending"
    private static let usdBtcBacktestEnabledKey = "ReportsUsdBtcBacktestEnabled"

    @Published var monthlyReport: MonthlyReportData?
    @Published var yearWrapReport: YearWrapData?
    @Published var weeklyReport: WeeklyReportData?
    @Published var usdBtcReport: UsdBtcReportData?
    @Published var currentPeriodSnapshot: ActivityPeriodSnapshot?
    @Published var previousPeriodSnapshot: ActivityPeriodSnapshot?
    @Published var nextPeriodSnapshot: ActivityPeriodSnapshot?
    @Published var selectedMonth: Date = Date()
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var selectedWeekStart: Date = Date()
    @Published var lastUsedWalletPeriod: WalletPeriod = .month
    @Published var creditCardViewMode: CreditCardViewMode = .transactions
    @Published var categorySortDescending: Bool = true
    @Published var usdBtcBacktestEnabled: Bool = false
    /// Number of months to include in USD vs BTC report (e.g. 48 = 4 years).
    @Published var usdBtcMonthsBack: Int = 48
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var expenseReport: ExpenseReportData?
    @Published var expenseReportStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var expenseReportEnd: Date = Date()
    @Published var expenseReportAccountId: UUID?

    private let context: NSManagedObjectContext
    private let bitcoinPriceService: BitcoinPriceService
    private let calendar = Calendar.current
    private var creditCardManager: CreditCardManager?

    init(context: NSManagedObjectContext, bitcoinPriceService: BitcoinPriceService, creditCardManager: CreditCardManager? = nil) {
        self.context = context
        self.bitcoinPriceService = bitcoinPriceService
        self.creditCardManager = creditCardManager
        if let raw = UserDefaults.standard.string(forKey: Self.lastPeriodKey),
           let p = WalletPeriod(rawValue: raw) {
            lastUsedWalletPeriod = p
        }
        if let raw = UserDefaults.standard.string(forKey: Self.lastCreditCardViewModeKey),
           let mode = CreditCardViewMode(rawValue: raw) {
            creditCardViewMode = mode
        }
        if UserDefaults.standard.object(forKey: Self.categorySortDescendingKey) != nil {
            categorySortDescending = UserDefaults.standard.bool(forKey: Self.categorySortDescendingKey)
        }
        usdBtcBacktestEnabled = UserDefaults.standard.bool(forKey: Self.usdBtcBacktestEnabledKey)
    }

    var hasActiveBitcoinDigitalWallet: Bool {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "currency == %@", "BTC")
        request.fetchLimit = 20
        let accounts = (try? context.fetch(request)) ?? []
        return accounts.contains { account in
            !account.isHiddenFlag && isDigitalWallet(account)
        }
    }

    func setCategorySortDescending(_ descending: Bool) {
        categorySortDescending = descending
        UserDefaults.standard.set(descending, forKey: Self.categorySortDescendingKey)
    }

    func setUsdBtcBacktestEnabled(_ enabled: Bool) {
        usdBtcBacktestEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.usdBtcBacktestEnabledKey)
        if enabled, hasActiveBitcoinDigitalWallet {
            Task { await loadUsdBtcReport() }
        } else if !enabled {
            usdBtcReport = nil
        }
    }
    
    func setCreditCardViewMode(_ mode: CreditCardViewMode) {
        creditCardViewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.lastCreditCardViewModeKey)
    }
    
    /// Jumps to the current period (today's week/month/year)
    func jumpToCurrentPeriod() {
        applyAnchorDate(presentPeriodAnchor())
    }

    /// Moves the selected week/month/year by `offset` periods. Ignores moves into the future.
    func shiftPeriod(_ offset: Int) {
        guard offset != 0 else { return }
        let target = adjacentAnchorDate(offset: offset)
        if offset > 0, isAnchorAfterPresentPeriod(target) { return }
        applyAnchorDate(target)
    }

    func presentPeriodAnchor() -> Date {
        let now = Date()
        switch lastUsedWalletPeriod {
        case .week:
            return startOfWeek(for: now)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        case .year:
            return calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1)) ?? now
        }
    }

    func isAnchorAfterPresentPeriod(_ date: Date) -> Bool {
        startOfPeriod(for: date) > presentPeriodAnchor()
    }

    private func startOfPeriod(for date: Date) -> Date {
        switch lastUsedWalletPeriod {
        case .week:
            return startOfWeek(for: date)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        case .year:
            return calendar.date(from: DateComponents(year: calendar.component(.year, from: date), month: 1, day: 1)) ?? date
        }
    }

    private func applyAnchorDate(_ date: Date) {
        switch lastUsedWalletPeriod {
        case .week:
            selectedWeekStart = startOfWeek(for: date)
            loadWeekReport()
        case .month:
            selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            loadMonthlyReport()
        case .year:
            selectedYear = calendar.component(.year, from: date)
            loadYearWrapReport()
        }
    }
    
    /// Checks if there's data available for a specific period
    func hasDataForPeriod(_ period: WalletPeriod, date: Date) -> Bool {
        let (start, end): (Date, Date) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: date)
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return (weekStart, weekStart)
                }
                return (weekStart, weekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart)
                }
                return (monthStart, monthEnd)
            case .year:
                let year = calendar.component(.year, from: date)
                let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
                guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                    return (yearStart, yearStart)
                }
                return (yearStart, yearEnd)
            }
        }()
        
        let entries = fetchEntries(from: start, to: end)
        return !entries.isEmpty
    }

    func currentAnchorDate() -> Date {
        switch lastUsedWalletPeriod {
        case .week:
            return startOfWeek(for: selectedWeekStart)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        case .year:
            return calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? Date()
        }
    }

    func adjacentAnchorDate(offset: Int) -> Date {
        let current = currentAnchorDate()
        switch lastUsedWalletPeriod {
        case .week:
            return calendar.date(byAdding: .day, value: 7 * offset, to: current) ?? current
        case .month:
            return calendar.date(byAdding: .month, value: offset, to: current) ?? current
        case .year:
            return calendar.date(byAdding: .year, value: offset, to: current) ?? current
        }
    }

    func periodTitle(for period: WalletPeriod, date: Date) -> String {
        switch period {
        case .week:
            let start = startOfWeek(for: date)
            guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "Week" }
            let dayMonth = DateFormatter()
            dayMonth.dateFormat = "MMM d"
            let year = DateFormatter()
            year.dateFormat = "yyyy"
            let startY = calendar.component(.year, from: start)
            let endY = calendar.component(.year, from: end)
            let startStr = startY != endY ? "\(dayMonth.string(from: start)), \(year.string(from: start))" : dayMonth.string(from: start)
            let endStr = startY != endY ? "\(dayMonth.string(from: end)), \(year.string(from: end))" : dayMonth.string(from: end)
            return "\(startStr) – \(endStr)"
        case .month:
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            return f.string(from: monthStart)
        case .year:
            return String(calendar.component(.year, from: date))
        }
    }

    func makeSnapshot(period: WalletPeriod, date: Date) -> ActivityPeriodSnapshot {
        let (start, end) = periodBounds(for: period, date: date)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]
        let entries = fetchEntries(from: start, to: end)
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            guard includeInActivity(entry) else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            if usd > 0 {
                income += usd
            } else {
                expenses += abs(usd)
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                byCategory[cat, default: 0] += abs(usd)
                if isDigitalWallet(account) {
                    let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                    if fee > 0 {
                        fees += fee
                        byCategory["Digital Wallet Fees", default: 0] += fee
                    }
                }
            }
        }
        let comparison = comparablePreviousSpending(for: period, date: date)
        return ActivityPeriodSnapshot(
            period: period,
            anchorDate: date,
            title: periodTitle(for: period, date: date),
            income: income,
            expenses: expenses,
            digitalWalletFees: fees,
            previousComparableSpending: comparison.previous,
            isCurrentPeriodInProgress: comparison.inProgress,
            creditCardSpending: creditCardSpending(for: period, date: date),
            byCategory: byCategory.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        )
    }

    /// Spending total used by both the Balance activity chip and Activity Total Spending.
    func periodSpendingTotal(for period: WalletPeriod, date: Date? = nil) -> Decimal {
        categoryBreakdownByPeriod(period: period, date: date ?? presentPeriodAnchor())
            .reduce(into: Decimal(0)) { sum, bucket in
                sum += bucket.categories.reduce(Decimal(0)) { $0 + $1.amount }
            }
    }

    func refreshAdjacentSnapshots() {
        let period = lastUsedWalletPeriod
        currentPeriodSnapshot = makeSnapshot(period: period, date: currentAnchorDate())
        previousPeriodSnapshot = makeSnapshot(period: period, date: adjacentAnchorDate(offset: -1))
        let nextDate = adjacentAnchorDate(offset: 1)
        nextPeriodSnapshot = isAnchorAfterPresentPeriod(nextDate)
            ? nil
            : makeSnapshot(period: period, date: nextDate)
    }

    func periodBounds(for period: WalletPeriod, date: Date) -> (Date, Date) {
        switch period {
        case .week:
            let weekStart = startOfWeek(for: date)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            return (weekStart, weekEnd)
        case .month:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            return (monthStart, monthEnd)
        case .year:
            let year = calendar.component(.year, from: date)
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
            return (yearStart, yearEnd)
        }
    }

    /// Previous-period spending (expenses + fees). If `date`'s period contains today, compares through the same elapsed time last period.
    func comparablePreviousSpending(for period: WalletPeriod, date: Date) -> (previous: Decimal?, inProgress: Bool) {
        let (start, end) = periodBounds(for: period, date: date)
        let now = Date()
        let inProgress = now >= start && now < end
        let previousDate = adjacentAnchorDate(offset: -1, from: date, period: period)
        let (prevStart, prevEnd) = periodBounds(for: period, date: previousDate)
        let compareEnd: Date
        if inProgress {
            let elapsed = now.timeIntervalSince(start)
            compareEnd = min(prevStart.addingTimeInterval(elapsed), prevEnd)
        } else {
            compareEnd = prevEnd
        }
        let previous = spendingIncludingFees(from: prevStart, to: compareEnd)
        return (previous, inProgress)
    }

    private func adjacentAnchorDate(offset: Int, from date: Date, period: WalletPeriod) -> Date {
        switch period {
        case .week:
            return calendar.date(byAdding: .day, value: 7 * offset, to: startOfWeek(for: date)) ?? date
        case .month:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            return calendar.date(byAdding: .month, value: offset, to: monthStart) ?? date
        case .year:
            return calendar.date(byAdding: .year, value: offset, to: date) ?? date
        }
    }

    private func spendingIncludingFees(from start: Date, to end: Date) -> Decimal {
        let entries = fetchEntries(from: start, to: end)
        var total: Decimal = 0
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            guard includeInActivity(entry) else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            if usd < 0 {
                total += abs(usd)
            }
            if isDigitalWallet(account) {
                total += calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
            }
        }
        return total
    }

    func setLastUsedWalletPeriod(_ p: WalletPeriod) {
        lastUsedWalletPeriod = p
        UserDefaults.standard.set(p.rawValue, forKey: Self.lastPeriodKey)
    }

    /// Loads the report matching lastUsedWalletPeriod (week, month, or year).
    /// - Parameter useCurrentRange: If true (Balance page), fetches current week/month/year only and restores selection afterward. If false (Reports), uses existing selection.
    func loadReportForLastUsedPeriod(useCurrentRange: Bool = false) {
        let savedMonth = selectedMonth
        let savedYear = selectedYear
        let savedWeekStart = selectedWeekStart
        if useCurrentRange {
            let now = Date()
            selectedMonth = now
            selectedYear = calendar.component(.year, from: now)
            selectedWeekStart = startOfWeek(for: now)
        }
        switch lastUsedWalletPeriod {
        case .week:
            loadWeekReport()
        case .month:
            loadMonthlyReport()
        case .year:
            loadYearWrapReport()
        }
        if useCurrentRange {
            selectedMonth = savedMonth
            selectedYear = savedYear
            selectedWeekStart = savedWeekStart
        }
    }

    func refresh() {
        loadMonthlyReport()
        loadYearWrapReport()
        loadWeekReport()
        Task { await loadUsdBtcReport() }
    }

    func loadMonthlyReport() {
        isLoading = true
        errorMessage = nil
        monthlyReport = nil

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            isLoading = false
            return
        }

        let oldestTrend = calendar.date(byAdding: .month, value: -5, to: start) ?? start
        let trendOrigin = calendar.date(from: calendar.dateComponents([.year, .month], from: oldestTrend)) ?? start
        let trendEntries = fetchEntries(from: trendOrigin, to: end)
        let entries = filterEntries(trendEntries, from: start, to: end)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]

        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            
            guard includeInActivity(entry) else { continue }
            
            if usd > 0 {
                income += usd
            } else {
                expenses += abs(usd)
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                byCategory[cat, default: 0] += abs(usd)
            }
            if isDigitalWallet(account) {
                let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                fees += fee
                if fee > 0 {
                    byCategory["Digital Wallet Fees", default: 0] += fee
                }
            }
        }

        let trendMonths = (0..<6).reversed().compactMap { offset -> (Date, Decimal, Decimal)? in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: start) else { return nil }
            let mStart = calendar.date(from: calendar.dateComponents([.year, .month], from: m))!
            guard let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) else { return nil }
            let es = filterEntries(trendEntries, from: mStart, to: mEnd)
            var inc: Decimal = 0, exp: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
                
                guard includeInActivity(e) else { continue }
                
                if u > 0 { inc += u } else { exp += abs(u) }
            }
            return (mStart, inc, exp)
        }

        let range = calendar.range(of: .day, in: .month, for: start)!
        let dayCount = range.count
        let daysPerWeek = max(1, (dayCount + 4) / 5)
        var weekly: [Decimal] = Array(repeating: Decimal(0), count: 5)
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { continue }
            
            guard includeInActivity(entry) else { continue }
            
            let d = calendar.component(.day, from: entry.date ?? start)
            let weekIndex = min(4, (d - 1) / daysPerWeek)
            weekly[weekIndex] += abs(usd)
        }

        monthlyReport = MonthlyReportData(
            income: income,
            expenses: expenses,
            digitalWalletFees: fees,
            byCategory: byCategory.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
            trendMonths: trendMonths,
            weeklyBreakdown: weekly,
            month: start
        )
        isLoading = false
        if lastUsedWalletPeriod == .month {
            refreshAdjacentSnapshots()
        }
    }

    func loadYearWrapReport() {
        isLoading = true
        errorMessage = nil
        yearWrapReport = nil

        let start = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            isLoading = false
            return
        }

        let entries = fetchEntries(from: start, to: end)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]
        var monthly: [(Date, Decimal, Decimal, Decimal)] = []

        for monthOffset in 0..<12 {
            guard let m = calendar.date(byAdding: .month, value: monthOffset, to: start) else { continue }
            let mStart = calendar.date(from: calendar.dateComponents([.year, .month], from: m))!
            guard let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) else { continue }
            let es = filterEntries(entries, from: mStart, to: mEnd)
            var inc: Decimal = 0, exp: Decimal = 0, f: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
                
                guard includeInActivity(e) else { continue }
                
                if u > 0 { inc += u } else { exp += abs(u) }
                if isDigitalWallet(acct) {
                    f += calculateDigitalWalletFee(for: e, account: acct, btcService: bitcoinPriceService)
                }
            }
            monthly.append((mStart, inc, exp, f))
        }

        // Yearly totals from all entries (with credit card filtering)
        income = 0
        expenses = 0
        fees = 0
        byCategory = [:]
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let u = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            
            guard includeInActivity(entry) else { continue }
            
            if u > 0 { income += u } else {
                expenses += abs(u)
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                byCategory[cat, default: 0] += abs(u)
            }
            if isDigitalWallet(account) {
                let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                fees += fee
                // Add fees to category breakdown
                if fee > 0 {
                    byCategory["Digital Wallet Fees", default: 0] += fee
                }
            }
        }

        let rate: Decimal? = income > 0 ? (income - expenses) / income : nil
        yearWrapReport = YearWrapData(
            year: selectedYear,
            income: income,
            expenses: expenses,
            digitalWalletFees: fees,
            savingsRate: rate,
            byCategory: byCategory.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
            monthlyBreakdown: monthly
        )
        isLoading = false
        if lastUsedWalletPeriod == .year {
            refreshAdjacentSnapshots()
        }
    }

    func loadWeekReport() {
        isLoading = true
        errorMessage = nil
        weeklyReport = nil

        let start = startOfWeek(for: selectedWeekStart)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            isLoading = false
            return
        }

        let entries = fetchEntries(from: start, to: end)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]
        var daily: [(day: Date, expenses: Decimal)] = []

        for dayOffset in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            let dStart = calendar.startOfDay(for: d)
            guard let dEnd = calendar.date(byAdding: .day, value: 1, to: dStart) else { continue }
            let es = filterEntries(entries, from: dStart, to: dEnd)
            var exp: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
                
                guard includeInActivity(e) else { continue }
                
                if u > 0 { income += u } else {
                    let a = abs(u)
                    expenses += a
                    exp += a
                    let cat = e.category?.isEmpty == false ? e.category! : "Uncategorized"
                    byCategory[cat, default: 0] += a
                }
                if isDigitalWallet(acct) {
                    let fee = calculateDigitalWalletFee(for: e, account: acct, btcService: bitcoinPriceService)
                    fees += fee
                    // Add fees to category breakdown
                    if fee > 0 {
                        byCategory["Digital Wallet Fees", default: 0] += fee
                    }
                }
            }
            daily.append((day: dStart, expenses: exp))
        }

        weeklyReport = WeeklyReportData(
            weekStart: start,
            income: income,
            expenses: expenses,
            digitalWalletFees: fees,
            byCategory: byCategory.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
            dailyBreakdown: daily
        )
        isLoading = false
        if lastUsedWalletPeriod == .week {
            refreshAdjacentSnapshots()
        }
    }

    func startOfWeek(for date: Date) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return date }
        return interval.start
    }
    
    /// Previous-period spending including fees. Uses month-to-date (or equivalent) when the selected period is still in progress.
    func previousPeriodExpenses(for period: WalletPeriod) -> Decimal? {
        comparablePreviousSpending(for: period, date: currentAnchorDate()).previous
    }

    func isCurrentPeriodInProgress(_ period: WalletPeriod) -> Bool {
        comparablePreviousSpending(for: period, date: currentAnchorDate()).inProgress
    }

    func loadUsdBtcReport() async {
        guard hasActiveBitcoinDigitalWallet, usdBtcBacktestEnabled else {
            usdBtcReport = nil
            return
        }
        errorMessage = nil
        let templates = trackedBillTemplates()
        let now = Date()
        let start = calendar.date(byAdding: .month, value: -usdBtcMonthsBack, to: now)!
        let startOfStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        await bitcoinPriceService.ensureHistoricalPrices(from: startOfStart, to: now)
        let currentPrice = bitcoinPriceService.btcToUsdRate

        guard !templates.isEmpty else {
            usdBtcReport = UsdBtcReportData(
                months: [],
                bills: [],
                totalUsd: 0,
                totalBtcAtTime: 0,
                totalBtcValueNow: 0,
                monthsBack: usdBtcMonthsBack,
                trackedBillNames: [],
                estimatedMonths: 0,
                actualMonths: 0
            )
            return
        }

        var totalUsd: Decimal = 0
        var totalBtcAtTime: Decimal = 0
        var totalBtcValueNow: Decimal = 0
        var months: [UsdBtcMonthPoint] = []
        var estimatedMonths = 0
        var actualMonths = 0
        var billMonthPoints = Array(repeating: [UsdBtcMonthPoint](), count: templates.count)
        var billUsd = Array(repeating: Decimal(0), count: templates.count)
        var billBtcAt = Array(repeating: Decimal(0), count: templates.count)
        var billBtcNow = Array(repeating: Decimal(0), count: templates.count)

        let rangeEnd = calendar.date(byAdding: .month, value: usdBtcMonthsBack, to: startOfStart) ?? now
        let allEntries = fetchEntries(from: startOfStart, to: rangeEnd)
        let candidates: [BillBtcBacktest.LedgerCandidate] = allEntries.compactMap { entry in
            guard let account = entry.account, !account.isHiddenFlag, !entry.isCredit, let date = entry.date else { return nil }
            let usd = abs(reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService))
            let btc = entry.btcAmountDecimal > 0 ? entry.btcAmountDecimal : nil
            let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : nil
            return BillBtcBacktest.LedgerCandidate(
                date: date,
                title: entry.title ?? "",
                usd: usd,
                btc: btc,
                price: price,
                billName: entry.bill?.name,
                billSeriesId: entry.bill?.seriesId,
                category: entry.category
            )
        }

        for offset in 0..<usdBtcMonthsBack {
            guard let m = calendar.date(byAdding: .month, value: offset, to: startOfStart) else { continue }
            let mStart = calendar.date(from: calendar.dateComponents([.year, .month], from: m))!
            guard let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) else { continue }
            if mStart > now { continue }

            var usdExp: Decimal = 0
            var btcQty: Decimal = 0
            var btcAt: Decimal = 0
            var btcNow: Decimal = 0
            var priceSum: Decimal = 0
            var priceCount: Int = 0
            var monthIsEstimate = false
            var monthHasActual = false
            var used = Set<Int>()

            for (templateIndex, template) in templates.enumerated() {
                let due = BillBtcBacktest.dueDate(inMonth: mStart, day: template.dueDay, calendar: calendar)
                let matchIdx = BillBtcBacktest.matchingIndex(
                    template: template,
                    in: candidates,
                    used: used,
                    monthStart: mStart,
                    monthEnd: mEnd,
                    calendar: calendar
                )
                let actual: BillBtcBacktest.LedgerCandidate?
                if let matchIdx {
                    used.insert(matchIdx)
                    actual = candidates[matchIdx]
                } else {
                    actual = nil
                }
                let hist = bitcoinPriceService.historicalUSDPrice(on: actual?.date ?? due)
                guard let amount = BillBtcBacktest.monthAmount(
                    template: template,
                    dueDate: due,
                    actual: actual,
                    historicalPrice: hist,
                    currentPrice: currentPrice
                ) else { continue }

                let nowValue = amount.btc * (currentPrice > 0 ? currentPrice : amount.price)
                let point = UsdBtcMonthPoint(
                    month: mStart,
                    usdExpenses: amount.usd,
                    btcAtTime: amount.usd,
                    btcValueNow: nowValue,
                    btcAmount: amount.btc,
                    avgBtcPrice: amount.price,
                    isEstimate: amount.isEstimate
                )
                billMonthPoints[templateIndex].append(point)
                billUsd[templateIndex] += amount.usd
                billBtcAt[templateIndex] += amount.usd
                billBtcNow[templateIndex] += nowValue

                usdExp += amount.usd
                btcQty += amount.btc
                btcAt += amount.usd
                btcNow += nowValue
                if amount.price > 0 {
                    priceSum += amount.price
                    priceCount += 1
                }
                if amount.isEstimate {
                    monthIsEstimate = true
                } else {
                    monthHasActual = true
                }
            }

            let avgPrice = priceCount > 0 ? priceSum / Decimal(priceCount) : 0
            months.append(
                UsdBtcMonthPoint(
                    month: mStart,
                    usdExpenses: usdExp,
                    btcAtTime: btcAt,
                    btcValueNow: btcNow,
                    btcAmount: btcQty,
                    avgBtcPrice: avgPrice,
                    isEstimate: monthIsEstimate && !monthHasActual
                )
            )
            totalUsd += usdExp
            totalBtcAtTime += btcAt
            totalBtcValueNow += btcNow
            if monthHasActual {
                actualMonths += 1
            } else if usdExp > 0 {
                estimatedMonths += 1
            }
        }

        let bills: [UsdBtcBillSeries] = templates.enumerated().compactMap { index, template in
            let points = billMonthPoints[index]
            guard !points.isEmpty else { return nil }
            return UsdBtcBillSeries(
                name: template.name,
                months: points,
                totalUsd: billUsd[index],
                totalBtcAtTime: billBtcAt[index],
                totalBtcValueNow: billBtcNow[index]
            )
        }

        usdBtcReport = UsdBtcReportData(
            months: months,
            bills: bills,
            totalUsd: totalUsd,
            totalBtcAtTime: totalBtcAtTime,
            totalBtcValueNow: totalBtcValueNow,
            monthsBack: usdBtcMonthsBack,
            trackedBillNames: templates.map(\.name),
            estimatedMonths: estimatedMonths,
            actualMonths: actualMonths
        )
    }

    func loadExpenseReport() {
        isLoading = true
        errorMessage = nil
        expenseReport = nil

        let start = calendar.startOfDay(for: expenseReportStart)
        var endDay = calendar.startOfDay(for: expenseReportEnd)
        if endDay < start { endDay = start }
        let end = calendar.date(byAdding: .day, value: 1, to: endDay)!

        let entries = fetchEntries(from: start, to: end)
        var rows: [ExpenseReportRow] = []
        var byCategory: [String: Decimal] = [:]
        var total: Decimal = 0

        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            if let aid = expenseReportAccountId, account.id != aid { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            if usd >= 0 { continue }
            guard includeInActivity(entry) else { continue }
            let amount = abs(usd)
            let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
            byCategory[cat, default: 0] += amount
            total += amount
            rows.append(ExpenseReportRow(
                id: entry.id ?? UUID(),
                date: entry.date ?? start,
                title: entry.title ?? "",
                amount: amount,
                category: cat,
                accountName: account.name ?? ""
            ))
        }

        expenseReport = ExpenseReportData(
            start: start,
            end: end,
            accountId: expenseReportAccountId,
            rows: rows.sorted { ($0.date, $0.title) < ($1.date, $1.title) },
            byCategory: byCategory.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
            total: total
        )
        isLoading = false
    }

    func accountsForExpenseReport() -> [Account] {
        fetchNonHiddenAccounts()
    }

    private func fetchEntries(from start: Date, to end: Date) -> [LedgerEntry] {
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: true)]
        request.fetchBatchSize = 50
        do {
            return try context.fetch(request)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func filterEntries(_ entries: [LedgerEntry], from start: Date, to end: Date) -> [LedgerEntry] {
        entries.filter { entry in
            guard let date = entry.date else { return false }
            return date >= start && date < end
        }
    }

    private func fetchNonHiddenAccounts() -> [Account] {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Account.order, ascending: true)]
        request.fetchBatchSize = 50
        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private var cardNames: [String] {
        creditCardManager?.cards ?? []
    }

    private func includeInActivity(_ entry: LedgerEntry) -> Bool {
        guard let account = entry.account, !account.isHiddenFlag else { return false }
        return ActivityLedgerRules.includeInTotals(
            accountType: account.type,
            isCredit: entry.isCredit,
            title: entry.title ?? "",
            cardNames: cardNames,
            category: entry.category
        )
    }

    private func trackedBillTemplates() -> [BillBtcBacktest.Template] {
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.fetchBatchSize = 50
        let bills = (try? context.fetch(request)) ?? []
        let sources: [BillBtcBacktest.BillSource] = bills.map { bill in
            let entries = (bill.ledgerEntries as? Set<LedgerEntry>) ?? []
            let paidInBitcoin = entries.contains { entry in
                let usd = entry.usdAmountDecimal > 0 ? entry.usdAmountDecimal : bill.amountDecimal
                return BillBtcBacktest.isUsdBillPaidInBitcoin(
                    isCredit: entry.isCredit,
                    usdAmount: usd,
                    btcAmount: entry.btcAmountDecimal
                )
            }
            return BillBtcBacktest.BillSource(
                groupingKey: BillBtcBacktest.groupingKey(
                    seriesId: bill.seriesId,
                    billId: bill.id,
                    objectURI: bill.objectID.uriRepresentation().absoluteString
                ),
                name: bill.name ?? "",
                amount: bill.amountDecimal,
                dueDate: bill.dueDate,
                seriesId: bill.seriesId,
                category: bill.category,
                trackInBitcoin: bill.trackInBitcoinFlag,
                paidInBitcoin: paidInBitcoin
            )
        }
        return BillBtcBacktest.templates(from: sources, calendar: calendar)
    }
    
    /// Fetches income entries (positive USD amounts) within the current period
    func fetchIncomeEntries(period: WalletPeriod) -> [LedgerEntry] {
        let (start, end): (Date, Date) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: selectedWeekStart)
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return (weekStart, weekStart)
                }
                return (weekStart, weekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart)
                }
                return (monthStart, monthEnd)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
                guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                    return (yearStart, yearStart)
                }
                return (yearStart, yearEnd)
            }
        }()
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        
        do {
            let entries = try context.fetch(request)
            // Filter for income entries (positive USD amounts) from non-hidden accounts
            return entries.filter { entry in
                guard let account = entry.account, !account.isHiddenFlag else { return false }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                return usd > 0 && includeInActivity(entry)
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
    
    /// Fetches digital wallet fee entries within the current period
    func fetchFeeEntries(period: WalletPeriod) -> [LedgerEntry] {
        let (start, end): (Date, Date) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: selectedWeekStart)
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return (weekStart, weekStart)
                }
                return (weekStart, weekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart)
                }
                return (monthStart, monthEnd)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
                guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                    return (yearStart, yearStart)
                }
                return (yearStart, yearEnd)
            }
        }()
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        
        do {
            let entries = try context.fetch(request)
            // Filter for entries from digital wallet accounts with fees
            return entries.filter { entry in
                guard let account = entry.account, !account.isHiddenFlag else { return false }
                guard isDigitalWallet(account) else { return false }
                guard account.feePercentageDecimal > 0 else { return false }
                let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                return fee > 0
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
    
    /// Calculates category spending for previous period (for trend comparison)
    func previousPeriodCategorySpending(_ categoryName: String, period: WalletPeriod) -> Decimal {
        let (start, end): (Date, Date) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: selectedWeekStart)
                guard let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
                      let prevWeekEnd = calendar.date(byAdding: .day, value: 7, to: prevWeekStart) else {
                    return (weekStart, weekStart)
                }
                return (prevWeekStart, prevWeekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: monthStart),
                      let prevMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: prevMonth)),
                      let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) else {
                    return (monthStart, monthStart)
                }
                return (prevMonthStart, prevMonthEnd)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
                guard let prevYearStart = calendar.date(from: DateComponents(year: selectedYear - 1, month: 1, day: 1)),
                      let prevYearEnd = calendar.date(byAdding: .year, value: 1, to: prevYearStart) else {
                    return (yearStart, yearStart)
                }
                return (prevYearStart, prevYearEnd)
            }
        }()
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        let categoryPredicate: NSPredicate
        if categoryName == "Uncategorized" {
            categoryPredicate = NSPredicate(format: "(category == nil OR category == %@)", "")
        } else {
            categoryPredicate = NSPredicate(format: "category == %@", categoryName)
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate),
            categoryPredicate
        ])
        
        do {
            let entries = try context.fetch(request)
            var total: Decimal = 0
            for entry in entries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                if usd < 0 {
                    total += abs(usd)
                }
            }
            return total
        } catch {
            return 0
        }
    }
    
    /// Fetches ledger entries for a specific category within the current period
    func fetchEntriesByCategory(_ categoryName: String, period: WalletPeriod) -> [LedgerEntry] {
        let (start, end): (Date, Date) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: selectedWeekStart)
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return (weekStart, weekStart)
                }
                return (weekStart, weekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart)
                }
                return (monthStart, monthEnd)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
                guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                    return (yearStart, yearStart)
                }
                return (yearStart, yearEnd)
            }
        }()
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        let categoryPredicate: NSPredicate
        if categoryName == "Uncategorized" {
            categoryPredicate = NSPredicate(format: "(category == nil OR category == %@)", "")
        } else {
            categoryPredicate = NSPredicate(format: "category == %@", categoryName)
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate),
            categoryPredicate
        ])
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        
        do {
            let entries = try context.fetch(request)
            // Filter out entries from hidden accounts
            return entries.filter { entry in
                guard let account = entry.account else { return false }
                return !account.isHiddenFlag
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
    
    /// Gets category breakdown by period for stacked bar chart.
    /// - Parameter date: Anchor date for the week/month/year. Defaults to the currently selected period.
    func categoryBreakdownByPeriod(period: WalletPeriod, date: Date? = nil) -> [(period: String, categories: [(name: String, amount: Decimal)])] {
        let calendar = Calendar.current
        var result: [(period: String, categories: [(name: String, amount: Decimal)])] = []
        let anchor = date ?? currentAnchorDate()
        
        let (start, end, periodCount, periodFormatter): (Date, Date, Int, (Date) -> String) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: anchor)
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                    return (weekStart, weekStart, 0, { _ in "" })
                }
                let formatter: (Date) -> String = { date in
                    let f = DateFormatter()
                    f.dateFormat = "EEE"
                    return f.string(from: date).prefix(3).uppercased()
                }
                return (weekStart, weekEnd, 7, formatter)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart, 0, { _ in "" })
                }
                let formatter: (Date) -> String = { _ in "" }
                return (monthStart, monthEnd, 5, formatter)
            case .year:
                let year = calendar.component(.year, from: anchor)
                let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
                guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                    return (yearStart, yearStart, 0, { _ in "" })
                }
                let formatter: (Date) -> String = { date in
                    let f = DateFormatter()
                    f.dateFormat = "MMM"
                    return f.string(from: date).prefix(3).uppercased()
                }
                return (yearStart, yearEnd, 12, formatter)
            }
        }()
        
        // Get all categories from the period (filtered by view mode)
        let entries = fetchEntries(from: start, to: end)
        var allCategories: Set<String> = []
        var hasFees = false
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { continue }
            
            guard includeInActivity(entry) else { continue }
            
            let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
            allCategories.insert(cat)
            
            // Check if there are digital wallet fees
            if isDigitalWallet(account) && account.feePercentageDecimal > 0 {
                let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                if fee > 0 {
                    hasFees = true
                }
            }
        }
        // Add Digital Wallet Fees category if fees exist
        if hasFees {
            allCategories.insert("Digital Wallet Fees")
        }
        // Sort categories, but put Digital Wallet Fees at the end for better visual hierarchy
        let sortedCategories = Array(allCategories).sorted { cat1, cat2 in
            if cat1 == "Digital Wallet Fees" { return false }
            if cat2 == "Digital Wallet Fees" { return true }
            return cat1 < cat2
        }
        
        // Get category data for each period
        for periodIndex in 0..<periodCount {
            let periodStart: Date?
            let periodEnd: Date?
            var periodLabel: String?
            
            switch period {
            case .week:
                guard let day = calendar.date(byAdding: .day, value: periodIndex, to: start) else {
                    continue
                }
                let dayStart = calendar.startOfDay(for: day)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                    continue
                }
                periodStart = dayStart
                periodEnd = dayEnd
            case .month:
                let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
                let daysPerWeek = max(1, (dayCount + 4) / 5) // Divide month into 5 roughly equal weeks
                let startDay = periodIndex * daysPerWeek + 1
                let endDay = min((periodIndex + 1) * daysPerWeek, dayCount)
                guard let periodStartDate = calendar.date(byAdding: .day, value: startDay - 1, to: start) else {
                    continue
                }
                // Calculate end date correctly
                let daysInPeriod = endDay - startDay + 1
                guard let periodEndDate = calendar.date(byAdding: .day, value: daysInPeriod, to: periodStartDate) else {
                    continue
                }
                periodStart = periodStartDate
                periodEnd = periodEndDate
                
                // Generate period label directly from day range
                periodLabel = "\(startDay)-\(endDay)"
            case .year:
                guard let monthDate = calendar.date(byAdding: .month, value: periodIndex, to: start) else {
                    continue
                }
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    continue
                }
                periodStart = monthStart
                periodEnd = monthEnd
            }
            
            guard let periodStart = periodStart, let periodEnd = periodEnd else {
                continue
            }
            
            var categoryAmounts: [String: Decimal] = [:]
            let periodEntries = filterEntries(entries, from: periodStart, to: periodEnd)
            
            for entry in periodEntries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                guard usd < 0 else { continue }
                
                guard includeInActivity(entry) else { continue }
                
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                categoryAmounts[cat, default: 0] += abs(usd)
                
                // Add digital wallet fees to category breakdown
                if isDigitalWallet(account) {
                    let fee = calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService)
                    if fee > 0 {
                        categoryAmounts["Digital Wallet Fees", default: 0] += fee
                    }
                }
            }
            
            // Create sorted category list for this period (only categories with spending)
            let categories = sortedCategories.compactMap { category -> (name: String, amount: Decimal)? in
                let amount = categoryAmounts[category] ?? 0
                guard amount > 0 else { return nil }
                return (name: category, amount: amount)
            }.sorted { $0.amount > $1.amount }
            
            // Always add period, even if no categories (for proper date display)
            // Generate period label - for month view, use the pre-calculated label, otherwise use formatter
            let finalPeriodLabel: String
            if let preCalculatedLabel = periodLabel {
                finalPeriodLabel = preCalculatedLabel
            } else {
                finalPeriodLabel = periodFormatter(periodStart)
            }
            result.append((period: finalPeriodLabel, categories: categories))
        }
        
        return result
    }
    
    // MARK: - Credit Card Detection
    
    /// Determines if a transaction is a credit card payment (vs. an individual credit card transaction)
    /// Credit card payments are the payments you make TO the credit card, not the individual transactions ON the card
    private func isCreditCardPaymentTransaction(_ entry: LedgerEntry) -> Bool {
        if let account = entry.account, ActivityLedgerRules.isCreditAccount(account.type), entry.isCredit {
            return true
        }
        return ActivityLedgerRules.isCardPaymentTitle(entry.title ?? "", cardNames: cardNames, isCreditEntry: entry.isCredit)
    }
    
    // MARK: - Credit Card Spending Calculation
    
    /// Calculates total credit card spending or payments based on current view mode
    func creditCardSpending(for period: WalletPeriod, date: Date? = nil) -> Decimal {
        let (start, end) = periodBounds(for: period, date: date ?? currentAnchorDate())
        
        let entries = fetchEntries(from: start, to: end)
        var total: Decimal = 0
        
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            
            switch creditCardViewMode {
            case .payments:
                let isBankSidePayment = !ActivityLedgerRules.isCreditAccount(account.type)
                    && isCreditCardPaymentTransaction(entry)
                    && usd < 0
                if isBankSidePayment {
                    total += abs(usd)
                }
            case .transactions:
                if isCreditCardTransaction(entry) && usd < 0 {
                    total += abs(usd)
                }
            }
        }
        
        return total
    }
    
    /// Determines if a transaction is a credit card transaction (individual spending on a card)
    /// This includes both imported transactions and transactions from bills
    private func isCreditCardTransaction(_ entry: LedgerEntry) -> Bool {
        if isCreditCardPaymentTransaction(entry) { return false }
        if let account = entry.account, ActivityLedgerRules.isCreditAccount(account.type), !entry.isCredit {
            return true
        }
        return ActivityLedgerRules.isCardSpendingTitle(entry.title ?? "", cardNames: cardNames, isCreditEntry: entry.isCredit)
    }
    
    /// Gets all transactions for a specific category within a period
    func transactionsForCategory(_ category: String, period: WalletPeriod, date: Date? = nil) -> [LedgerEntry] {
        let (start, end) = periodBounds(for: period, date: date ?? currentAnchorDate())
        
        let entries = fetchEntries(from: start, to: end)
        let categoryName = category.isEmpty ? nil : category
        
        // Special handling for Digital Wallet Fees - return all transactions from digital wallet accounts
        if category == "Digital Wallet Fees" {
            return entries.filter { entry in
                guard let account = entry.account, !account.isHiddenFlag else { return false }
                guard isDigitalWallet(account) else { return false }
                guard account.feePercentageDecimal > 0 else { return false }
                
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                // Include both positive and negative transactions (fees apply to all)
                guard usd != 0 else { return false }
                return includeInActivity(entry) && calculateDigitalWalletFee(for: entry, account: account, btcService: bitcoinPriceService) > 0
            }.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
        }
        
        // Regular category filtering
        return entries.filter { entry in
            guard let account = entry.account, !account.isHiddenFlag else { return false }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { return false }
            guard includeInActivity(entry) else { return false }
            
            let entryCategory = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
            return entryCategory == (categoryName ?? "Uncategorized")
        }.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
}
