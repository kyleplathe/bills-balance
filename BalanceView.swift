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

private enum BalancePrivacy {
    static let placeholder = "$••••••"
}

// MARK: - Main Balance View
struct BalanceView: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var appLockManager: AppLockManager
    @State private var showingManageAccounts = false
    @State private var showingReports = false
    @State private var showingAddAccount = false
    @State private var showingAccountDetail: Bool = false
    @State private var selectedAccount: Account?
    @State private var showInactiveAccounts = false
    @AppStorage("hideBalances") private var hideBalances = false
    @State private var showingTransfer = false
    @State private var currentAccountPage = 0
    @State private var activityChartAppeared = false
    @State private var selectedRecentTransaction: LedgerEntry?
    
    var body: some View {
        NavigationStack {
            navigationContent
        }
    }
    
    private var navigationContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if accountViewModel.accounts.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 8) {
                        summaryChipCards
                        if !visibleAccounts.isEmpty {
                            accountsSection
                        }
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
                transferButton
                menuButton
            }
        }
        .sheet(isPresented: $showingManageAccounts) {
            ManageAccountsView()
                .environmentObject(accountViewModel)
                .environmentObject(billViewModel)
                .environmentObject(paycheckViewModel)
                .environmentObject(appLockManager)
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
        .sheet(isPresented: $showingTransfer) {
            TransferPickerSheet()
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
        }
        .navigationDestination(isPresented: $showingReports) {
            ReportsView()
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
                .environmentObject(reportsViewModel)
                .environmentObject(categoryManager)
                .environmentObject(billViewModel)
        }
        .navigationDestination(isPresented: $showingAccountDetail) {
            if let account = selectedAccount {
                AccountDetailView(account: account)
                    .environmentObject(accountViewModel)
                    .environmentObject(bitcoinPriceService)
                    .environmentObject(categoryManager)
                    .environmentObject(billViewModel)
                    .environmentObject(reportsViewModel)
            }
        }
        .sheet(item: Binding(
            get: { selectedRecentTransaction.map { LedgerEntrySheetItem($0) } },
            set: { selectedRecentTransaction = $0?.entry }
        )) { item in
            TransactionEditorSheet(entry: item.entry)
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
                .environmentObject(categoryManager)
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
        .accessibilityLabel("Add Account")
    }

    private var transferButton: some View {
        Button {
            showingTransfer = true
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
        }
        .accessibilityLabel("Transfer")
        .disabled(visibleAccounts.count < 2)
    }
    
    private var menuButton: some View {
        Menu {
            Button {
                showingManageAccounts = true
            } label: {
                Label("Manage Accounts", systemImage: "building.columns")
            }

            Button {
                withAnimation {
                    showInactiveAccounts.toggle()
                    currentAccountPage = 0
                }
            } label: {
                Label(
                    showInactiveAccounts ? "Hide Inactive Accounts" : "Show Inactive Accounts",
                    systemImage: showInactiveAccounts ? "eye.slash" : "eye"
                )
            }
            .disabled(!hasInactiveAccounts && !showInactiveAccounts)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
        .accessibilityLabel("More")
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
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow(alignment: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    currentBalanceChip
                    if !visibleAccounts.isEmpty {
                        Text("Accounts")
                            .font(.title3.weight(.semibold))
                    }
                }
                periodActivityChip
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                activityChartAppeared = true
            }
        }
    }

    private var currentBalanceChip: some View {
        ChipCard(verticalPadding: 10, horizontalPadding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                FittedChipLine(
                    text: "Total Balance",
                    maxSize: 13,
                    minSize: 10,
                    weight: .medium,
                    color: .secondary
                )

                Button {
                    HapticManager.shared.buttonTapped()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hideBalances.toggle()
                    }
                } label: {
                    FittedChipLine(
                        text: displayedTotalBalance,
                        maxSize: 26,
                        minSize: 13,
                        weight: .bold,
                        design: .rounded
                    )
                    .contentTransition(.opacity)
                    .privacySensitive()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    hideBalances
                        ? "Total balance hidden"
                        : "Total balance \(totalBalance.formatted(.currency(code: "USD")))"
                )
                .accessibilityHint("Shows or hides total balance")

                FittedChipLine(
                    text: balanceChipSubtitle,
                    maxSize: 13,
                    minSize: 10,
                    weight: .regular,
                    color: .secondary
                )
            }
        }
    }

    private var periodActivityChip: some View {
        Button {
            showingReports = true
        } label: {
            ChipCard(verticalPadding: 10, horizontalPadding: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    FittedChipLine(
                        text: activityChipTitle,
                        maxSize: 13,
                        minSize: 10,
                        weight: .medium,
                        color: .secondary
                    )

                    FittedChipLine(
                        text: activityChipSpendingText,
                        maxSize: 20,
                        minSize: 12,
                        weight: .bold,
                        design: .rounded
                    )
                    .privacySensitive()

                    CompactWalletStackedCategoryBarChart(
                        period: activityPeriod,
                        appeared: activityChartAppeared,
                        date: reportsViewModel.presentPeriodAnchor()
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activityAccessibilityLabel)
    }
    
    // MARK: - Accounts Section
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                                        .frame(height: AccountChipLayout.height)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(pageIndex)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: AccountChipLayout.pageHeight)
                    
                    // Custom page indicator below the chips
                    if totalPages > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<totalPages, id: \.self) { index in
                                Circle()
                                    .fill(index == currentAccountPage ? Color.primary : Color.secondary.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var visibleAccounts: [Account] {
        let filtered = showInactiveAccounts
            ? accountViewModel.accounts
            : accountViewModel.accounts.filter { !$0.isHiddenFlag }
        
        return filtered.sorted { account1, account2 in
            if account1.order != account2.order {
                return account1.order < account2.order
            }
            if let date1 = account1.createdAt, let date2 = account2.createdAt {
                return date1 < date2
            }
            return false
        }
    }
    
    // MARK: - Recent Transactions Section
    
    private var recentTransactionsSection: some View {
        let transactions = recentTransactions.prefix(5)
        return Group {
            if !transactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.title3.weight(.semibold))
                    
                    VStack(spacing: 0) {
                        ForEach(Array(transactions), id: \.objectID) { entry in
                            if let account = entry.account {
                                TransactionRow(
                                    entry: entry,
                                    account: account,
                                    showsRunningBalance: false,
                                    showsAccountInSubtitle: true,
                                    showsReconcileControl: false,
                                    onReconcile: { entry in
                                        HapticManager.shared.buttonTapped()
                                        selectedRecentTransaction = entry
                                    }
                                ) {
                                    HapticManager.shared.buttonTapped()
                                    selectedRecentTransaction = entry
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var hasInactiveAccounts: Bool {
        accountViewModel.accounts.contains { $0.isHiddenFlag }
    }
    
    private var activityAccessibilityLabel: String {
        "\(activityChipTitle). Opens reports."
    }

    private var activityChipTitle: String {
        switch activityPeriod {
        case .week: return "Weekly Activity"
        case .month: return "Monthly Activity"
        case .year: return "Yearly Activity"
        }
    }

    private var displayedTotalBalance: String {
        hideBalances
            ? BalancePrivacy.placeholder
            : totalBalance.formatted(.currency(code: "USD"))
    }

    private var activityChipSpendingText: String {
        periodSpendingTotal.formatted(.currency(code: "USD"))
    }

    private var periodSpendingTotal: Decimal {
        reportsViewModel.periodSpendingTotal(for: activityPeriod)
    }

    private var balanceChipSubtitle: String {
        let count = visibleAccounts.count
        if count == 0 { return "No accounts" }
        return "\(count) Account\(count == 1 ? "" : "s")"
    }
    
    private var totalBalance: Decimal {
        accountViewModel.totalAvailableBalance(bitcoinPriceService: bitcoinPriceService)
    }
    
    private var activityPeriod: ReportsViewModel.WalletPeriod {
        reportsViewModel.lastUsedWalletPeriod
    }
    
    private var recentTransactions: [LedgerEntry] {
        accountViewModel.recentTransactions(limit: 20, daysBack: 30)
            .filter { entry in
                guard let account = entry.account else { return false }
                return showInactiveAccounts || !account.isHiddenFlag
            }
    }

}

// MARK: - Chip Card Component

/// One line of chip text that uses the largest font that still fits the available width.
/// Display amounts use proportional lining figures (SF default) so pairs like "11" don’t
/// pick up the extra side-bearing that tabular/`monospacedDigit` figures add.
private struct FittedChipLine: View {
    let text: String
    var maxSize: CGFloat
    var minSize: CGFloat
    var weight: Font.Weight
    var color: Color = .primary
    var design: Font.Design = .default

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(candidateSizes, id: \.self) { size in
                line(size: size)
                    .fixedSize(horizontal: true, vertical: false)
            }
            line(size: minSize)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var candidateSizes: [CGFloat] {
        stride(from: maxSize, through: minSize, by: -1).map { $0 }
    }

    private func line(size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: design))
            .foregroundStyle(color)
            .lineLimit(1)
            .allowsTightening(true)
    }
}

private struct ChipCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var verticalPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    var fillHeight: Bool = false
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
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
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

private enum AccountChipLayout {
    static let height: CGFloat = 72
    static let spacing: CGFloat = 12
    static var pageHeight: CGFloat { height * 2 + spacing }
}

private struct AccountChipCard: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let account: Account
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                FittedChipLine(
                    text: displayedBalance,
                    maxSize: 24,
                    minSize: 13,
                    weight: .bold,
                    color: .white,
                    design: .rounded
                )
                .privacySensitive()
                HStack(spacing: 4) {
                    FittedChipLine(
                        text: account.name ?? "Account",
                        maxSize: 13,
                        minSize: 10,
                        weight: .regular,
                        color: .white.opacity(0.9)
                    )
                    if account.isHiddenFlag {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accountGradient)
            )
        }
        .buttonStyle(.plain)
        .frame(height: AccountChipLayout.height)
        .opacity(account.isHiddenFlag ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityBalanceLabel)
    }
    
    private var displayedBalance: String {
        formatAccountBalanceUSD(accountViewModel.totalBalance(for: account), account: account)
    }
    
    private var accessibilityBalanceLabel: String {
        let name = account.name ?? "Account"
        return "\(name), \(displayedBalance)"
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

