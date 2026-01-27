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

/// USD vs Bitcoin bills over time: expenses by currency, BTC value-at-payment vs value-today, and price fluctuation.
struct UsdBtcReportData {
    /// Per month: (month, USD expenses, BTC expenses USD@payment, BTC value today, avg BTC price @ payment).
    var months: [(month: Date, usdExpenses: Decimal, btcAtTime: Decimal, btcValueNow: Decimal, avgBtcPrice: Decimal)]
    var totalUsd: Decimal
    var totalBtcAtTime: Decimal
    var totalBtcValueNow: Decimal
    var monthsBack: Int
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

    @Published var monthlyReport: MonthlyReportData?
    @Published var yearWrapReport: YearWrapData?
    @Published var weeklyReport: WeeklyReportData?
    @Published var usdBtcReport: UsdBtcReportData?
    @Published var selectedMonth: Date = Date()
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var selectedWeekStart: Date = Date()
    @Published var lastUsedWalletPeriod: WalletPeriod = .month
    @Published var creditCardViewMode: CreditCardViewMode = .transactions
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
    }
    
    func setCreditCardViewMode(_ mode: CreditCardViewMode) {
        creditCardViewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.lastCreditCardViewModeKey)
    }
    
    /// Jumps to the current period (today's week/month/year)
    func jumpToCurrentPeriod() {
        let now = Date()
        switch lastUsedWalletPeriod {
        case .week:
            selectedWeekStart = startOfWeek(for: now)
            loadWeekReport()
        case .month:
            selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            loadMonthlyReport()
        case .year:
            selectedYear = calendar.component(.year, from: now)
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
        loadUsdBtcReport()
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

        let entries = fetchEntries(from: start, to: end)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]

        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            if usd > 0 {
                income += usd
            } else {
                expenses += abs(usd)
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                byCategory[cat, default: 0] += abs(usd)
            }
            if isDigitalWallet(account) {
                fees += FeeParsing.feeFromNotes(entry.notes)
            }
        }

        let trendMonths = (0..<6).reversed().compactMap { offset -> (Date, Decimal, Decimal)? in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: start) else { return nil }
            let mStart = calendar.date(from: calendar.dateComponents([.year, .month], from: m))!
            guard let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) else { return nil }
            let es = fetchEntries(from: mStart, to: mEnd)
            var inc: Decimal = 0, exp: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
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
            let es = fetchEntries(from: mStart, to: mEnd)
            var inc: Decimal = 0, exp: Decimal = 0, f: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
                if u > 0 { inc += u } else { exp += abs(u) }
                if isDigitalWallet(acct) { f += FeeParsing.feeFromNotes(e.notes) }
            }
            monthly.append((mStart, inc, exp, f))
        }

        // Yearly totals from all entries
        income = 0
        expenses = 0
        fees = 0
        byCategory = [:]
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let u = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            if u > 0 { income += u } else {
                expenses += abs(u)
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                byCategory[cat, default: 0] += abs(u)
            }
            if isDigitalWallet(account) { fees += FeeParsing.feeFromNotes(entry.notes) }
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

        _ = fetchEntries(from: start, to: end)
        var income: Decimal = 0
        var expenses: Decimal = 0
        var fees: Decimal = 0
        var byCategory: [String: Decimal] = [:]
        var daily: [(day: Date, expenses: Decimal)] = []

        for dayOffset in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            let dStart = calendar.startOfDay(for: d)
            guard let dEnd = calendar.date(byAdding: .day, value: 1, to: dStart) else { continue }
            let es = fetchEntries(from: dStart, to: dEnd)
            var exp: Decimal = 0
            for e in es {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                let u = reportUSDAmount(for: e, account: acct, btcService: bitcoinPriceService)
                if u > 0 { income += u } else {
                    let a = abs(u)
                    expenses += a
                    exp += a
                    let cat = e.category?.isEmpty == false ? e.category! : "Uncategorized"
                    byCategory[cat, default: 0] += a
                }
                if isDigitalWallet(acct) { fees += FeeParsing.feeFromNotes(e.notes) }
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
    }

    func startOfWeek(for date: Date) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return date }
        return interval.start
    }
    
    /// Calculates expenses for the previous period (week/month/year) based on current period type.
    func previousPeriodExpenses(for period: WalletPeriod) -> Decimal? {
        switch period {
        case .week:
            guard let weekStart = weeklyReport?.weekStart else { return nil }
            guard let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) else { return nil }
            guard let prevWeekEnd = calendar.date(byAdding: .day, value: 7, to: prevWeekStart) else { return nil }
            let entries = fetchEntries(from: prevWeekStart, to: prevWeekEnd)
            var expenses: Decimal = 0
            for entry in entries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                if usd < 0 {
                    expenses += abs(usd)
                }
            }
            return expenses
        case .month:
            guard let month = monthlyReport?.month else { return nil }
            guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: month) else { return nil }
            let prevMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: prevMonth))!
            guard let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) else { return nil }
            let entries = fetchEntries(from: prevMonthStart, to: prevMonthEnd)
            var expenses: Decimal = 0
            for entry in entries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                if usd < 0 {
                    expenses += abs(usd)
                }
            }
            return expenses
        case .year:
            guard let year = yearWrapReport?.year else { return nil }
            let prevYearStart = calendar.date(from: DateComponents(year: year - 1, month: 1, day: 1))!
            guard let prevYearEnd = calendar.date(byAdding: .year, value: 1, to: prevYearStart) else { return nil }
            let entries = fetchEntries(from: prevYearStart, to: prevYearEnd)
            var expenses: Decimal = 0
            for entry in entries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                if usd < 0 {
                    expenses += abs(usd)
                }
            }
            return expenses
        }
    }

    func loadUsdBtcReport() {
        isLoading = true
        errorMessage = nil
        usdBtcReport = nil

        let now = Date()
        let start = calendar.date(byAdding: .month, value: -usdBtcMonthsBack, to: now)!
        let startOfStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        let currentPrice = bitcoinPriceService.btcToUsdRate

        var totalUsd: Decimal = 0
        var totalBtcAtTime: Decimal = 0
        var totalBtcValueNow: Decimal = 0
        var months: [(Date, Decimal, Decimal, Decimal, Decimal)] = []

        for offset in 0..<usdBtcMonthsBack {
            guard let m = calendar.date(byAdding: .month, value: offset, to: startOfStart) else { continue }
            let mStart = calendar.date(from: calendar.dateComponents([.year, .month], from: m))!
            guard let mEnd = calendar.date(byAdding: .month, value: 1, to: mStart) else { continue }
            let entries = fetchEntries(from: mStart, to: mEnd)

            var usdExp: Decimal = 0
            var btcAt: Decimal = 0
            var btcNow: Decimal = 0
            var priceSum: Decimal = 0
            var priceCount: Int = 0

            for e in entries {
                guard let acct = e.account, !acct.isHiddenFlag else { continue }
                guard !e.isCredit else { continue }

                let isDigitalWallet = (acct.type ?? "").lowercased() == "digital wallet"
                if isDigitalWallet {
                    let btc = abs(e.amountInCurrency(for: acct))
                    let price = e.btcPriceAtTransactionDecimal > 0 ? e.btcPriceAtTransactionDecimal : currentPrice
                    let usdAtPayment = e.usdAmountDecimal != 0 ? abs(e.usdAmountDecimal) : btc * price
                    btcAt += usdAtPayment
                    btcNow += btc * currentPrice
                    if e.btcPriceAtTransactionDecimal > 0 {
                        priceSum += e.btcPriceAtTransactionDecimal
                        priceCount += 1
                    }
                } else {
                    let amt = e.usdAmountDecimal != 0 ? abs(e.usdAmountDecimal) : abs(e.amountDecimal)
                    usdExp += amt
                }
            }

            let avgPrice = priceCount > 0 ? priceSum / Decimal(priceCount) : 0
            months.append((mStart, usdExp, btcAt, btcNow, avgPrice))
            totalUsd += usdExp
            totalBtcAtTime += btcAt
            totalBtcValueNow += btcNow
        }

        usdBtcReport = UsdBtcReportData(
            months: months,
            totalUsd: totalUsd,
            totalBtcAtTime: totalBtcAtTime,
            totalBtcValueNow: totalBtcValueNow,
            monthsBack: usdBtcMonthsBack
        )
        isLoading = false
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
        do {
            return try context.fetch(request)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func fetchNonHiddenAccounts() -> [Account] {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Account.order, ascending: true)]
        do {
            return try context.fetch(request)
        } catch {
            return []
        }
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
                return usd > 0
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
                let fee = FeeParsing.feeFromNotes(entry.notes)
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
    
    /// Gets category breakdown by period for stacked bar chart
    func categoryBreakdownByPeriod(period: WalletPeriod) -> [(period: String, categories: [(name: String, amount: Decimal)])] {
        let calendar = Calendar.current
        var result: [(period: String, categories: [(name: String, amount: Decimal)])] = []
        
        let (start, end, periodCount, periodFormatter): (Date, Date, Int, (Date) -> String) = {
            switch period {
            case .week:
                let weekStart = startOfWeek(for: selectedWeekStart)
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
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
                guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                    return (monthStart, monthStart, 0, { _ in "" })
                }
                // The formatter won't be used for month view - labels are generated directly in the loop
                let formatter: (Date) -> String = { date in
                    // This won't be used - we'll generate labels directly in the loop
                    return ""
                }
                return (monthStart, monthEnd, 5, formatter)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
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
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { continue }
            
            // Filter based on credit card view mode
            let isCreditCardPayment = isCreditCardPaymentTransaction(entry)
            
            switch creditCardViewMode {
            case .payments:
                // Only include credit card payment transactions
                guard isCreditCardPayment else { continue }
            case .transactions:
                // Exclude credit card payment transactions
                guard !isCreditCardPayment else { continue }
            }
            
            let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
            allCategories.insert(cat)
        }
        let sortedCategories = Array(allCategories).sorted()
        
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
                let dayCount = calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
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
            let periodEntries = fetchEntries(from: periodStart, to: periodEnd)
            
            for entry in periodEntries {
                guard let account = entry.account, !account.isHiddenFlag else { continue }
                let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
                guard usd < 0 else { continue }
                
                // Filter based on credit card view mode
                let isCreditCardPayment = isCreditCardPaymentTransaction(entry)
                
                switch creditCardViewMode {
                case .payments:
                    // Only show credit card payment transactions
                    guard isCreditCardPayment else { continue }
                case .transactions:
                    // Exclude credit card payment transactions, show individual transactions
                    guard !isCreditCardPayment else { continue }
                }
                
                let cat = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
                categoryAmounts[cat, default: 0] += abs(usd)
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
        guard let title = entry.title else { return false }
        let titleLower = title.lowercased()
        
        // 1. Check if title explicitly contains "Credit Card Payment" or "Credit Card" + "Payment"
        if titleLower.contains("credit card payment") {
            return true
        }
        if titleLower.contains("credit card") && titleLower.contains("payment") {
            return true
        }
        
        // 2. Check if title matches any card name from CreditCardManager AND contains "payment" or is a credit
        if let cardManager = creditCardManager {
            for cardName in cardManager.cards {
                let cardNameLower = cardName.lowercased()
                // If title contains the card name and either "payment" keyword or it's a credit transaction
                if titleLower.contains(cardNameLower) {
                    // If it contains "payment" or is a credit (payment TO the card), it's likely a payment
                    if titleLower.contains("payment") || entry.isCredit {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Credit Card Spending Calculation
    
    /// Calculates total credit card spending (transactions, not payments) for a given period
    func creditCardSpending(for period: WalletPeriod) -> Decimal {
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
        
        let entries = fetchEntries(from: start, to: end)
        var totalSpending: Decimal = 0
        
        for entry in entries {
            guard let account = entry.account, !account.isHiddenFlag else { continue }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { continue }
            
            // Only include credit card transactions (exclude payments)
            let isCreditCardPayment = isCreditCardPaymentTransaction(entry)
            guard !isCreditCardPayment else { continue }
            
            // Check if this is a credit card transaction (has credit card in title or matches card name)
            if isCreditCardTransaction(entry) {
                totalSpending += abs(usd)
            }
        }
        
        return totalSpending
    }
    
    /// Determines if a transaction is a credit card transaction (individual spending on a card)
    private func isCreditCardTransaction(_ entry: LedgerEntry) -> Bool {
        guard let title = entry.title else { return false }
        let titleLower = title.lowercased()
        
        // Check if title contains credit card keywords (but not "payment")
        if titleLower.contains("credit card") && !titleLower.contains("payment") {
            return true
        }
        
        // Check if it matches any card name from CreditCardManager (but not a payment)
        if let cardManager = creditCardManager {
            for cardName in cardManager.cards {
                let cardNameLower = cardName.lowercased()
                if titleLower.contains(cardNameLower) && !titleLower.contains("payment") && !entry.isCredit {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Gets all transactions for a specific category within a period
    func transactionsForCategory(_ category: String, period: WalletPeriod) -> [LedgerEntry] {
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
        
        let entries = fetchEntries(from: start, to: end)
        let categoryName = category.isEmpty ? nil : category
        
        return entries.filter { entry in
            guard let account = entry.account, !account.isHiddenFlag else { return false }
            let usd = reportUSDAmount(for: entry, account: account, btcService: bitcoinPriceService)
            guard usd < 0 else { return false }
            
            // Filter based on credit card view mode
            let isCreditCardPayment = isCreditCardPaymentTransaction(entry)
            
            switch creditCardViewMode {
            case .payments:
                // Only show credit card payment transactions
                guard isCreditCardPayment else { return false }
            case .transactions:
                // Exclude credit card payment transactions
                guard !isCreditCardPayment else { return false }
            }
            
            let entryCategory = entry.category?.isEmpty == false ? entry.category! : "Uncategorized"
            return entryCategory == (categoryName ?? "Uncategorized")
        }.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
}
