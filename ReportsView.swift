//
//  ReportsView.swift
//  BillsAndBalance
//
//  Activity reports: Week/Month/Year, Total Spending, Income, Fees, By Category.
//  Presented as fullScreenCover — own NavigationStack, X + period picker in toolbar. Main toolbar (Balance/tab bar) not shown.
//

import SwiftUI
import Charts
import UIKit

// MARK: - Reports View

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
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
    @State private var expandedCategories: Set<String> = []
    @State private var selectedTransaction: LedgerEntry?
    @State private var showingTransactionEditor = false

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
            periodSwipeContainer
                .refreshable {
                    reportsViewModel.loadMonthlyReport()
                    reportsViewModel.loadYearWrapReport()
                    reportsViewModel.loadWeekReport()
                }
                .navigationTitle("Activity")
                .navigationBarTitleDisplayMode(.inline)
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
                        periodPickerWithDoubleTap
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingStatementImportPicker = true
                        } label: {
                            ZStack(alignment: .center) {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.primary, lineWidth: 1.5)
                                    .frame(width: 19, height: 13.5)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                            }
                            .frame(width: 20, height: 16)
                        }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
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
                .overlay(statementImportOverlay)
                .alert("Statement Import Error", isPresented: $showStatementImportErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(statementImportErrorMessage ?? "Something went wrong.")
                }
                .alert("Import successful", isPresented: $showStatementImportSuccessAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    importSuccessMessage
                }
                .sheet(isPresented: $showingCategoryTransactions) {
                    categoryTransactionsSheet
                }
                .sheet(isPresented: $showingTransactionEditor) {
                    transactionEditorSheet
                }
                .onAppear(perform: handleAppear)
                .onChange(of: reportsViewModel.selectedMonth) { _, _ in
                    reportsViewModel.loadMonthlyReport()
                }
                .onChange(of: reportsViewModel.lastUsedWalletPeriod) { _, p in
                    handlePeriodChange(p)
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
        }
    }
    
    // MARK: - Computed Properties for View Modifiers
    
    @ViewBuilder
    private var statementImportOverlay: some View {
        if isStatementImportParsing {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            ProgressView("Reading CSV…")
                .tint(.white)
                .scaleEffect(1.2)
        }
    }
    
    private var importSuccessMessage: Text {
        Text("Imported \(statementImportSuccessCount) transaction\(statementImportSuccessCount == 1 ? "" : "s").")
    }
    
    @ViewBuilder
    private var categoryTransactionsSheet: some View {
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
    
    @ViewBuilder
    private var transactionEditorSheet: some View {
        if let entry = selectedTransaction {
            TransactionEditorSheetWrapper(entry: entry)
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
                .environmentObject(categoryManager)
        }
    }
    
    private func handleAppear() {
        reportsViewModel.loadMonthlyReport()
        reportsViewModel.loadYearWrapReport()
        reportsViewModel.loadWeekReport()
        reportsViewModel.loadUsdBtcReport()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
    }
    
    private func handlePeriodChange(_ p: ReportsViewModel.WalletPeriod) {
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
        
        for tx in transactions {
            let usdAmount = tx.isCredit ? tx.amount : -tx.amount
            
            // Import all transactions - treat credit card payments and transactions as the same dataset
            // Users can toggle between viewing payments vs transactions in the reports
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
        statementImportSuccessCount = importedCount
        statementImportMatchedCount = 0
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
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    expandedCategories: $expandedCategories,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    onTransactionTap: { entry in
                        selectedTransaction = entry
                        showingTransactionEditor = true
                    },
                    period: .week
                )
            }
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
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    expandedCategories: $expandedCategories,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    onTransactionTap: { entry in
                        selectedTransaction = entry
                        showingTransactionEditor = true
                    },
                    period: .month
                )
            }
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
                appeared: appeared,
                onIncomeTap: {
                    selectedCategory = "Income"
                    showingCategoryTransactions = true
                }
            )
            if !r.byCategory.isEmpty {
                WalletCategorySection(
                    items: r.byCategory,
                    appeared: appeared,
                    expandedCategories: $expandedCategories,
                    onCategoryTap: { category in
                        selectedCategory = category
                        showingCategoryTransactions = true
                    },
                    onTransactionTap: { entry in
                        selectedTransaction = entry
                        showingTransactionEditor = true
                    },
                    period: .year
                )
            }
        } else {
            emptySection
        }
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

    // MARK: - Period Picker with Double-Tap
    
    private var periodPickerWithDoubleTap: some View {
        Picker("", selection: walletPeriodBinding) {
            ForEach(ReportsViewModel.WalletPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    // Double-tap to jump to current period
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        reportsViewModel.jumpToCurrentPeriod()
                    }
                }
        )
    }
    
    // MARK: - Period Swipe Container (Apple Wallet Style)
    
    @State private var currentSwipeIndex: Int = 1
    @State private var isResettingSwipeIndex: Bool = false
    
    private var periodSwipeContainer: some View {
        TabView(selection: $currentSwipeIndex) {
            if canNavigateToPreviousPeriod {
                periodContentList
                    .tag(0)
            }
            periodContentList
                .tag(1)
            if canNavigateToNextPeriod {
                periodContentList
                    .tag(2)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .padding(.horizontal, -24) // Peek of previous/next period cards (Apple Wallet style)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            currentSwipeIndex = 1 // Start at center
        }
        .onChange(of: walletPeriod) { _, _ in
            currentSwipeIndex = 1 // Reset to center when period type changes
        }
        .onChange(of: currentSwipeIndex) { oldValue, newValue in
            // Only handle swipe if it's a real change and not a reset
            if !isResettingSwipeIndex && newValue != oldValue && newValue != 1 {
                handleSwipeToIndex(newValue)
            }
        }
    }
    
    private var periodContentList: some View {
        List {
            // Period title (Apple Wallet: large title right under toolbar)
            Section {
                Text(reportsPeriodTitle)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            Group {
                walletSections
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(4))
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }
    
    private var canNavigateToPreviousPeriod: Bool {
        let prevDate = getPreviousPeriodDate()
        return reportsViewModel.hasDataForPeriod(walletPeriod, date: prevDate)
    }
    
    private var canNavigateToNextPeriod: Bool {
        let nextDate = getNextPeriodDate()
        return reportsViewModel.hasDataForPeriod(walletPeriod, date: nextDate)
    }
    
    private func getPreviousPeriodDate() -> Date {
        let cal = Calendar.current
        switch walletPeriod {
        case .week:
            let start = reportsViewModel.startOfWeek(for: reportsViewModel.selectedWeekStart)
            return cal.date(byAdding: .day, value: -7, to: start) ?? start
        case .month:
            return cal.date(byAdding: .month, value: -1, to: reportsViewModel.selectedMonth) ?? reportsViewModel.selectedMonth
        case .year:
            return cal.date(from: DateComponents(year: reportsViewModel.selectedYear - 1, month: 1, day: 1)) ?? Date()
        }
    }
    
    private func getNextPeriodDate() -> Date {
        let cal = Calendar.current
        switch walletPeriod {
        case .week:
            let start = reportsViewModel.startOfWeek(for: reportsViewModel.selectedWeekStart)
            return cal.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            return cal.date(byAdding: .month, value: 1, to: reportsViewModel.selectedMonth) ?? reportsViewModel.selectedMonth
        case .year:
            return cal.date(from: DateComponents(year: reportsViewModel.selectedYear + 1, month: 1, day: 1)) ?? Date()
        }
    }
    
    private func handleSwipeToIndex(_ index: Int) {
        let cal = Calendar.current
        
        // Update period based on swipe direction
        switch index {
        case 0: // Swiped to previous
            switch walletPeriod {
            case .week:
                let start = reportsViewModel.startOfWeek(for: reportsViewModel.selectedWeekStart)
                if let prev = cal.date(byAdding: .day, value: -7, to: start) {
                    reportsViewModel.selectedWeekStart = prev
                }
            case .month:
                if let prev = cal.date(byAdding: .month, value: -1, to: reportsViewModel.selectedMonth) {
                    reportsViewModel.selectedMonth = prev
                }
            case .year:
                reportsViewModel.selectedYear -= 1
            }
        case 2: // Swiped to next
            switch walletPeriod {
            case .week:
                let start = reportsViewModel.startOfWeek(for: reportsViewModel.selectedWeekStart)
                if let next = cal.date(byAdding: .day, value: 7, to: start) {
                    reportsViewModel.selectedWeekStart = next
                }
            case .month:
                if let next = cal.date(byAdding: .month, value: 1, to: reportsViewModel.selectedMonth) {
                    reportsViewModel.selectedMonth = next
                }
            case .year:
                reportsViewModel.selectedYear += 1
            }
        default:
            break
        }
        
        // Reset to center after a brief delay to allow continuous swiping
        // The delay allows the TabView animation to complete and the view model to update
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            isResettingSwipeIndex = true
            currentSwipeIndex = 1
            // Small delay before allowing swipe handling again
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            isResettingSwipeIndex = false
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

/// iOS design shape for Activity bar charts: corner radius and style used by main chart and chip card so they match.
private let activityBarCornerRadius: CGFloat = 6

/// Rich, hue-ordered palette for Activity bar gradients (category + value + period). More colors, smooth spectral flow.
private let activityCategoryPalette: [Color] = [
    Color(red: 0.95, green: 0.40, blue: 0.25),   // warm orange
    Color(red: 0.90, green: 0.35, blue: 0.45),   // coral / pink
    Color(red: 0.75, green: 0.30, blue: 0.55),   // magenta
    Color(red: 0.55, green: 0.35, blue: 0.75),   // purple
    Color(red: 0.40, green: 0.45, blue: 0.90),   // blue
    Color(red: 0.30, green: 0.65, blue: 0.90),   // sky blue
    Color(red: 0.25, green: 0.75, blue: 0.80),   // cyan
    Color(red: 0.30, green: 0.80, blue: 0.65),  // teal
    Color(red: 0.35, green: 0.78, blue: 0.45),  // green
    Color(red: 0.55, green: 0.82, blue: 0.35),  // lime
    Color(red: 0.75, green: 0.78, blue: 0.30),  // yellow-green
    Color(red: 0.90, green: 0.72, blue: 0.25),  // gold
    Color(red: 0.92, green: 0.55, blue: 0.28),  // orange
    Color(red: 0.85, green: 0.35, blue: 0.38),  // red-pink
    Color(red: 0.60, green: 0.45, blue: 0.75),   // violet
    Color(red: 0.50, green: 0.55, blue: 0.85),  // periwinkle
    Color(red: 0.45, green: 0.70, blue: 0.75),  // steel
    Color(red: 0.55, green: 0.65, blue: 0.55), // sage
]

// MARK: - Activity chart color helpers (blend, lighten, period tint)

private func activityBlend(_ a: Color, _ b: Color, t: CGFloat = 0.5) -> Color {
    let uia = UIColor(a)
    let uib = UIColor(b)
    var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
    var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
    uia.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    uib.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return Color(
        red: r1 + (r2 - r1) * t,
        green: g1 + (g2 - g1) * t,
        blue: b1 + (b2 - b1) * t,
        opacity: a1 + (a2 - a1) * t
    )
}

private func activityLighten(_ color: Color, amount: CGFloat = 0.15) -> Color {
    activityBlend(color, .white, t: amount)
}

/// Subtle period tint: earlier bars slightly cooler, later bars slightly warmer (for time flow).
private func activityPeriodTint(_ color: Color, periodIndex: Int, totalPeriods: Int) -> Color {
    guard totalPeriods > 1 else { return color }
    let t = Double(periodIndex) / max(Double(totalPeriods - 1), 1)
    let strength = 0.07
    let cool = Color(red: 0.4, green: 0.5, blue: 0.9)
    let warm = Color(red: 0.95, green: 0.6, blue: 0.35)
    let tint = activityBlend(cool, warm, t: CGFloat(t))
    return activityBlend(color, tint, t: CGFloat(strength))
}

/// One segment in a stacked bar: category color + value (height). Used for Apple Wallet–style stacked bars.
private struct ActivityBarSegment: Identifiable {
    let id: String
    let period: String
    let periodIndex: Int
    let category: String
    let amount: Double
}

private struct WalletTotalSpendingAppleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
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
    
    /// Apple Wallet wording: "So far, you've spent $XXX.XX more/less than last month at this time."
    private var comparisonText: String? {
        guard let previous = previousPeriodExpenses, previous > 0 else { return nil }
        let difference = expenses - previous
        let absDifference = abs(difference)
        let periodPhrase: String = {
            switch periodType {
            case .week: return "last week at this time"
            case .month: return "last month at this time"
            case .year: return "last year at this time"
            }
        }()
        
        if abs(difference) < 0.01 {
            return "So far, same as \(periodPhrase)"
        }
        
        let diffString = formatter.string(from: absDifference as NSDecimalNumber) ?? "$0.00"
        if difference > 0 {
            return "So far, you've spent \(diffString) more than \(periodPhrase)."
        } else {
            return "So far, you've spent \(diffString) less than \(periodPhrase)."
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatter.string(from: expenses as NSDecimalNumber) ?? "$0.00")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                    if let icon = arrowIcon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(comparisonColor)
                    }
                }
                if let comparison = comparisonText {
                    Text(comparison)
                        .font(.subheadline)
                        .foregroundStyle(comparisonColor)
                }
                walletBarChart
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
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

struct WalletStackedCategoryBarChart: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let period: ReportsViewModel.WalletPeriod
    let appeared: Bool
    let showEveryNthLabel: Int?
    
    private var categoryBreakdown: [(period: String, categories: [(name: String, amount: Decimal)])] {
        reportsViewModel.categoryBreakdownByPeriod(period: period)
    }
    
    private var allCategories: [String] {
        var set: Set<String> = []
        for item in categoryBreakdown {
            for cat in item.categories { set.insert(cat.name) }
        }
        return Array(set).sorted { cat1, cat2 in
            if cat1 == "Digital Wallet Fees" { return false }
            if cat2 == "Digital Wallet Fees" { return true }
            return cat1 < cat2
        }
    }
    
    private func colorForCategory(_ name: String) -> Color {
        if name == "Digital Wallet Fees" { return Color(red: 0.95, green: 0.55, blue: 0.28) }
        guard let i = allCategories.firstIndex(of: name) else { return .gray }
        return activityCategoryPalette[i % activityCategoryPalette.count]
    }
    
    /// Flatten to one segment per (period, category) with amount > 0, sorted so largest category is bottom of stack.
    private var stackedSegments: [ActivityBarSegment] {
        var out: [ActivityBarSegment] = []
        for (periodIndex, periodData) in categoryBreakdown.enumerated() {
            let sorted = periodData.categories.sorted { $0.amount > $1.amount }
            for cat in sorted {
                let amount = (cat.amount as NSDecimalNumber).doubleValue
                if amount > 0 {
                    out.append(ActivityBarSegment(
                        id: "\(periodData.period)-\(cat.name)",
                        period: periodData.period,
                        periodIndex: periodIndex,
                        category: cat.name,
                        amount: amount
                    ))
                }
            }
        }
        return out
    }
    
    /// Apple Wallet style: category color + subtle vertical gradient (darker bottom, lighter top) + optional period tint.
    private func segmentStyle(for segment: ActivityBarSegment) -> LinearGradient {
        let base = colorForCategory(segment.category)
        let tinted = activityPeriodTint(base, periodIndex: segment.periodIndex, totalPeriods: categoryBreakdown.count)
        let top = activityLighten(tinted, amount: 0.12)
        return LinearGradient(colors: [tinted, top], startPoint: .bottom, endPoint: .top)
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
                ForEach(stackedSegments) { segment in
                    BarMark(
                        x: .value("Period", segment.period),
                        y: .value("Amount", segment.amount)
                    )
                    .foregroundStyle(segmentStyle(for: segment))
                    .cornerRadius(activityBarCornerRadius, style: .continuous)
                }
                ForEach(Array(categoryBreakdown.enumerated()), id: \.element.period) { _, periodData in
                    let totalAmount = actualValue(for: periodData)
                    if totalAmount == 0 {
                        BarMark(
                            x: .value("Period", periodData.period),
                            y: .value("Amount", 0.0)
                        )
                        .foregroundStyle(Color.clear)
                        .opacity(0)
                        .cornerRadius(activityBarCornerRadius, style: .continuous)
                    }
                }
            }
            .id(categoryBreakdown.map(\.period).joined(separator: "-"))
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
                let maxVal = max(maxValue, 100) // 100 floor for readable axis when no data
                let step = maxVal / 4.0
                let mainValues: [Double] = [0, step, step * 2, step * 3, maxVal]
                let midpointValues: [Double] = [step * 0.5, step * 1.5, step * 2.5, step * 3.5]
                let allValues = (mainValues + midpointValues).sorted()
                
                AxisMarks(position: .trailing, values: allValues) { value in
                    if let doubleValue = value.as(Double.self) {
                        let isMainValue = mainValues.contains { abs($0 - doubleValue) < 0.01 }
                        if isMainValue {
                            AxisValueLabel {
                                Text(formatAmount(doubleValue))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary.opacity(0.3))
                        } else {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(.secondary.opacity(0.2))
                        }
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 4))
        }
        .opacity(appeared ? 1 : 0)
    }
}

