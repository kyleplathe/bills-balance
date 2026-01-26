//
//  ReportsView.swift
//  BillsAndBalance
//
//  Activity reports: Week/Month/Year, Total Spending, Income, Fees, By Category, USD vs BTC.
//  Presented as fullScreenCover — own NavigationStack, X + period picker in toolbar. Main toolbar (Balance/tab bar) not shown.
//

import SwiftUI
import Charts

// MARK: - Reports View

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @State private var appeared = false
    @State private var showingStatementImportPicker = false
    @State private var showingStatementImportSheet = false
    @State private var statementImportTransactions: [ParsedStatementTransaction] = []
    @State private var statementImportFileName: String = ""
    @State private var statementImportErrorMessage: String?
    @State private var showStatementImportErrorAlert = false
    @State private var showStatementImportSuccessAlert = false
    @State private var statementImportSuccessCount = 0
    @State private var statementImportMatchedCount = 0
    @State private var isStatementImportParsing = false
    @State private var selectedCategory: String?
    @State private var showingCategoryTransactions = false

    private var walletPeriod: ReportsViewModel.WalletPeriod {
        reportsViewModel.lastUsedWalletPeriod
    }

    private var walletPeriodBinding: Binding<ReportsViewModel.WalletPeriod> {
        Binding(
            get: { reportsViewModel.lastUsedWalletPeriod },
            set: { reportsViewModel.setLastUsedWalletPeriod($0) }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    walletSections
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: reportsViewModel.monthlyReport != nil)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: reportsViewModel.usdBtcReport != nil)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .simultaneousGesture(
                DragGesture(minimumDistance: 44).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy), abs(dx) > 50 else { return }
                    walletSwipeNavigate(forward: dx < 0)
                }
            )
            .refreshable {
                reportsViewModel.loadMonthlyReport()
                reportsViewModel.loadYearWrapReport()
                reportsViewModel.loadWeekReport()
                reportsViewModel.loadUsdBtcReport()
            }
            .navigationTitle(reportsPeriodTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: walletPeriodBinding) {
                        ForEach(ReportsViewModel.WalletPeriod.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingStatementImportPicker = true
                    } label: {
                        // Credit card icon with arrow in the middle (iOS share/export style)
                        ZStack(alignment: .center) {
                            // Credit card outline
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.primary, lineWidth: 1.5)
                                .frame(width: 20, height: 14)
                            
                            // Down arrow centered in the middle of the card
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.primary)
                        }
                        .frame(width: 20, height: 14)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingStatementImportPicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleStatementImportResult(result)
            }
            .sheet(isPresented: $showingStatementImportSheet) {
                StatementImportSheet(
                    fileName: statementImportFileName,
                    transactions: statementImportTransactions,
                    onImport: handleStatementImport
                )
                .environmentObject(accountViewModel)
            }
            .overlay {
                if isStatementImportParsing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Reading CSV…")
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
            .alert("Statement Import Error", isPresented: $showStatementImportErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(statementImportErrorMessage ?? "Something went wrong.")
            }
            .alert("Import successful", isPresented: $showStatementImportSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                if statementImportMatchedCount > 0 {
                    Text("Imported \(statementImportSuccessCount - statementImportMatchedCount) new transaction\(statementImportSuccessCount - statementImportMatchedCount == 1 ? "" : "s") and matched \(statementImportMatchedCount) payment\(statementImportMatchedCount == 1 ? "" : "s") to existing transactions.")
                } else {
                    Text("Imported \(statementImportSuccessCount) transaction\(statementImportSuccessCount == 1 ? "" : "s").")
                }
            }
            .sheet(isPresented: $showingCategoryTransactions) {
                if let category = selectedCategory {
                    CategoryTransactionsView(
                        category: category,
                        period: walletPeriod
                    )
                    .environmentObject(reportsViewModel)
                    .environmentObject(accountViewModel)
                    .environmentObject(bitcoinPriceService)
                }
            }
            .onAppear {
                reportsViewModel.loadMonthlyReport()
                reportsViewModel.loadYearWrapReport()
                reportsViewModel.loadWeekReport()
                reportsViewModel.loadUsdBtcReport()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
            }
            .onChange(of: reportsViewModel.selectedMonth) { _, _ in
                reportsViewModel.loadMonthlyReport()
            }
            .onChange(of: reportsViewModel.lastUsedWalletPeriod) { _, p in
                switch p {
                case .week:
                    reportsViewModel.selectedWeekStart = reportsViewModel.startOfWeek(for: Date())
                    reportsViewModel.loadWeekReport()
                case .month:
                    reportsViewModel.loadMonthlyReport()
                case .year:
                    reportsViewModel.loadYearWrapReport()
                }
            }
            .onChange(of: reportsViewModel.selectedYear) { _, _ in
                if walletPeriod == .year {
                    reportsViewModel.loadYearWrapReport()
                }
            }
            .onChange(of: reportsViewModel.selectedWeekStart) { _, _ in
                if walletPeriod == .week {
                    reportsViewModel.loadWeekReport()
                }
            }
            .onChange(of: reportsViewModel.usdBtcMonthsBack) { _, _ in
                reportsViewModel.loadUsdBtcReport()
            }
        }
    }

    private func handleStatementImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            statementImportFileName = url.lastPathComponent
            isStatementImportParsing = true
            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw NSError(domain: "Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to access the selected file."])
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    let txs = try TransactionCSVParser.parse(data: data)
                    await MainActor.run {
                        statementImportTransactions = txs
                        isStatementImportParsing = false
                        showingStatementImportSheet = true
                    }
                } catch {
                    await MainActor.run {
                        isStatementImportParsing = false
                        statementImportErrorMessage = error.localizedDescription
                        showStatementImportErrorAlert = true
                    }
                }
            }
        case .failure(let error):
            statementImportErrorMessage = "Failed to access file: \(error.localizedDescription)"
            showStatementImportErrorAlert = true
        }
    }

    private func handleStatementImport(account: Account, transactions: [ParsedStatementTransaction]) {
        var importedCount = 0
        var matchedCount = 0
        
        for tx in transactions {
            let usdAmount = tx.isCredit ? tx.amount : -tx.amount
            
            // For credit transactions (payments), try to match to existing transactions
            // Payments are likely already reconciled on the account side, so we check both reconciled and unreconciled
            if tx.isCredit {
                if let matchedEntry = accountViewModel.findMatchingTransaction(
                    account: account,
                    amount: tx.amount,
                    date: tx.date,
                    title: tx.title
                ) {
                    // Match found - skip creating duplicate
                    // If it's already reconciled, we just skip it
                    // If it's unreconciled, mark it as reconciled
                    if !matchedEntry.isReconciledFlag {
                        matchedEntry.isReconciledFlag = true
                        if matchedEntry.notes?.isEmpty != false {
                            matchedEntry.notes = "Reconciled from CSV import"
                        } else {
                            matchedEntry.notes = (matchedEntry.notes ?? "") + " (Reconciled from CSV)"
                        }
                    }
                    matchedCount += 1
                    continue
                }
            }
            
            // No match found or not a credit - create new entry
            accountViewModel.addManualEntry(
                to: account,
                title: tx.title,
                btcAmount: nil,
                usdAmount: usdAmount,
                btcPriceAtTransaction: nil,
                date: tx.date,
                notes: "Imported from CSV",
                isReconciled: true,
                category: nil
            )
            importedCount += 1
        }
        
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        statementImportSuccessCount = importedCount + matchedCount
        statementImportMatchedCount = matchedCount
        showStatementImportSuccessAlert = true
    }

    @ViewBuilder
    private var walletSections: some View {
        if reportsViewModel.isLoading && !walletHasReport {
            Section {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        } else if walletPeriod == .week, let r = reportsViewModel.weeklyReport {
            WalletTotalSpendingAppleCard(
                periodLabel: weekRangeLabel(r.weekStart),
                expenses: r.expenses,
                previousPeriodExpenses: reportsViewModel.previousPeriodExpenses(for: .week),
                periodType: .week,
                barData: .week(r.dailyBreakdown),
                appeared: appeared
            )
            WalletIncomeFeesRows(
                income: r.income,
                fees: r.digitalWalletFees,
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                },
                onFeesTap: {
                    selectedCategory = "Digital Wallet Fees"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    period: .week
                )
            }
            usdBtcBottomSection
        } else if walletPeriod == .month, let r = reportsViewModel.monthlyReport {
            WalletTotalSpendingAppleCard(
                periodLabel: monthYearLabel(reportsViewModel.selectedMonth),
                expenses: r.expenses,
                previousPeriodExpenses: reportsViewModel.previousPeriodExpenses(for: .month),
                periodType: .month,
                barData: .month(r.weeklyBreakdown, month: r.month),
                appeared: appeared
            )
            WalletIncomeFeesRows(
                income: r.income,
                fees: r.digitalWalletFees,
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                },
                onFeesTap: {
                    selectedCategory = "Digital Wallet Fees"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    period: .month
                )
            }
            usdBtcBottomSection
        } else if walletPeriod == .year, let r = reportsViewModel.yearWrapReport {
            WalletTotalSpendingAppleCard(
                periodLabel: String(r.year),
                expenses: r.expenses,
                previousPeriodExpenses: reportsViewModel.previousPeriodExpenses(for: .year),
                periodType: .year,
                barData: .year(r.monthlyBreakdown),
                appeared: appeared
            )
            WalletIncomeFeesRows(
                income: r.income,
                fees: r.digitalWalletFees,
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                },
                onFeesTap: {
                    selectedCategory = "Digital Wallet Fees"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    period: .year
                )
            }
            usdBtcBottomSection
        } else {
            emptySection
        }
    }

    @ViewBuilder
    private var usdBtcBottomSection: some View {
        if hasBtcActivity, let r = reportsViewModel.usdBtcReport {
            UsdBtcRangePickerSection(monthsBack: Binding(get: { reportsViewModel.usdBtcMonthsBack }, set: { reportsViewModel.usdBtcMonthsBack = $0 }))
            UsdBtcValueThenVsNowSection(
                totalUsd: r.totalUsd,
                totalBtcAtTime: r.totalBtcAtTime,
                totalBtcValueNow: r.totalBtcValueNow,
                appeared: appeared
            )
            if !r.months.isEmpty {
                UsdBtcBarsSection(months: r.months, appeared: appeared)
            }
            if r.months.contains(where: { $0.avgBtcPrice > 0 }) {
                UsdBtcPriceFluctuationSection(months: r.months, appeared: appeared)
            }
        }
    }

    private var hasBtcActivity: Bool {
        guard let r = reportsViewModel.usdBtcReport else { return false }
        return (r.totalBtcAtTime as NSDecimalNumber).doubleValue > 0 || (r.totalBtcValueNow as NSDecimalNumber).doubleValue > 0
    }

    private var walletHasReport: Bool {
        switch walletPeriod {
        case .week: return reportsViewModel.weeklyReport != nil
        case .month: return reportsViewModel.monthlyReport != nil
        case .year: return reportsViewModel.yearWrapReport != nil
        }
    }

    private var reportsPeriodTitle: String {
        switch walletPeriod {
        case .week:
            if let r = reportsViewModel.weeklyReport {
                return weekRangeLabel(r.weekStart)
            }
            return "Week"
        case .month:
            return monthYearLabel(reportsViewModel.selectedMonth)
        case .year:
            if let r = reportsViewModel.yearWrapReport {
                return String(r.year)
            }
            return String(reportsViewModel.selectedYear)
        }
    }

    private func weekRangeLabel(_ weekStart: Date) -> String {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let y = DateFormatter()
        y.dateFormat = "yyyy"
        let startY = cal.component(.year, from: weekStart)
        let endY = cal.component(.year, from: end)
        let startStr = startY != endY ? "\(f.string(from: weekStart)), \(y.string(from: weekStart))" : f.string(from: weekStart)
        let endStr = startY != endY ? "\(f.string(from: end)), \(y.string(from: end))" : f.string(from: end)
        return "\(startStr) – \(endStr)"
    }

    private func walletSwipeNavigate(forward: Bool) {
        let cal = Calendar.current
        let delta = forward ? 1 : -1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switch walletPeriod {
            case .week:
                let start = reportsViewModel.startOfWeek(for: reportsViewModel.selectedWeekStart)
                guard let next = cal.date(byAdding: .day, value: delta * 7, to: start) else { return }
                reportsViewModel.selectedWeekStart = next
            case .month:
                guard let next = cal.date(byAdding: .month, value: delta, to: reportsViewModel.selectedMonth) else { return }
                reportsViewModel.selectedMonth = next
            case .year:
                reportsViewModel.selectedYear += delta
            }
        }
    }

    private func monthYearLabel(_ date: Date) -> String {
        let m = Calendar.current.component(.month, from: date)
        let y = Calendar.current.component(.year, from: date)
        return "\(monthName(m)) \(y)"
    }

    private func monthName(_ m: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        guard let d = Calendar.current.date(from: DateComponents(year: 2000, month: m, day: 1)) else { return "" }
        return f.string(from: d)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No data for this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        .listRowBackground(Color.clear)
    }
}

