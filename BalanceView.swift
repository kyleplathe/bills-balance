import SwiftUI
import Charts

// Cash register style balance text with digit rotation
private struct CashRegisterBalanceText: View {
    let value: String
    let previousValue: String?
    let fontSize: CGFloat
    @State private var displayedValue: String
    @State private var digitRotations: [Double]
    
    init(value: String, previousValue: String?, fontSize: CGFloat) {
        self.value = value
        self.previousValue = previousValue
        self.fontSize = fontSize
        _displayedValue = State(initialValue: previousValue ?? value)
        _digitRotations = State(initialValue: Array(repeating: 0, count: value.count))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(displayedValue.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .rotation3DEffect(
                        .degrees(digitRotations[safe: index] ?? 0),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.3
                    )
            }
        }
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue {
                // Animate each digit that changed
                for (index, newChar) in newValue.enumerated() {
                    let oldChar = oldValue.count > index ? oldValue[oldValue.index(oldValue.startIndex, offsetBy: index)] : nil
                    if oldChar != newChar {
                        // Animate this digit
                        withAnimation(.easeOut(duration: 0.25).delay(Double(index) * 0.03)) {
                            digitRotations[index] = 180
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.125 + Double(index) * 0.03) {
                            if displayedValue.count > index {
                                let startIndex = displayedValue.startIndex
                                let charIndex = displayedValue.index(startIndex, offsetBy: index)
                                displayedValue.replaceSubrange(charIndex...charIndex, with: String(newChar))
                            }
                            withAnimation(.easeIn(duration: 0.25)) {
                                digitRotations[index] = 360
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                digitRotations[index] = 0
                            }
                        }
                    }
                }
                // Update displayed value for length changes
                if newValue.count != displayedValue.count {
                    displayedValue = newValue
                    digitRotations = Array(repeating: 0, count: newValue.count)
                }
            }
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Main Balance View
struct BalanceView: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @State private var showingManageAccounts = false
    @State private var showingReports = false
    @State private var showingAddAccount = false
    @State private var showingAccountDetail: Bool = false
    @State private var selectedAccount: Account?
    @State private var isSearchPresented = false
    @State private var showInactiveAccounts = false
    @State private var showingImportPicker = false
    @State private var showingExportSheet = false
    @State private var showingProjectionSettings = false
    @State private var currentAccountPage = 0
    @State private var activityChartAppeared = false
    @State private var supabaseManager: SupabaseManager?
    
    var body: some View {
        NavigationStack {
            navigationContent
        }
    }
    
