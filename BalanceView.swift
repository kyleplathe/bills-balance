import SwiftUI

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
    @State private var showingManageAccounts = false
    @State private var showingReports = false
    @State private var showingAddAccount = false
    @State private var showingAccountDetail: Bool = false
    @State private var selectedAccount: Account?
    @State private var isSearchPresented = false
    @State private var showInactiveAccounts = false
    @State private var showingImportPicker = false
    @State private var showingExportSheet = false
    
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
            AccountEditorSheet(account: nil) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage in
                _ = accountViewModel.addAccount(name: name,
                                            type: type,
                                            startingBalance: startingBalance,
                                            isHidden: isHidden,
                                            currency: currency,
                                            btcDisplayFormat: btcDisplayFormat,
                                            feePercentage: feePercentage)
                // Ensure view refreshes - fetchAccounts is already called in addAccount
                // but we'll refresh again to be sure
                accountViewModel.fetchAccounts()
            }
            .environmentObject(bitcoinPriceService)
        }
        .fullScreenCover(isPresented: $showingReports) {
            ReportsView()
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
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
        HStack(spacing: 12) {
            totalBalanceCard
            monthlyActivityCard
        }
    }
    
    private var totalBalanceCard: some View {
        ChipCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(totalBalance, format: .currency(code: "USD"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 100)
    }
    
    private var monthlyActivityCard: some View {
        Button {
            showingReports = true
        } label: {
            ChipCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(activityPeriodTitle) Activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("-\(activitySpending, format: .currency(code: "USD")) Spending")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    activityBreakdownChart
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 100)
        }
        .buttonStyle(.plain)
    }
    
    private var activityBreakdownChart: some View {
        HStack(spacing: 4) {
            ForEach(0..<activityBreakdown.count, id: \.self) { index in
                let value = activityBreakdown[safe: index] ?? Decimal(0)
                let hasData = value > Decimal(0.01) // Consider values less than 1 cent as no data
                let ratio = hasData ? NSDecimalNumber(decimal: value).doubleValue / NSDecimalNumber(decimal: maxActivityValue).doubleValue : 0
                let barColor = hasData ? (activityChartColors[safe: index] ?? .gray) : Color.gray.opacity(0.3)
                let barHeight = hasData ? max(4, CGFloat(ratio * 24)) : 4
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(height: barHeight)
            }
        }
        .frame(height: 24, alignment: .bottom)
    }
    
    private var activityChartColors: [Color] {
        switch activityPeriod {
        case .week:
            return [.orange, .pink, .purple, .blue, .green, .cyan, .indigo]
        case .month:
            return [.orange, .pink, .purple, .blue]
        case .year:
            return [.orange, .pink, .purple, .blue, .green, .cyan, .indigo, .mint, .teal, .yellow, .red, .brown]
        }
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
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(visibleAccounts.prefix(4), id: \.objectID) { account in
                        AccountChipCard(account: account) {
                            selectedAccount = account
                            showingAccountDetail = true
                        }
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
        if let raw = UserDefaults.standard.string(forKey: "ReportsLastWalletPeriod"),
           let period = ReportsViewModel.WalletPeriod(rawValue: raw) {
            return period
        }
        return .month
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
    
    private var activityBreakdown: [Decimal] {
        let calendar = Calendar.current
        let now = Date()
        let entries = accountViewModel.recentTransactions(limit: 1000, daysBack: nil)
        
        switch activityPeriod {
        case .week:
            let weekStart = startOfWeek(for: now, calendar: calendar)
            var daily: [Decimal] = Array(repeating: Decimal(0), count: 7)
            
            for dayOffset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                      let dayStart = Optional(calendar.startOfDay(for: day)),
                      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                
                let dayEntries = entries.filter { entry in
                    guard let date = entry.date else { return false }
                    return date >= dayStart && date < dayEnd
                }
                
                for entry in dayEntries {
                    guard let account = entry.account, !account.isHiddenFlag else { continue }
                    let amount = entry.signedAmount
                    if amount < 0 {
                        daily[dayOffset] += abs(amount)
                    }
                }
            }
            return daily
            
        case .month:
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
                return Array(repeating: Decimal(0), count: 4)
            }
            
            let monthEntries = entries.filter { entry in
                guard let date = entry.date else { return false }
                return date >= startOfMonth && date < endOfMonth
            }
            
            var weekly: [Decimal] = Array(repeating: Decimal(0), count: 4)
            let dayCount = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            let daysPerWeek = max(1, (dayCount + 3) / 4)
            
            for entry in monthEntries {
                guard let account = entry.account, !account.isHiddenFlag,
                      let date = entry.date else { continue }
                let amount = entry.signedAmount
                guard amount < 0 else { continue }
                
                let day = calendar.component(.day, from: date)
                let weekIndex = min(3, (day - 1) / daysPerWeek)
                weekly[weekIndex] += abs(amount)
            }
            
            return weekly
            
        case .year:
            let year = calendar.component(.year, from: now)
            guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let _ = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                return Array(repeating: Decimal(0), count: 12)
            }
            
            var monthly: [Decimal] = Array(repeating: Decimal(0), count: 12)
            
            for monthOffset in 0..<12 {
                guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: yearStart),
                      let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { continue }
                
                let monthEntries = entries.filter { entry in
                    guard let date = entry.date else { return false }
                    return date >= monthStart && date < monthEnd
                }
                
                for entry in monthEntries {
                    guard let account = entry.account, !account.isHiddenFlag else { continue }
                    let amount = entry.signedAmount
                    if amount < 0 {
                        monthly[monthOffset] += abs(amount)
                    }
                }
            }
            
            return monthly
        }
    }
    
    private var maxActivityValue: Decimal {
        max(activityBreakdown.max() ?? Decimal(1), Decimal(1))
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
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
                
                if let amount = entry.amount {
                    let formattedAmount = abs(amount.decimalValue).formatted(.currency(code: "USD"))
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