// MARK: - Wallet-style sections

private enum WalletBarData {
    case week([(day: Date, expenses: Decimal)])
    case month([Decimal], month: Date)
    case year([(month: Date, income: Decimal, expenses: Decimal, fees: Decimal)])
}

private let appleWalletBarGradients: [LinearGradient] = [
    LinearGradient(colors: [.orange, .pink], startPoint: .bottom, endPoint: .top),
    LinearGradient(colors: [.pink, .purple], startPoint: .bottom, endPoint: .top),
    LinearGradient(colors: [.purple, .blue], startPoint: .bottom, endPoint: .top),
    LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top),
]

private struct WalletTotalSpendingAppleCard: View {
    let periodLabel: String
    let expenses: Decimal
    let previousPeriodExpenses: Decimal?
    let periodType: ReportsViewModel.WalletPeriod
    let barData: WalletBarData
    let appeared: Bool
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private var comparisonText: String? {
        guard let previous = previousPeriodExpenses, previous > 0 else { return nil }
        let difference = expenses - previous
        let absDifference = abs(difference)
        let periodName: String = {
            switch periodType {
            case .week: return "last week"
            case .month: return "last month"
            case .year: return "last year"
            }
        }()
        
        if abs(difference) < 0.01 {
            return "Same as \(periodName)"
        }
        
        let diffString = formatter.string(from: absDifference as NSDecimalNumber) ?? "$0.00"
        if difference > 0 {
            return "\(diffString) more than \(periodName)"
        } else {
            return "\(diffString) less than \(periodName)"
        }
    }
    