    private var navigationContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if visibleAccounts.isEmpty && !showInactiveAccounts {
                    emptyStateView
                } else {
                    summaryChipCards
                    if !visibleAccounts.isEmpty {
                        accountsSection
                    }
                    recentTransactionsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle("Balance")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                addButton
                searchButton
                menuButton
            }
        }
        .sheet(isPresented: $showingManageAccounts) {
            ManageAccountsView()
                .environmentObject(accountViewModel)
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountEditorSheet(account: nil) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage, startingBalanceUSD, startingBalanceBTCPrice in
                _ = accountViewModel.addAccount(name: name,
                                            type: type,
                                            startingBalance: startingBalance,
                                            isHidden: isHidden,
                                            currency: currency,
                                            btcDisplayFormat: btcDisplayFormat,
                                            feePercentage: feePercentage,
                                            startingBalanceUSD: startingBalanceUSD,
                                            startingBalanceBTCPrice: startingBalanceBTCPrice)
                // Ensure view refreshes - fetchAccounts is already called in addAccount
                // but we'll refresh again to be sure
                accountViewModel.fetchAccounts()
            }
            .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingProjectionSettings) {
            NavigationStack {
                if let supabaseManager {
                    ProjectionSettingsView(accountID: nil, supabaseManager: supabaseManager)
                } else {
                    ContentUnavailableView(
                        "Supabase Not Configured",
                        systemImage: "icloud.slash",
                        description: Text("Set SUPABASE_URL and SUPABASE_ANON_KEY to edit projection settings.")
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showingReports) {
            ReportsView()
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
                .environmentObject(reportsViewModel)
                .environmentObject(categoryManager)
        }
        .navigationDestination(isPresented: $showingAccountDetail) {
            if let account = selectedAccount {
                AccountDetailView(account: account)
                    .environmentObject(accountViewModel)
                    .environmentObject(billViewModel)
                    .environmentObject(paycheckViewModel)
                    .environmentObject(bitcoinPriceService)
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            // TODO: Handle account import
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Handle import
                    print("Import from: \(url)")
                }
            case .failure(let error):
                print("Import error: \(error)")
            }
        }
        .onAppear {
            accountViewModel.fetchAccounts()
            if supabaseManager == nil {
                supabaseManager = try? SupabaseManager()
            }
        }
        .onChange(of: showingAddAccount) { _, isPresented in
            // Refresh accounts when the add account sheet is dismissed
            if !isPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    accountViewModel.fetchAccounts()
                }
            }
        }
        .onChange(of: showingManageAccounts) { _, isPresented in
            // Refresh accounts when the manage accounts sheet is dismissed
            if !isPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    accountViewModel.fetchAccounts()
                }
            }
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var addButton: some View {
        Button {
            showingAddAccount = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
    }
    
    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title2)
        }
    }
    
    private var menuButton: some View {
        Menu {
            Button {
                showingManageAccounts = true
            } label: {
                Label("Manage Accounts", systemImage: "building.columns")
            }
            
            Menu {
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Button {
                    // TODO: Implement export accounts
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Import/Export", systemImage: "arrow.up.arrow.down")
            }
            
            Button {
                // TODO: Implement transfer between accounts
            } label: {
                Label("Transfer", systemImage: "arrow.left.arrow.right")
            }
            .disabled(true)
            
            Button {
                showInactiveAccounts.toggle()
            } label: {
                Label("Show Inactive Accounts", systemImage: showInactiveAccounts ? "eye.fill" : "eye")
            }
            
            Button {
                showingReports = true
            } label: {
                Label("Reports", systemImage: "chart.bar")
            }

            Button {
                showingProjectionSettings = true
            } label: {
                Label("Projection Settings", systemImage: "slider.horizontal.3")
            }
            
            // Debug: Add sample data for testing bar chart
            if let firstAccount = visibleAccounts.first {
                Divider()
                Button {
                    accountViewModel.addSampleDataForTesting(to: firstAccount)
                } label: {
                    Label("Add Sample Data (Test)", systemImage: "chart.bar.doc.horizontal.fill")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("Add accounts to track balances and transactions.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 40)
        }
    }
    
    // MARK: - Summary Chip Cards
    
    private var summaryChipCards: some View {
        balanceSnapshotCard
    }
    
    private var balanceSnapshotCard: some View {
        Button {
            showingReports = true
        } label: {
            ChipCard {
                HStack(spacing: 20) {
                    // Left side: Total Balance
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(totalBalance, format: .currency(code: "USD"))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                    
                    // Right side: Activity
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(activityPeriodTitle) Activity")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("-\(activitySpending, format: .currency(code: "USD")) Spending")
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .foregroundColor(.primary)
                        activityChart
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 120)
        }
        .buttonStyle(.plain)
        .onAppear {
            // Trigger chart animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                activityChartAppeared = true
            }
        }
    }
    
    private var activityChart: some View {
        CompactWalletStackedCategoryBarChart(
            period: activityPeriod,
            appeared: activityChartAppeared
        )
        .frame(height: 40)
    }
    
    // MARK: - Accounts Section
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts")
                .font(.headline)
                .padding(.horizontal, 4)
            
            if visibleAccounts.isEmpty {
                Text("No accounts to display")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                // Calculate number of pages (4 accounts per page)
                let accountsPerPage = 4
                let totalPages = (visibleAccounts.count + accountsPerPage - 1) / accountsPerPage
                
                VStack(spacing: 8) {
                    TabView(selection: $currentAccountPage) {
                        ForEach(0..<totalPages, id: \.self) { pageIndex in
                            let startIndex = pageIndex * accountsPerPage
                            let endIndex = min(startIndex + accountsPerPage, visibleAccounts.count)
                            let pageAccounts = Array(visibleAccounts[startIndex..<endIndex])
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], alignment: .leading, spacing: 12) {
                                // Fill with actual accounts first
                                ForEach(pageAccounts, id: \.objectID) { account in
                                    AccountChipCard(account: account) {
                                        selectedAccount = account
                                        showingAccountDetail = true
                                    }
                                }
                                // Fill remaining slots with invisible spacers to maintain grid order
                                ForEach(pageAccounts.count..<accountsPerPage, id: \.self) { _ in
                                    Color.clear
                                        .frame(height: 100)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .tag(pageIndex)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 220) // Height for 2 rows of cards (100px each + 12px spacing)
                    
                    // Custom page indicator below the chips
                    if totalPages > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<totalPages, id: \.self) { index in
                                Circle()
                                    .fill(index == currentAccountPage ? Color.primary : Color.secondary.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
    
    private var visibleAccounts: [Account] {
        let allAccounts = accountViewModel.accounts
        
        // Always filter and sort, regardless of showInactiveAccounts
        // showInactiveAccounts just determines if we show hidden accounts too
        let filtered = showInactiveAccounts ? allAccounts : allAccounts.filter { !$0.isHiddenFlag }
        
        return filtered.sorted { account1, account2 in
            if account1.order != account2.order {
                return account1.order < account2.order
            }
            // If order is the same, sort by creation date
            if let date1 = account1.createdAt, let date2 = account2.createdAt {
                return date1 < date2
            }
            return false
        }
    }
    
    // MARK: - Recent Transactions Section
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(recentTransactions.prefix(5), id: \.objectID) { entry in
                    TransactionChipCard(entry: entry)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalBalance: Decimal {
        accountViewModel.totalClearedBalance(bitcoinPriceService: bitcoinPriceService)
    }
    
    private var activityPeriod: ReportsViewModel.WalletPeriod {
        reportsViewModel.lastUsedWalletPeriod
    }
    
    private var activityPeriodTitle: String {
        activityPeriod.rawValue
    }
    
    private var activitySpending: Decimal {
        let calendar = Calendar.current
        let now = Date()
        let entries = accountViewModel.recentTransactions(limit: 1000, daysBack: nil)
        
        let (start, end): (Date?, Date?) = {
            switch activityPeriod {
            case .week:
                let weekStart = startOfWeek(for: now, calendar: calendar)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)
                return (weekStart, weekEnd)
            case .month:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                let monthEnd = monthStart.map { calendar.date(byAdding: .month, value: 1, to: $0) }
                return (monthStart, monthEnd ?? nil)
            case .year:
                let yearStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1))
                let yearEnd = yearStart.map { calendar.date(byAdding: .year, value: 1, to: $0) }
                return (yearStart, yearEnd ?? nil)
            }
        }()
        
        guard let start = start, let end = end else { return 0 }
        
        return entries
            .filter { entry in
                guard let date = entry.date else { return false }
                return date >= start && date < end
            }
            .reduce(Decimal.zero) { partial, entry in
                guard let account = entry.account, !account.isHiddenFlag else { return partial }
                let amount = entry.signedAmount
                // Only count expenses (negative amounts)
                return amount < 0 ? partial + abs(amount) : partial
            }
    }
    
    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return date }
        return interval.start
    }
    
    private var recentTransactions: [LedgerEntry] {
        accountViewModel.recentTransactions(limit: 5, daysBack: 30)
    }
}

// MARK: - Chip Card Component

private struct ChipCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content
    
    var body: some View {
        // Match bills page styling exactly
        let backgroundColor: Color = colorScheme == .dark 
            ? Color.black.opacity(0.82) 
            : Color(.secondarySystemBackground)
        let borderColor: Color = colorScheme == .dark 
            ? Color.white.opacity(0.08) 
            : Color.black.opacity(0.06)
        
        content
            .padding(.vertical, 20)
            .padding(.horizontal, 18)
            .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(borderColor)
                        )
            )
    }
}