// MARK: - Compact Stacked Category Bar Chart (for Balance page chip card)

struct CompactWalletStackedCategoryBarChart: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let period: ReportsViewModel.WalletPeriod
    let appeared: Bool
    
    private var categoryBreakdown: [(period: String, categories: [(name: String, amount: Decimal)])] {
        reportsViewModel.categoryBreakdownByPeriod(period: period)
    }
    
    private var allCategories: [String] {
        var set: Set<String> = []
        for item in categoryBreakdown {
            for cat in item.categories { set.insert(cat.name) }
        }
        return Array(set).sorted { cat1, cat2 in
            if cat1 == "Digital Wallet Fees" { return false }
            if cat2 == "Digital Wallet Fees" { return true }
            return cat1 < cat2
        }
    }
    
    private func colorForCategory(_ name: String) -> Color {
        if name == "Digital Wallet Fees" { return Color(red: 0.95, green: 0.55, blue: 0.28) }
        guard let i = allCategories.firstIndex(of: name) else { return .gray }
        return activityCategoryPalette[i % activityCategoryPalette.count]
    }
    
    private var stackedSegments: [ActivityBarSegment] {
        var out: [ActivityBarSegment] = []
        for (periodIndex, periodData) in categoryBreakdown.enumerated() {
            let sorted = periodData.categories.sorted { $0.amount > $1.amount }
            for cat in sorted {
                let amount = (cat.amount as NSDecimalNumber).doubleValue
                if amount > 0 {
                    out.append(ActivityBarSegment(
                        id: "\(periodData.period)-\(cat.name)",
                        period: periodData.period,
                        periodIndex: periodIndex,
                        category: cat.name,
                        amount: amount
                    ))
                }
            }
        }
        return out
    }
    
    private func segmentStyle(for segment: ActivityBarSegment) -> LinearGradient {
        let base = colorForCategory(segment.category)
        let tinted = activityPeriodTint(base, periodIndex: segment.periodIndex, totalPeriods: categoryBreakdown.count)
        let top = activityLighten(tinted, amount: 0.12)
        return LinearGradient(colors: [tinted, top], startPoint: .bottom, endPoint: .top)
    }
    
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
    
    var body: some View {
        Chart {
            ForEach(stackedSegments) { segment in
                BarMark(
                    x: .value("Period", segment.period),
                    y: .value("Amount", segment.amount)
                )
                .foregroundStyle(segmentStyle(for: segment))
                .cornerRadius(activityBarCornerRadius, style: .continuous)
            }
            ForEach(Array(categoryBreakdown.enumerated()), id: \.element.period) { _, periodData in
                let totalAmount = actualValue(for: periodData)
                if totalAmount == 0 {
                    BarMark(
                        x: .value("Period", periodData.period),
                        y: .value("Amount", maxValue * 0.1)
                    )
                    .foregroundStyle(Color.gray.opacity(0.2))
                    .cornerRadius(activityBarCornerRadius, style: .continuous)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 40)
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
                    .cornerRadius(activityBarCornerRadius, style: .continuous)
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
                // When there's no data, use sensible default values
                let maxVal = maxValue > 0 ? max(maxValue, 100) : 100
                let quarter = maxVal / 4.0
                // Ensure quarter is at least 25 for readability when there's no data
                let adjustedQuarter = max(quarter, 25.0)
                let adjustedMax = maxValue > 0 ? maxVal : 100
                // Create 4 main values (quarters) and 4 midpoints
                let mainValues: [Double] = [0, adjustedQuarter, adjustedQuarter * 2, adjustedQuarter * 3, adjustedMax]
                let midpointValues: [Double] = [adjustedQuarter * 0.5, adjustedQuarter * 1.5, adjustedQuarter * 2.5, adjustedQuarter * 3.5]
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
    let appeared: Bool
    let onIncomeTap: () -> Void
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
    @Binding var expandedCategories: Set<String>
    let onCategoryTap: (String) -> Void
    let onTransactionTap: (LedgerEntry) -> Void
    let period: ReportsViewModel.WalletPeriod
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    // Sort items by amount descending (largest first)
    private var sortedItems: [(name: String, amount: Decimal)] {
        items.sorted { $0.amount > $1.amount }
    }
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
        sortedItems.reduce(0) { $0 + $1.amount }
    }
    
    // Get color for category based on its index (ensures each category gets a unique color)
    // Colors are synced between list and pie chart. Digital Wallet Fees always orange.
    private func colorForIndex(_ index: Int) -> Color {
        return categoryColorPalette[index % categoryColorPalette.count]
    }
    
    private func colorForCategoryRow(_ name: String, index: Int) -> Color {
        name == "Digital Wallet Fees" ? .orange : colorForIndex(index)
    }
    
    // Get all colors for the items (used for pie chart). Digital Wallet Fees = orange.
    private var itemColors: [Color] {
        return sortedItems.prefix(8).enumerated().map { index, item in
            item.name == "Digital Wallet Fees" ? .orange : colorForIndex(index)
        }
    }
    
    private func iconForCategory(_ categoryName: String) -> String {
        if categoryName == "Digital Wallet Fees" {
            return "bitcoinsign.circle.fill"
        }
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
                            items: sortedItems,
                            colors: itemColors,
                            appeared: appeared
                        )
                        .scaleEffect(pieChartScale)
                        .rotationEffect(.degrees(pieChartRotation))
                        .opacity(pieChartOpacity)
                        
                        // Legend with separate animations
                        CategoryPieChartLegend(
                            items: sortedItems,
                            colors: itemColors,
                            legendOffset: legendOffset,
                            legendOpacity: legendOpacity
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedItems.prefix(8).enumerated()), id: \.offset) { i, item in
                            let isExpanded = expandedCategories.contains(item.name)
                            let transactions = reportsViewModel.transactionsForCategory(item.name, period: period)
                            
                            VStack(spacing: 0) {
                                // Category row - tappable to expand/collapse
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if expandedCategories.contains(item.name) {
                                            expandedCategories.remove(item.name)
                                        } else {
                                            expandedCategories.insert(item.name)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: iconForCategory(item.name))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(colorForCategoryRow(item.name, index: i))
                                            .frame(width: 32, height: 32)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(colorForCategoryRow(item.name, index: i).opacity(0.15)))
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formatter.string(from: item.amount as NSDecimalNumber) ?? "$0")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                        }
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .opacity(appeared ? 1 : 0)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                // Expanded transactions
                                if isExpanded {
                                    VStack(spacing: 0) {
                                        if !transactions.isEmpty {
                                            ForEach(transactions, id: \.objectID) { entry in
                                                Button {
                                                    onTransactionTap(entry)
                                                } label: {
                                                    CategoryTransactionRow(
                                                        entry: entry,
                                                        category: item.name,
                                                        formatter: formatter,
                                                        dateFormatter: {
                                                            let f = DateFormatter()
                                                            f.dateStyle = .short
                                                            f.timeStyle = .none
                                                            return f
                                                        }(),
                                                        onEdit: {
                                                            onTransactionTap(entry)
                                                        },
                                                        onDelete: {}
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.leading, 52)
                                                .padding(.vertical, 8)
                                                
                                                if entry != transactions.last {
                                                    Divider()
                                                        .padding(.leading, 52)
                                                }
                                            }
                                        } else {
                                            Text("No transactions")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 52)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// Wrapper for TransactionEditorSheet (which is private in AccountDetailView)
private struct TransactionEditorSheetWrapper: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let entry: LedgerEntry
    
    var body: some View {
        // Use the same editor structure as AccountDetailView
        LedgerEntryEditorView(entry: entry, onSave: { date, title, btcAmount, usdAmount, btcPrice, isCleared, notes, category in
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
        })
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
                        TextField("Description", text: $title)
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
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                } header: {
                    Text("Transaction Details")
                }
                
                if let account = entry.account, account.currencyCode == "BTC" {
                    Section {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
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
                    } header: {
                        Text("Amount")
                    }
                    Section {
                        HStack {
                            TextField("sats/BTC Amount", text: $btcSatsAmountString)
                                .keyboardType(.decimalPad)
                                .onChange(of: btcSatsAmountString) { _, _ in
                                    btcPriceString = reportsEditorComputedBTCPrice()
                                }
                            if !btcSatsAmountString.isEmpty {
                                Button {
                                    btcSatsAmountString = ""
                                    btcPriceString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        HStack {
                            Text("BTC Price")
                            Spacer()
                            if !btcPriceString.isEmpty {
                                Text("$\(btcPriceString)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Bitcoin Details")
                    }
                } else {
                    Section {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
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
                    } header: {
                        Text("Amount")
                    }
                }
                
                Section {
                    Toggle("Cleared", isOn: $isCleared)
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
                } header: {
                    Text("Additional Information")
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
    
    private func reportsEditorComputedBTCPrice() -> String {
        guard entry.account?.currencyCode == "BTC" else { return "" }
        let cleaned = btcSatsAmountString.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return "" }
        guard let usd = Decimal(string: usdAmountString.replacingOccurrences(of: ",", with: "")), usd > 0 else { return "" }
        let btcAmount: Decimal
        if cleaned.contains(".") {
            guard let btc = Decimal(string: cleaned), btc > 0 else { return "" }
            btcAmount = btc
        } else {
            guard let sats = Int(cleaned), sats > 0 else { return "" }
            btcAmount = Decimal(sats) / 100_000_000
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: (usd / btcAmount) as NSDecimalNumber) ?? ""
    }
    
    private func saveEntry() {
        let cleanedBtc = btcSatsAmountString.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let btcAmount: Decimal? = {
            guard !cleanedBtc.isEmpty else { return nil }
            if cleanedBtc.contains(".") {
                guard let btc = Decimal(string: cleanedBtc), btc != 0 else { return nil }
                return btc
            }
            guard let sats = Int(cleanedBtc), sats != 0 else { return nil }
            return Decimal(sats) / 100_000_000
        }()
        
        let usdAmount: Decimal? = {
            let cleaned = usdAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            if let amount = Decimal(string: cleaned), amount != 0 {
                return amount
            }
            return nil
        }()
        
        var btcPrice: Decimal? = nil
        if !btcPriceString.isEmpty {
            let cleaned = btcPriceString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            if let price = Decimal(string: cleaned), price > 0 { btcPrice = price }
        }
        if btcPrice == nil, let usd = usdAmount, let btc = btcAmount, btc != 0 {
            btcPrice = abs(usd) / abs(btc)
        }
        
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
        guard let account = entry.account else { return .zero }
        
        // For Digital Wallet Fees, calculate from account fee percentage
        if category == "Digital Wallet Fees" {
            guard account.feePercentageDecimal > 0 else { return .zero }
            
            // Get the transaction amount in USD
            let transactionAmount: Decimal
            if account.currencyCode == "BTC" {
                let usd = entry.usdAmountDecimal
                if usd != 0 {
                    transactionAmount = abs(usd)
                } else {
                    let btc = entry.amountInCurrency(for: account)
                    let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : bitcoinPriceService.btcToUsdRate
                    transactionAmount = abs(btc * price)
                }
            } else {
                let amt = entry.usdAmountDecimal != 0 ? entry.usdAmountDecimal : entry.amountDecimal
                transactionAmount = abs(amt)
            }
            
            // Calculate fee: amount * (feePercentage / 100)
            return transactionAmount * (account.feePercentageDecimal / 100)
        }
        
        // For regular categories, calculate USD amount similar to ReportsViewModel
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
    
    var body: some View {
        Picker("Category", selection: $selection) {
            Text("None").tag("")
            ForEach(categoryManager.displayCategories(usage: usage, selected: selection), id: \.self) { category in
                Text(category).tag(category)
            }
        }
        .pickerStyle(.menu)
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
    let vm = ReportsViewModel(context: ctx, bitcoinPriceService: .shared, creditCardManager: CreditCardManager())
    let accountVM = AccountViewModel(context: ctx)
    return ReportsView()
        .environmentObject(vm)
        .environmentObject(BitcoinPriceService.shared)
        .environmentObject(accountVM)
}