    private var comparisonColor: Color {
        guard let previous = previousPeriodExpenses, previous > 0 else { return .secondary }
        let difference = expenses - previous
        if abs(difference) < 0.01 {
            return .secondary
        }
        return difference > 0 ? .red : .green
    }
    
    private var arrowIcon: String? {
        guard let previous = previousPeriodExpenses, previous > 0 else { return nil }
        let difference = expenses - previous
        if abs(difference) < 0.01 {
            return "arrow.right"
        }
        return difference > 0 ? "arrow.up" : "arrow.down"
    }
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Total Spending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formatter.string(from: expenses as NSDecimalNumber) ?? "$0.00")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                walletBarChart
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var walletBarChart: some View {
        switch barData {
        case .week:
            return AnyView(WalletStackedCategoryBarChart(
                period: .week,
                appeared: appeared,
                showEveryNthLabel: nil
            ))
        case .month:
            return AnyView(WalletStackedCategoryBarChart(
                period: .month,
                appeared: appeared,
                showEveryNthLabel: nil
            ))
        case .year:
            return AnyView(WalletStackedCategoryBarChart(
                period: .year,
                appeared: appeared,
                showEveryNthLabel: 2  // Show every 2nd month (6 labels for 12 months)
            ))
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

// MARK: - Stacked Category Bar Chart

private struct WalletStackedCategoryBarChart: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let period: ReportsViewModel.WalletPeriod
    let appeared: Bool
    let showEveryNthLabel: Int?
    
    // Enhanced color palette for categories
    private let categoryColors: [Color] = [
        .orange, .pink, .purple, .blue, .green, .mint, .cyan, .teal,
        .indigo, .red, .yellow, .brown, .gray
    ]
    
    private var categoryBreakdown: [(period: String, categories: [(name: String, amount: Decimal)])] {
        reportsViewModel.categoryBreakdownByPeriod(period: period)
    }
    
    private var allCategories: [String] {
        var categories: Set<String> = []
        for item in categoryBreakdown {
            for cat in item.categories {
                categories.insert(cat.name)
            }
        }
        return Array(categories).sorted()
    }
    
    private func colorForCategory(_ categoryName: String) -> Color {
        if let index = allCategories.firstIndex(of: categoryName) {
            return categoryColors[index % categoryColors.count]
        }
        return .gray
    }
    
    // Create gradient that blends categories smoothly based on their values
    private func gradientForPeriod(_ categories: [(name: String, amount: Decimal)]) -> LinearGradient {
        guard !categories.isEmpty else {
            return LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .bottom, endPoint: .top)
        }
        
        let totalAmount = categories.reduce(Decimal(0)) { $0 + $1.amount }
        guard totalAmount > 0 else {
            return LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .bottom, endPoint: .top)
        }
        
        // Sort categories by amount (largest first, at bottom)
        let sortedCategories = categories.sorted { $0.amount > $1.amount }
        
        if sortedCategories.count == 1 {
            let color = colorForCategory(sortedCategories[0].name)
            return LinearGradient(
                colors: [color, color],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        
        // Create gradient stops - each category gets proportional space based on its value
        // Larger category values = larger proportion = more dominant color in the gradient
        var gradientStops: [Gradient.Stop] = []
        var cumulativeLocation: Double = 0.0
        
        for (index, category) in sortedCategories.enumerated() {
            // Calculate proportion: larger amounts = larger proportion = more color dominance
            let categoryAmount = (category.amount as NSDecimalNumber).doubleValue
            let proportion = categoryAmount / (totalAmount as NSDecimalNumber).doubleValue
            let color = colorForCategory(category.name)
            
            // Add stop at start of this category's segment
            // For the first category, start at 0.0
            if index == 0 {
                gradientStops.append(Gradient.Stop(color: color, location: 0.0))
            } else {
                // For subsequent categories, add blend point with previous color
                let prevColor = colorForCategory(sortedCategories[index - 1].name)
                gradientStops.append(Gradient.Stop(color: prevColor, location: cumulativeLocation))
                gradientStops.append(Gradient.Stop(color: color, location: cumulativeLocation))
            }
            
            // Move to end of this category's segment (proportional to its value)
            cumulativeLocation += proportion
            
            // Add stop at end of this category's segment
            gradientStops.append(Gradient.Stop(color: color, location: min(cumulativeLocation, 1.0)))
        }
        
        // Ensure final stop is exactly at 1.0
        if let lastStop = gradientStops.last, lastStop.location < 1.0 {
            gradientStops.append(Gradient.Stop(color: lastStop.color, location: 1.0))
        }
        
        // Sort stops by location and remove duplicates
        var uniqueStops: [Gradient.Stop] = []
        var lastLocation: Double = -1.0
        for stop in gradientStops.sorted(by: { $0.location < $1.location }) {
            // Only add if location is different (with small tolerance for floating point)
            if abs(stop.location - lastLocation) > 0.0001 {
                uniqueStops.append(stop)
                lastLocation = stop.location
            }
        }
        
        return LinearGradient(
            gradient: Gradient(stops: uniqueStops),
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()
    
    private var maxValue: Double {
        let values = categoryBreakdown.map { period in
            period.categories.reduce(Decimal(0)) { $0 + $1.amount }
        }.map { ($0 as NSDecimalNumber).doubleValue }
        return max(values.max() ?? 0, 1)
    }
    
    private func actualValue(for periodData: (period: String, categories: [(name: String, amount: Decimal)])) -> Double {
        let totalAmount = periodData.categories.reduce(Decimal(0)) { $0 + $1.amount }
        return (totalAmount as NSDecimalNumber).doubleValue
    }
    
    private func formatAmount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        } else {
            return formatter.string(from: NSNumber(value: value)) ?? "$0"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                // Create a bar for each period using the period string as X-axis value
                ForEach(categoryBreakdown, id: \.period) { periodData in
                    let totalAmount = actualValue(for: periodData)
                    
                    if totalAmount > 0 {
                        let gradient = gradientForPeriod(periodData.categories)
                        BarMark(
                            x: .value("Period", periodData.period),
                            y: .value("Amount", totalAmount)
                        )
                        .foregroundStyle(gradient)
                        .cornerRadius(4)
                    } else {
                        // Empty period - show invisible bar to maintain X-axis spacing
                        BarMark(
                            x: .value("Period", periodData.period),
                            y: .value("Amount", 0.0)
                        )
                        .foregroundStyle(Color.clear)
                        .opacity(0)
                    }
                }
            }
            .chartXAxis {
                let periodValues = categoryBreakdown.map { $0.period }
                
                if let nth = showEveryNthLabel {
                    let labelIndices = (0..<categoryBreakdown.count).filter { $0 % nth == 0 }
                    let visiblePeriods = labelIndices.compactMap { index -> String? in
                        guard index < periodValues.count else { return nil }
                        return periodValues[index]
                    }
                    AxisMarks(values: .automatic) { value in
                        if let stringValue = value.as(String.self),
                           visiblePeriods.contains(stringValue) {
                            AxisValueLabel {
                                Text(stringValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .automatic) { value in
                        if let stringValue = value.as(String.self),
                           periodValues.contains(stringValue) {
                            AxisValueLabel {
                                Text(stringValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                let maxVal = max(maxValue, 1)
                let step = maxVal / 4.0
                let mainValues: [Double] = [0, step, step * 2, step * 3, maxVal]
                
                AxisMarks(position: .trailing, values: mainValues) { value in
                    if let doubleValue = value.as(Double.self) {
                        AxisValueLabel {
                            Text(formatAmount(doubleValue))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.2))
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .opacity(appeared ? 1 : 0)
    }
}

private struct WalletAppleBarChart: View {
    let labels: [String]
    let values: [Decimal]
    let showEveryNthLabel: Int? // For year view, show every Nth label (e.g., 3 = every 3rd month)
    let comparisonText: String?
    let comparisonColor: Color
    let appeared: Bool
    
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()
    
    private var maxValue: Double {
        values.map { ($0 as NSDecimalNumber).doubleValue }.max() ?? 0
    }
    
    private func formatAmount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        } else {
            return formatter.string(from: NSNumber(value: value)) ?? "$0"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    BarMark(
                        x: .value("Period", label),
                        y: .value("Amount", (values[i] as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(appleWalletBarGradients[i % appleWalletBarGradients.count])
                    .cornerRadius(6)
                }
            }
            .chartXAxis {
                if let nth = showEveryNthLabel {
                    // For year view, use explicit values to show only every Nth label
                    let labelIndices = (0..<labels.count).filter { $0 % nth == 0 }
                    AxisMarks(values: .automatic) { value in
                        if let stringValue = value.as(String.self),
                           let index = labels.firstIndex(of: stringValue),
                           labelIndices.contains(index) {
                            AxisValueLabel()
                                .font(.caption2)
                        }
                        // Don't show label for other positions
                    }
                } else {
                    // For week/month, show all labels
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
            }
            .chartYAxis {
                let maxVal = max(maxValue, 100) // Ensure we have a minimum range
                let quarter = maxVal / 4.0
                // Create 4 main values (quarters) and 4 midpoints
                let mainValues: [Double] = [0, quarter, quarter * 2, quarter * 3, maxVal]
                let midpointValues: [Double] = [quarter * 0.5, quarter * 1.5, quarter * 2.5, quarter * 3.5]
                let allValues = (mainValues + midpointValues).sorted()
                
                AxisMarks(position: .trailing, values: allValues) { value in
                    if let doubleValue = value.as(Double.self) {
                        // Check if this is a main quarter value
                        let isMainValue = mainValues.contains { abs($0 - doubleValue) < 0.01 }
                        
                        if isMainValue {
                            // Show label and solid line for main quarter values
                            AxisValueLabel {
                                Text(formatAmount(doubleValue))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary.opacity(0.3))
                        } else {
                            // Show dashed line for midpoints, no label
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(.secondary.opacity(0.2))
                        }
                    }
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            if let compText = comparisonText {
                Text(compText)
                    .font(.caption)
                    .foregroundStyle(comparisonColor)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
    }
}

private struct WalletIncomeFeesRows: View {
    let income: Decimal
    let fees: Decimal
    let appeared: Bool
    let onIncomeTap: () -> Void
    let onFeesTap: () -> Void
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    var body: some View {
        Section {
            VStack(spacing: 0) {
                WalletSummaryRow(
                    icon: "arrow.down.circle.fill",
                    iconColor: .green,
                    title: "Income",
                    amount: income,
                    formatter: formatter,
                    appeared: appeared,
                    onTap: onIncomeTap
                )
                if fees > 0 {
                    Divider()
                        .padding(.leading, 52)
                    WalletSummaryRow(
                        icon: "bitcoinsign.circle.fill",
                        iconColor: .orange,
                        title: "Digital Wallet Fees",
                        amount: fees,
                        formatter: formatter,
                        appeared: appeared,
                        onTap: onFeesTap
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct WalletSummaryRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let amount: Decimal
    let formatter: NumberFormatter
    let appeared: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.15)))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatter.string(from: amount as NSDecimalNumber) ?? "$0.00")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WalletCategorySection: View {
    let items: [(name: String, amount: Decimal)]
    let appeared: Bool
    let onCategoryTap: (String) -> Void
    let period: ReportsViewModel.WalletPeriod
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @State private var showingPieChart = false
    @State private var pieChartScale: CGFloat = 1.0
    @State private var pieChartRotation: Double = 0
    @State private var pieChartOpacity: Double = 1.0
    @State private var categoryListOffset: CGFloat = 0
    @State private var categoryListOpacity: Double = 1.0
    @State private var legendOffset: CGFloat = 0
    @State private var legendOpacity: Double = 1.0
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()
    
    // Enhanced color palette with visually appealing, vibrant colors
    private let categoryColorPalette: [Color] = [
        .orange, .pink, .purple, .blue, .green, .mint, .cyan, .teal,
        .indigo, .red, .yellow, .brown, .gray, .blue.opacity(0.8), .purple.opacity(0.8)
    ]
    
    // Create smooth gradient transitions between categories
    private func gradientForCategories(_ categories: [(name: String, amount: Decimal)], startIndex: Int) -> LinearGradient {
        guard !categories.isEmpty else {
            return LinearGradient(colors: [.gray], startPoint: .bottom, endPoint: .top)
        }
        
        // Get colors for all categories in this period
        let colors = categories.enumerated().map { index, _ in
            categoryColorPalette[(startIndex + index) % categoryColorPalette.count]
        }
        
        // Create a gradient that blends all category colors
        // The gradient goes from bottom (first category) to top (last category)
        return LinearGradient(
            colors: colors,
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    // Calculate total spending across all categories
    private var totalSpending: Decimal {
        items.reduce(0) { $0 + $1.amount }
    }
    
    // Get color for category based on its index (ensures each category gets a unique color)
    // Colors are synced between list and pie chart
    private func colorForIndex(_ index: Int) -> Color {
        return categoryColorPalette[index % categoryColorPalette.count]
    }
    
    // Get all colors for the items (used for pie chart)
    private var itemColors: [Color] {
        return items.prefix(8).enumerated().map { index, _ in
            colorForIndex(index)
        }
    }
    
    private func iconForCategory(_ categoryName: String) -> String {
        let lowercased = categoryName.lowercased()
        
        // Credit Card / Debt Payment
        if lowercased.contains("credit") || lowercased.contains("debt") {
            return "creditcard"
        }
        
        // Housing
        if lowercased.contains("housing") || lowercased.contains("rent") || lowercased.contains("mortgage") {
            return "house"
        }
        
        // Food & Dining
        if lowercased.contains("food") || lowercased.contains("dining") || lowercased.contains("grocery") {
            return "fork.knife"
        }
        
        // Transportation
        if lowercased.contains("transportation") || lowercased.contains("gas") || lowercased.contains("fuel") {
            return "car"
        }
        
        // Utilities
        if lowercased.contains("utilities") || lowercased.contains("utility") || lowercased.contains("electric") || lowercased.contains("water") || lowercased.contains("internet") {
            return "bolt.fill"
        }
        
        // Healthcare
        if lowercased.contains("healthcare") || lowercased.contains("health") || lowercased.contains("medical") {
            return "cross.case.fill"
        }
        
        // Insurance
        if lowercased.contains("insurance") {
            return "shield.fill"
        }
        
        // Entertainment
        if lowercased.contains("entertainment") {
            return "tv.fill"
        }
        
        // Shopping
        if lowercased.contains("shopping") {
            return "bag.fill"
        }
        
        // Personal Care
        if lowercased.contains("personal care") || lowercased.contains("care") {
            return "sparkles"
        }
        
        // Education
        if lowercased.contains("education") {
            return "book.fill"
        }
        
        // Subscriptions
        if lowercased.contains("subscription") {
            return "repeat"
        }
        
        // Savings
        if lowercased.contains("savings") {
            return "banknote.fill"
        }
        
        // Investments
        if lowercased.contains("investment") {
            return "chart.line.uptrend.xyaxis"
        }
        
        // Gifts & Donations
        if lowercased.contains("gift") || lowercased.contains("donation") {
            return "gift.fill"
        }
        
        // Travel
        if lowercased.contains("travel") {
            return "airplane"
        }
        
        // Business
        if lowercased.contains("business") {
            return "briefcase.fill"
        }
        
        // Default fallback
        return "dollarsign.circle.fill"
    }
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Category")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        if showingPieChart {
                            // Closing animation - reverse of opening
                            // First, animate legend out (down)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                legendOffset = 200
                                legendOpacity = 0
                            }
                            // Then animate pie chart out (scale down, rotate, fade)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    pieChartScale = 0.1
                                    pieChartRotation = -360
                                    pieChartOpacity = 0
                                }
                            }
                            // Then animate category list back in (up from bottom)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingPieChart = false
                                // Reset pie chart state for next opening
                                pieChartScale = 1.0
                                pieChartRotation = 0
                                pieChartOpacity = 1.0
                                legendOffset = 0
                                legendOpacity = 1.0
                                // Animate category list back up from bottom
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    categoryListOffset = 0
                                    categoryListOpacity = 1.0
                                }
                            }
                        } else {
                            // Opening animation
                            // First, animate category list out (down)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                categoryListOffset = 200
                                categoryListOpacity = 0
                            }
                            // Then show pie chart and animate it in from its final position
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showingPieChart = true
                                // Start from small scale and rotated
                                pieChartScale = 0.1
                                pieChartRotation = 360
                                pieChartOpacity = 0
                                legendOffset = 200
                                legendOpacity = 0
                                // Animate pie chart to final position (scale 1, rotation 0)
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    pieChartScale = 1.0
                                    pieChartRotation = 0
                                    pieChartOpacity = 1.0
                                }
                                // Animate legend in (up from bottom) with slight delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        legendOffset = 0
                                        legendOpacity = 1.0
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: showingPieChart ? "xmark.circle.fill" : "chart.pie.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.bounce, value: showingPieChart)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                
                if showingPieChart {
                    VStack(spacing: 12) {
                        // Pie chart with its own animations
                        CategoryPieChart(
                            items: items,
                            colors: itemColors,
                            appeared: appeared
                        )
                        .scaleEffect(pieChartScale)
                        .rotationEffect(.degrees(pieChartRotation))
                        .opacity(pieChartOpacity)
                        
                        // Legend with separate animations
                        CategoryPieChartLegend(
                            items: items,
                            colors: itemColors,
                            legendOffset: legendOffset,
                            legendOpacity: legendOpacity
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { i, item in
                            let previousAmount = reportsViewModel.previousPeriodCategorySpending(item.name, period: period)
                            WalletCategoryRow(
                                icon: iconForCategory(item.name),
                                color: colorForIndex(i),
                                name: item.name,
                                amount: item.amount,
                                previousAmount: previousAmount,
                                formatter: formatter,
                                appeared: appeared,
                                onTap: {
                                    onCategoryTap(item.name)
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            if i < min(8, items.count) - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .offset(y: categoryListOffset)
                    .opacity(categoryListOpacity)
                }
            }
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct CategoryPieChart: View {
    let items: [(name: String, amount: Decimal)]
    let colors: [Color] // Keep for pie chart segments
    let appeared: Bool
    @State private var segmentAppeared: [Bool] = []
    
    private var totalAmount: Decimal {
        items.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        Chart {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { i, item in
                let isVisible = i < segmentAppeared.count && segmentAppeared[i]
                SectorMark(
                    angle: .value("Amount", isVisible ? item.amount : 0),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(colors[i % colors.count])
                .opacity(isVisible ? 1 : 0)
            }
        }
        .frame(height: 200)
        .onAppear {
            let itemCount = min(8, items.count)
            segmentAppeared = Array(repeating: false, count: itemCount)
            
            // Animate each segment with a staggered delay
            for i in 0..<itemCount {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1 + Double(i) * 0.08)) {
                    segmentAppeared[i] = true
                }
            }
        }
        .onDisappear {
            segmentAppeared = []
        }
    }
}

private struct CategoryPieChartLegend: View {
    let items: [(name: String, amount: Decimal)]
    let colors: [Color]
    let legendOffset: CGFloat
    let legendOpacity: Double
    @State private var segmentAppeared: [Bool] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { i, item in
                let isVisible = i < segmentAppeared.count && segmentAppeared[i]
                HStack(spacing: 8) {
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: 12, height: 12)
                    Text(item.name)
                        .font(.caption)
                    Spacer()
                }
                .opacity(isVisible ? legendOpacity : 0)
                .offset(x: isVisible ? 0 : -20, y: legendOffset)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            let itemCount = min(8, items.count)
            segmentAppeared = Array(repeating: false, count: itemCount)
            
            // Animate each legend item with a staggered delay
            for i in 0..<itemCount {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1 + Double(i) * 0.08)) {
                    segmentAppeared[i] = true
                }
            }
        }
        .onDisappear {
            segmentAppeared = []
        }
    }
}

private struct WalletCategoryRow: View {
    let icon: String
    let color: Color
    let name: String
    let amount: Decimal
    let previousAmount: Decimal
    let formatter: NumberFormatter
    let appeared: Bool
    let onTap: () -> Void
    
    private var trendIndicator: (icon: String, color: Color)? {
        guard previousAmount > 0 else { return nil }
        let change = amount - previousAmount
        let percentChange = abs(change / previousAmount)
        
        // Only show if change is significant (>5%)
        guard percentChange > 0.05 else { return nil }
        
        if change > 0 {
            return ("arrow.up", .red)
        } else {
            return ("arrow.down", .green)
        }
    }
    
    private var trendText: String? {
        guard previousAmount > 0 else { return nil }
        let change = amount - previousAmount
        let percentChange = abs(change / previousAmount)
        
        guard percentChange > 0.05 else { return nil }
        
        let percentValue = (percentChange * Decimal(100)) as NSDecimalNumber
        let percent = Int(percentValue.doubleValue.rounded())
        if change > 0 {
            return "+\(percent)%"
        } else {
            return "-\(percent)%"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.15)))
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatter.string(from: amount as NSDecimalNumber) ?? "$0")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let trend = trendIndicator {
                            Image(systemName: trend.icon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(trend.color)
                        }
                    }
                    if let trend = trendText, let indicator = trendIndicator {
                        Text(trend)
                            .font(.caption2)
                            .foregroundStyle(indicator.color.opacity(0.8))
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - USD vs BTC

private struct UsdBtcRangePickerSection: View {
    @Binding var monthsBack: Int
    private let options = [(12, "1 year"), (24, "2 years"), (48, "4 years")]

    var body: some View {
        Section {
            Picker("Time range", selection: $monthsBack) {
                ForEach(options, id: \.0) { months, label in
                    Text(label).tag(months)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("USD vs BTC")
        } footer: {
            Text("Bills paid in USD vs Bitcoin. Bitcoin amounts shown in USD at payment time; \"value today\" uses current BTC price.")
        }
    }
}

private struct UsdBtcValueThenVsNowSection: View {
    let totalUsd: Decimal
    let totalBtcAtTime: Decimal
    let totalBtcValueNow: Decimal
    let appeared: Bool

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    var body: some View {
        Section {
            UsdBtcValueRow(
                label: "Bills in USD",
                icon: "dollarsign.circle.fill",
                color: .blue,
                amount: totalUsd,
                formatter: formatter,
                appeared: appeared
            )
            UsdBtcValueRow(
                label: "BTC bills (value when paid)",
                icon: "bitcoinsign.circle.fill",
                color: .orange,
                amount: totalBtcAtTime,
                formatter: formatter,
                appeared: appeared
            )
            UsdBtcValueRow(
                label: "Same BTC (value today)",
                icon: "chart.line.uptrend.xyaxis",
                color: totalBtcValueNow >= totalBtcAtTime ? .green : .red,
                amount: totalBtcValueNow,
                formatter: formatter,
                appeared: appeared
            )
            if totalBtcAtTime > 0 {
                UsdBtcDeltaRow(
                    totalBtcAtTime: totalBtcAtTime,
                    totalBtcValueNow: totalBtcValueNow,
                    formatter: formatter,
                    appeared: appeared
                )
            }
        } header: {
            Text("Value then vs now")
        }
    }
}

private struct UsdBtcValueRow: View {
    let label: String
    let icon: String
    let color: Color
    let amount: Decimal
    let formatter: NumberFormatter
    let appeared: Bool
    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(formatter.string(from: amount as NSDecimalNumber) ?? "$0.00")
                .fontWeight(.semibold)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
    }
}

private struct UsdBtcDeltaRow: View {
    let totalBtcAtTime: Decimal
    let totalBtcValueNow: Decimal
    let formatter: NumberFormatter
    let appeared: Bool
    private var delta: Decimal { totalBtcValueNow - totalBtcAtTime }
    var body: some View {
        HStack {
            Text("Difference (price fluctuation)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text((delta >= 0 ? "+" : "") + (formatter.string(from: delta as NSDecimalNumber) ?? "$0"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(delta >= 0 ? .green : .red)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
    }
}

private struct UsdBtcBarsSection: View {
    let months: [(month: Date, usdExpenses: Decimal, btcAtTime: Decimal, btcValueNow: Decimal, avgBtcPrice: Decimal)]
    let appeared: Bool

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f
    }()

    var body: some View {
        Section {
            Chart {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                    BarMark(
                        x: .value("Month", monthFormatter.string(from: m.month)),
                        y: .value("USD", (m.usdExpenses as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    BarMark(
                        x: .value("Month", monthFormatter.string(from: m.month)),
                        y: .value("BTC", (m.btcAtTime as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(Color.orange.gradient)
                }
            }
            .chartYAxis { AxisMarks(values: .automatic) }
            .frame(height: 200)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.95)
        } header: {
            Text("Bills over time")
        }
    }
}

private struct UsdBtcPriceFluctuationSection: View {
    let months: [(month: Date, usdExpenses: Decimal, btcAtTime: Decimal, btcValueNow: Decimal, avgBtcPrice: Decimal)]
    let appeared: Bool

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f
    }()

    var body: some View {
        let withPrice = months.filter { $0.avgBtcPrice > 0 }
        Group {
            if !withPrice.isEmpty {
                Section {
                    Chart {
                        ForEach(Array(withPrice.enumerated()), id: \.offset) { _, m in
                            LineMark(
                                x: .value("Month", monthFormatter.string(from: m.month)),
                                y: .value("BTC price", (m.avgBtcPrice as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(Color.orange.gradient)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Month", monthFormatter.string(from: m.month)),
                                y: .value("BTC price", (m.avgBtcPrice as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(Color.orange)
                            .symbolSize(20)
                        }
                    }
                    .chartYAxis { AxisMarks(values: .automatic) }
                    .frame(height: 160)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.95)
                } header: {
                    Text("BTC price at payment")
                } footer: {
                    Text("Average BTC/USD price when you paid each bill. Shows fluctuation over time.")
                }
            }
        }
    }
}

// MARK: - Category Transactions View

private struct CategoryTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let category: String
    let period: ReportsViewModel.WalletPeriod
    
    @State private var entries: [LedgerEntry] = []
    @State private var ledgerEntryToEdit: LedgerEntry?
    @State private var showLedgerEditor = false
    @State private var ledgerEntryToDelete: LedgerEntry?
    @State private var showLedgerDeleteAlert = false
    
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }
    
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet",
                        description: Text("No transactions found for \(category) in this period.")
                    )
                } else {
                    ForEach(entries, id: \.objectID) { entry in
                        CategoryTransactionRow(
                            entry: entry,
                            category: category,
                            formatter: formatter,
                            dateFormatter: dateFormatter,
                            onEdit: {
                                ledgerEntryToEdit = entry
                                showLedgerEditor = true
                            },
                            onDelete: {
                                ledgerEntryToDelete = entry
                                showLedgerDeleteAlert = true
                            }
                        )
                    }
                }
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showLedgerEditor) {
                if let entry = ledgerEntryToEdit {
                    CategoryLedgerEntryEditorSheet(
                        entry: entry,
                        onSave: handleEntrySave
                    )
                    .environmentObject(accountViewModel)
                    .environmentObject(bitcoinPriceService)
                }
            }
            .alert("Delete Entry", isPresented: $showLedgerDeleteAlert, presenting: ledgerEntryToDelete) { entry in
                Button("Delete", role: .destructive) {
                    accountViewModel.deleteLedgerEntry(entry)
                    loadEntries()
                }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("This will remove the ledger entry permanently.")
            }
            .onAppear {
                loadEntries()
            }
        }
    }
    
    private func loadEntries() {
        if category == "Income" {
            entries = reportsViewModel.fetchIncomeEntries(period: period)
        } else if category == "Digital Wallet Fees" {
            entries = reportsViewModel.fetchFeeEntries(period: period)
        } else {
            entries = reportsViewModel.fetchEntriesByCategory(category, period: period)
        }
    }
    
    private func handleEntrySave(date: Date, title: String, btcAmount: Decimal?, usdAmount: Decimal?, btcPrice: Decimal?, isCleared: Bool, notes: String?, category: String?) {
        guard let entry = ledgerEntryToEdit else { return }
        accountViewModel.updateLedgerEntry(
            entry,
            date: date,
            title: title,
            btcAmount: btcAmount,
            usdAmount: usdAmount,
            btcPrice: btcPrice,
            isReconciled: isCleared,
            notes: notes,
            category: category
        )
        loadEntries()
    }
}

// Wrapper to access the private LedgerEntryEditorSheet
private struct CategoryLedgerEntryEditorSheet: View {
    let entry: LedgerEntry
    let onSave: (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void
    
    var body: some View {
        // Use the same editor structure as BalanceView
        LedgerEntryEditorView(entry: entry, onSave: onSave)
    }
}

// Replicate the editor functionality here since LedgerEntryEditorSheet is private
private struct LedgerEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @StateObject private var categoryManager = CategoryManager()
    
    let entry: LedgerEntry
    let onSave: (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void
    
    @State private var date: Date
    @State private var title: String
    @State private var btcSatsAmountString: String = ""
    @State private var usdAmountString: String = ""
    @State private var btcPriceString: String = ""
    @State private var isCleared: Bool
    @State private var notes: String
    @State private var category: String
    
    init(entry: LedgerEntry, onSave: @escaping (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _date = State(initialValue: entry.date ?? Date())
        _title = State(initialValue: entry.title ?? "")
        _isCleared = State(initialValue: entry.isReconciledFlag)
        _notes = State(initialValue: entry.notes ?? "")
        _category = State(initialValue: entry.category ?? "")
        
        if let btc = entry.btcAmountDecimal as NSDecimalNumber? {
            _btcSatsAmountString = State(initialValue: String(format: "%.0f", btc.doubleValue))
        }
        if let usd = entry.usdAmountDecimal as NSDecimalNumber? {
            _usdAmountString = State(initialValue: String(format: "%.2f", usd.doubleValue))
        }
        if let price = entry.btcPriceAtTransactionDecimal as NSDecimalNumber? {
            _btcPriceString = State(initialValue: String(format: "%.2f", price.doubleValue))
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        TextField("Title", text: $title)
                        if !title.isEmpty {
                            Button {
                                title = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                }
                
                if let account = entry.account, account.currencyCode == "BTC" {
                    Section("Bitcoin Amount") {
                        HStack {
                            TextField("Sats", text: $btcSatsAmountString)
                                .keyboardType(.numberPad)
                            if !btcSatsAmountString.isEmpty {
                                Button {
                                    btcSatsAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                    Section("USD Amount") {
                        HStack {
                            TextField("Amount", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                            if !usdAmountString.isEmpty {
                                Button {
                                    usdAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                    Section("BTC Price") {
                        HStack {
                            TextField("Price", text: $btcPriceString)
                                .keyboardType(.decimalPad)
                            if !btcPriceString.isEmpty {
                                Button {
                                    btcPriceString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                } else {
                    Section("Amount") {
                        HStack {
                            TextField("Amount", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                            if !usdAmountString.isEmpty {
                                Button {
                                    usdAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Reconciled", isOn: $isCleared)
                    HStack(alignment: .top) {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                        if !notes.isEmpty {
                            Button {
                                notes = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                
                Section {
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                }
            }
        }
    }
    
    private func saveEntry() {
        let btcAmount: Decimal? = {
            if let sats = Int(btcSatsAmountString), sats != 0 {
                return Decimal(sats)
            }
            return nil
        }()
        
        let usdAmount: Decimal? = {
            let cleaned = usdAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            if let amount = Decimal(string: cleaned), amount != 0 {
                return amount
            }
            return nil
        }()
        
        let btcPrice: Decimal? = {
            let cleaned = btcPriceString.replacingOccurrences(of: ",", with: "")
            if let price = Decimal(string: cleaned), price > 0 {
                return price
            }
            return nil
        }()
        
        let categoryValue = category.isEmpty ? nil : category
        
        onSave(date, title, btcAmount, usdAmount, btcPrice, isCleared, notes.isEmpty ? nil : notes, categoryValue)
        dismiss()
    }
}

private struct CategoryTransactionRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let entry: LedgerEntry
    let category: String
    let formatter: NumberFormatter
    let dateFormatter: DateFormatter
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var usdAmount: Decimal {
        // For fees, extract fee amount from notes
        if category == "Digital Wallet Fees" {
            return FeeParsing.feeFromNotes(entry.notes)
        }
        
        guard let account = entry.account else { return .zero }
        // Calculate USD amount similar to ReportsViewModel
        let signed: Decimal
        if account.currencyCode == "BTC" {
            let usd = entry.usdAmountDecimal
            if usd != 0 {
                signed = entry.isCredit ? usd : -usd
            } else {
                let btc = entry.amountInCurrency(for: account)
                let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : bitcoinPriceService.btcToUsdRate
                let usdVal = btc * price
                signed = entry.isCredit ? usdVal : -usdVal
            }
        } else {
            let amt = entry.usdAmountDecimal != 0 ? entry.usdAmountDecimal : entry.amountDecimal
            signed = entry.isCredit ? amt : -amt
        }
        return signed
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title ?? "Untitled")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    if let date = entry.date {
                        Text(dateFormatter.string(from: date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let account = entry.account {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(account.name ?? "Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if category == "Income" {
                    // Income is always positive
                    Text(formatter.string(from: abs(usdAmount) as NSDecimalNumber) ?? "$0.00")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if category == "Digital Wallet Fees" {
                    // Fees are always positive
                    Text(formatter.string(from: abs(usdAmount) as NSDecimalNumber) ?? "$0.00")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    // Categories can be positive or negative
                    Text(formatter.string(from: abs(usdAmount) as NSDecimalNumber) ?? "$0.00")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(usdAmount < 0 ? .red : .green)
                }
                if let entryCategory = entry.category, !entryCategory.isEmpty, category != "Income" && category != "Digital Wallet Fees" {
                    Text(entryCategory)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selection: String
    let usage: [String: CategoryUsage]
    @EnvironmentObject private var categoryManager: CategoryManager
    
    @State private var showingAddCategorySheet = false
    @State private var newCategoryName = ""
    
    private let addNewCategoryTag = "___ADD_NEW_CATEGORY___"
    
    var body: some View {
        HStack {
            Menu {
                Button {
                    selection = ""
                } label: {
                    HStack {
                        Text("None")
                        if selection.isEmpty {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                ForEach(categoryManager.displayCategories(usage: usage, selected: selection), id: \.self) { category in
                    Button {
                        selection = category
                    } label: {
                        HStack {
                            Text(category)
                            if selection == category {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    showingAddCategorySheet = true
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                }
            } label: {
                Text("Category")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(selection.isEmpty ? "None" : selection)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showingAddCategorySheet) {
            AddCategorySheet(
                categoryName: $newCategoryName,
                onSave: {
                    let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        categoryManager.addCategory(trimmed)
                        selection = trimmed
                        newCategoryName = ""
                    }
                    showingAddCategorySheet = false
                },
                onCancel: {
                    newCategoryName = ""
                    showingAddCategorySheet = false
                }
            )
        }
    }
}

private struct AddCategorySheet: View {
    @Binding var categoryName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Category Name", text: $categoryName)
                            .focused($isTextFieldFocused)
                            .autocapitalization(.words)
                            .autocorrectionDisabled()
                        if !categoryName.isEmpty {
                            Button {
                                categoryName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                } header: {
                    Text("Enter a new category name")
                } footer: {
                    Text("This category will be added to your custom categories.")
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let ctx = PersistenceController.shared.container.viewContext
    let vm = ReportsViewModel(context: ctx, bitcoinPriceService: .shared)
    let accountVM = AccountViewModel(context: ctx)
    return ReportsView()
        .environmentObject(vm)
        .environmentObject(BitcoinPriceService.shared)
        .environmentObject(accountVM)
}