// MARK: - Account Chip Card

private struct AccountChipCard: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let account: Account
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatAccountBalanceUSD(accountViewModel.totalBalance(for: account), account: account))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(account.name ?? "Account")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accountGradient)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .frame(height: 100)
    }
    
    private var accountGradient: LinearGradient {
        // Blue gradient with slight variation based on account
        let baseBlue = Color.blue
        let darkerBlue = Color(red: 0.0, green: 0.4, blue: 0.8)
        
        // Slight variation based on account name for visual distinction
        let hash = abs((account.name ?? "").hashValue)
        let variation = Double(hash % 20) / 100.0 // 0.0 to 0.2 variation
        
        return LinearGradient(
            gradient: Gradient(colors: [
                baseBlue.opacity(1.0 - variation),
                darkerBlue.opacity(0.9 + variation)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatAccountBalanceUSD(_ balance: Decimal, account: Account) -> String {
        // Always display in USD on the balance page
        let usdBalance: Decimal
        if account.currencyCode == "BTC" {
            // Convert BTC to USD using current price
            usdBalance = bitcoinPriceService.convertBTCToUSD(balance)
        } else {
            usdBalance = balance
        }
        
        // USD formatting with commas and decimals
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: usdBalance as NSDecimalNumber) ?? "$\(usdBalance)"
    }
}

// MARK: - Transaction Chip Card

private struct TransactionChipCard: View {
    let entry: LedgerEntry
    
    var body: some View {
        ChipCard {
            HStack(spacing: 12) {
                // Transaction icon
                Circle()
                    .fill(entry.isCredit ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: entry.isCredit ? "arrow.up" : "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(entry.isCredit ? .green : .red)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title ?? "Transaction")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        if let date = entry.date {
                            Text(formatDate(date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let accountName = entry.account?.name {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(accountName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Display USD amount for all transactions
                let usdAmount: Decimal = {
                    guard let account = entry.account else {
                        return entry.usdAmountDecimal != .zero ? entry.usdAmountDecimal : entry.amountDecimal
                    }
                    if account.currencyCode == "BTC" {
                        // For BTC accounts, use USD amount if available
                        if entry.usdAmountDecimal != .zero {
                            return entry.usdAmountDecimal
                        } else if entry.btcAmountDecimal != .zero && entry.btcPriceAtTransactionDecimal > 0 {
                            // Convert BTC to USD using transaction price
                            return entry.btcAmountDecimal * entry.btcPriceAtTransactionDecimal
                        }
                        return .zero
                    } else {
                        // For USD accounts, use USD amount or regular amount
                        return entry.usdAmountDecimal != .zero ? entry.usdAmountDecimal : entry.amountDecimal
                    }
                }()
                
                if usdAmount != .zero {
                    let signedAmount = entry.isCredit ? usdAmount : -usdAmount
                    let formattedAmount = abs(signedAmount).formatted(.currency(code: "USD"))
                    Text((entry.isCredit ? "+" : "-") + formattedAmount)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(entry.isCredit ? .green : .red)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}
