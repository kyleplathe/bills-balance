//
//  AccountDetailView.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI
import CoreData

struct AccountDetailView: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let account: Account
    
    @State private var showingCurrencyToggle: Bool = false // false = USD, true = BTC (for chip card only)
    @State private var showingBalanceDetails: Bool = false
    @State private var showingEditAccount = false
    @State private var showingAddTransaction = false
    @State private var showingTransfer = false
    @State private var selectedTransaction: LedgerEntry?
    @State private var showingTransactionEditor = false
    @State private var accountTransactions: [LedgerEntry] = []
    @State private var showingReconcileDrawer = false
    @State private var transactionToReconcile: LedgerEntry?
    @State private var reconcileSatsString: String = ""
    @State private var reconcileBTCPriceString: String = ""
    @State private var lastShakeTime: Date = Date.distantPast
    
    var body: some View {
        List {
            // Balance chip card section
            Section {
                balanceChipCard
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            
            // Transactions section
            if accountTransactions.isEmpty {
                Section {
                    Text("No transactions yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 32, leading: 20, bottom: 32, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Transactions")
                        .font(.headline)
                }
            } else {
                ForEach(groupedTransactions.keys.sorted(by: >), id: \.self) { monthDate in
                    let transactions = transactionsForMonth(monthDate)
                    Section(header: monthSectionHeader(for: monthDate)) {
                    ForEach(transactions, id: \.objectID) { entry in
                        TransactionRow(
                            entry: entry,
                            account: account,
                            onReconcile: { entry in
                                transactionToReconcile = entry
                                showingReconcileDrawer = true
                            }
                        ) {
                            selectedTransaction = entry
                            showingTransactionEditor = true
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Edit account button
                Button {
                    showingEditAccount = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.title2)
                }
                
                // Add transaction button
                Button {
                    showingAddTransaction = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                
                // Transfer button
                Button {
                    showingTransfer = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                }
            }
        }
        .sheet(isPresented: $showingEditAccount) {
            AccountEditorSheet(account: account) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage in
                accountViewModel.updateAccount(account,
                                               name: name,
                                               type: type,
                                               startingBalance: startingBalance,
                                               isHidden: isHidden,
                                               currency: currency,
                                               btcDisplayFormat: btcDisplayFormat,
                                               feePercentage: feePercentage)
                accountViewModel.fetchAccounts()
            }
            .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingAddTransaction) {
            ManualTransactionEntrySheet(account: account)
                .environmentObject(accountViewModel)
                .environmentObject(categoryManager)
                .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingTransfer) {
            // TODO: Implement transfer view
            Text("Transfer functionality coming soon")
                .padding()
        }
        .sheet(isPresented: $showingTransactionEditor) {
            if let entry = selectedTransaction {
                TransactionEditorSheet(entry: entry)
                    .environmentObject(accountViewModel)
                    .environmentObject(bitcoinPriceService)
                    .environmentObject(categoryManager)
            }
        }
        .sheet(isPresented: $showingReconcileDrawer) {
            if let entry = transactionToReconcile {
                TransactionReconcileDrawer(
                    entry: entry,
                    satsString: $reconcileSatsString,
                    btcPriceString: $reconcileBTCPriceString,
                    onSave: {
                        saveReconciledTransaction(entry: entry)
                    },
                    onCancel: {
                        showingReconcileDrawer = false
                        transactionToReconcile = nil
                        reconcileSatsString = ""
                        reconcileBTCPriceString = ""
                    }
                )
                .environmentObject(bitcoinPriceService)
                .presentationDetents([.medium])
            }
        }
        .onChange(of: showingReconcileDrawer) { oldValue, newValue in
            if newValue, let entry = transactionToReconcile {
                // Initialize fields when drawer opens
                if entry.btcAmountDecimal > 0 {
                    // Already has sats - populate fields
                    let sats = entry.btcAmountDecimal * 100_000_000
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.maximumFractionDigits = 0
                    formatter.groupingSeparator = ","
                    reconcileSatsString = formatter.string(from: sats as NSDecimalNumber) ?? ""
                }
                
                if entry.btcPriceAtTransactionDecimal > 0 {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.maximumFractionDigits = 2
                    reconcileBTCPriceString = formatter.string(from: entry.btcPriceAtTransactionDecimal as NSDecimalNumber) ?? ""
                } else {
                    // Pre-fill with current BTC price
                    let currentPrice = bitcoinPriceService.btcToUsdRate
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.maximumFractionDigits = 2
                    reconcileBTCPriceString = formatter.string(from: currentPrice as NSDecimalNumber) ?? ""
                }
            }
        }
        .onAppear {
            loadTransactions()
        }
        .onChange(of: showingAddTransaction) { _, newValue in
            if !newValue {
                // Refresh when add transaction sheet is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadTransactions()
                }
            }
        }
        .onChange(of: showingTransactionEditor) { _, newValue in
            if !newValue {
                // Refresh when transaction editor is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadTransactions()
                }
            }
        }
        .onChange(of: account.objectID) { _, _ in
            // Refresh when account changes
            loadTransactions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)) { _ in
            // Refresh transactions when Core Data saves (e.g., when reconciled status changes)
            loadTransactions()
        }
        .onChange(of: bitcoinPriceService.showInBitcoin) { _, _ in
            // Refresh view when currency display changes
        }
        .onShake {
            // Debounce: prevent rapid shakes (at least 0.5 seconds apart)
            let now = Date()
            guard now.timeIntervalSince(lastShakeTime) > 0.5 else { return }
            lastShakeTime = now
            
            // Toggle bitcoin display mode (only for BTC accounts)
            if account.currencyCode == "BTC" {
                withAnimation {
                    bitcoinPriceService.showInBitcoin.toggle()
                }
            }
        }
    }
    
    // MARK: - Balance Chip Card
    
    private var balanceChipCard: some View {
        ZStack {
            // Main content area with centered balance
            VStack(spacing: 0) {
                // Date at the top, centered vertically in the space above the balance
                Spacer()
                    .frame(minHeight: 20)
                
                Text(currentDateString)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 8)
                
                Spacer()
                    .frame(minHeight: 20)
                
                // Balance amount section - centered and tappable (for BTC accounts)
                VStack(spacing: 4) {
                    if account.currencyCode == "BTC" {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingCurrencyToggle.toggle()
                            }
                        } label: {
                            ZStack {
                                // USD value (shown when showingCurrencyToggle is false)
                                if !showingCurrencyToggle {
                                    Text(formattedBalance)
                                        .font(.system(size: dynamicBalanceFontSize, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)
                                        ))
                                }
                                
                                // BTC value (shown when showingCurrencyToggle is true)
                                if showingCurrencyToggle {
                                    Text(formattedBalance)
                                        .font(.system(size: dynamicBalanceFontSize, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)
                                        ))
                                }
                            }
                            .id(showingCurrencyToggle ? "btc" : "usd")
                            .frame(height: dynamicBalanceFontSize + 10) // Reserve space for balance
                        }
                        .buttonStyle(.plain)
                    } else {
                        // USD accounts - just show the balance
                        Text(formattedBalance)
                            .font(.system(size: dynamicBalanceFontSize, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                            .frame(height: dynamicBalanceFontSize + 10)
                    }
                    
                    // USD equivalent for BTC accounts when showing BTC
                    if account.currencyCode == "BTC" && showingCurrencyToggle {
                        Text("≈ \(usdEquivalent)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .transition(.opacity)
                    } else if account.currencyCode == "BTC" && !showingCurrencyToggle {
                        Text("≈ \(btcEquivalent)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                // Account name and balance details - simple expand/collapse
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingBalanceDetails.toggle()
                        }
                    } label: {
                        HStack {
                            Text("\(account.name ?? "Account") Balance")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Image(systemName: showingBalanceDetails ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if showingBalanceDetails {
                        VStack(spacing: 0) {
                            balanceDetailRow(label: "Available", value: formattedAvailableBalance)
                                .padding(.vertical, 8)
                                .padding(.top, 8)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                            
                            balanceDetailRow(label: "Pending", value: formattedPendingBalance)
                                .padding(.vertical, 8)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accountGradient)
                .shadow(
                    color: Color.black.opacity(0.25),
                    radius: 16,
                    x: 0,
                    y: 6
                )
        )
    }
    
    private func balanceDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: Date())
    }
    
    private var dynamicBalanceFontSize: CGFloat {
        // Calculate font size based on the number of characters in the formatted balance
        // Longer numbers get smaller font, shorter numbers get larger font
        let balanceString = formattedBalance
        let characterCount = balanceString.count
        
        // Base font size for short numbers (up to 8 characters)
        let baseSize: CGFloat = 72
        
        // Reduce font size for longer numbers
        // Formula: baseSize - (characterCount - 8) * 4, with minimum of 32
        if characterCount <= 8 {
            return baseSize
        } else if characterCount <= 12 {
            return baseSize - CGFloat((characterCount - 8) * 4)
        } else if characterCount <= 16 {
            return baseSize - CGFloat(16 + (characterCount - 12) * 3)
        } else {
            return max(32, baseSize - CGFloat(28 + (characterCount - 16) * 2))
        }
    }
    
    private var totalBalance: Decimal {
        accountViewModel.totalBalance(for: account)
    }
    
    private var availableBalance: Decimal {
        // Available balance = Cleared Balance (traditional checkbook balancing)
        // Available = Starting Balance + only reconciled (checked) transactions
        // This is mathematically equivalent to: Total Balance - Pending Balance
        // But using clearedBalance is more direct and matches checkbook logic
        let cleared = accountViewModel.clearedBalance(for: account)
        
        // Debug logging for BTC accounts
        if account.currencyCode == "BTC" {
            let total = totalBalance
            let pending = pendingBalance
            print("🔍 Available Balance Calculation (BTC Account: \(account.name ?? "Unknown")):")
            print("   Starting Balance: \(account.startingBalanceDecimal) BTC")
            print("   Total Balance: \(total) BTC")
            print("   Pending Balance: \(pending) BTC")
            print("   Cleared Balance (Available): \(cleared) BTC")
            print("   Verification (Total - Pending): \(total - pending) BTC")
            if showingCurrencyToggle {
                print("   Display Format: \(account.btcDisplayFormat ?? "sats")")
            } else {
                let usd = bitcoinPriceService.convertBTCToUSD(cleared)
                print("   Available in USD: \(usd)")
            }
        }
        
        return cleared
    }
    
    private var pendingBalance: Decimal {
        // Pending balance = sum of unreconciled (unchecked) transactions
        // This represents transactions that haven't been reconciled yet
        // In checkbook terms: these are pending transactions that haven't cleared
        let entries = accountViewModel.ledgerEntries(for: account)
        if account.currencyCode == "BTC" {
            // For BTC accounts: use sats if available, otherwise use USD for pending
            let unreconciledSum = entries.reduce(Decimal.zero) { partial, entry in
                guard !entry.isReconciledFlag else { return partial }
                
                // If transaction has sats, use sats amount
                if entry.btcAmountDecimal > 0 {
                    return partial + entry.signedAmountInCurrency(for: account)
                } else {
                    // No sats yet - use USD amount for pending (will convert for display)
                    let usdAmount = entry.usdAmountDecimal
                    return partial + (entry.isCredit ? usdAmount : -usdAmount)
                }
            }
            return unreconciledSum
        } else {
            let unreconciledSum = entries.reduce(Decimal.zero) { partial, entry in
                !entry.isReconciledFlag ? partial + entry.signedAmount : partial
            }
            return unreconciledSum
        }
    }
    
    private var formattedBalance: String {
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                // Show in BTC/sats
                return formatBTCBalance(totalBalance)
            } else {
                // Show in USD (convert from BTC)
                let usd = bitcoinPriceService.convertBTCToUSD(totalBalance)
                return formatUSDBalance(usd)
            }
        } else {
            // For USD accounts, always show in USD
            return formatUSDBalance(totalBalance)
        }
    }
    
    private var formattedAvailableBalance: String {
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                // Show in BTC/sats format
                return formatBTCBalance(availableBalance)
            } else {
                // Convert BTC to USD for display
                let usd = bitcoinPriceService.convertBTCToUSD(availableBalance)
                print("🔍 Available Balance Formatting (BTC Account):")
                print("   Available Balance (BTC): \(availableBalance)")
                print("   Converted to USD: \(usd)")
                return formatUSDBalance(usd)
            }
        } else {
            return formatUSDBalance(availableBalance)
        }
    }
    
    private var formattedPendingBalance: String {
        if account.currencyCode == "BTC" {
            // Check if pending balance is in USD (from transactions without sats)
            let entries = accountViewModel.ledgerEntries(for: account)
            let hasUnreconciledWithoutSats = entries.contains { entry in
                !entry.isReconciledFlag && entry.btcAmountDecimal == 0 && entry.usdAmountDecimal > 0
            }
            
            if showingCurrencyToggle {
                // If showing BTC/sats, check if we need to convert USD to BTC
                if hasUnreconciledWithoutSats {
                    // Some pending transactions are in USD - convert to BTC for display
                    let usdPending = entries.reduce(Decimal.zero) { partial, entry in
                        guard !entry.isReconciledFlag, entry.btcAmountDecimal == 0 else { return partial }
                        let usdAmount = entry.usdAmountDecimal
                        return partial + (entry.isCredit ? usdAmount : -usdAmount)
                    }
                    let btcPending = bitcoinPriceService.convertUSDtoBTC(usdPending)
                    // Add BTC pending (transactions with sats)
                    let btcPendingWithSats = entries.reduce(Decimal.zero) { partial, entry in
                        guard !entry.isReconciledFlag, entry.btcAmountDecimal > 0 else { return partial }
                        return partial + entry.signedAmountInCurrency(for: account)
                    }
                    return formatBTCBalance(btcPending + btcPendingWithSats)
                } else {
                    return formatBTCBalance(pendingBalance)
                }
            } else {
                // Showing USD - if pending has USD amounts, show them directly
                if hasUnreconciledWithoutSats {
                    let usdPending = entries.reduce(Decimal.zero) { partial, entry in
                        guard !entry.isReconciledFlag else { return partial }
                        if entry.btcAmountDecimal > 0 {
                            // Has sats - convert to USD
                            let btcAmount = entry.signedAmountInCurrency(for: account)
                            return partial + bitcoinPriceService.convertBTCToUSD(abs(btcAmount)) * (btcAmount >= 0 ? 1 : -1)
                        } else {
                            // No sats - use USD directly
                            let usdAmount = entry.usdAmountDecimal
                            return partial + (entry.isCredit ? usdAmount : -usdAmount)
                        }
                    }
                    return formatUSDBalance(usdPending)
                } else {
                    // All pending have sats - convert BTC to USD
                    let usd = bitcoinPriceService.convertBTCToUSD(pendingBalance)
                    return formatUSDBalance(usd)
                }
            }
        } else {
            return formatUSDBalance(pendingBalance)
        }
    }
    
    private var usdEquivalent: String {
        let usd = bitcoinPriceService.convertBTCToUSD(totalBalance)
        return formatUSDBalance(usd)
    }
    
    private var btcEquivalent: String {
        return formatBTCBalance(totalBalance)
    }
    
    private func formatUSDBalance(_ balance: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: balance as NSDecimalNumber) ?? "$\(balance)"
    }
    
    private func formatBTCBalance(_ balance: Decimal) -> String {
        let displayFormat = account.btcDisplayFormat ?? "sats"
        
        if displayFormat == "sats" {
            // Display in sats with commas and ₿ symbol
            let sats = balance * 100_000_000
            let satsDouble = (sats as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 0
            let formattedSats = formatter.string(from: NSNumber(value: satsDouble)) ?? String(format: "%.0f", satsDouble)
            return "₿ \(formattedSats) sats"
        } else {
            // Display in BTC with decimals and commas
            let btcDouble = (balance as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
            let formattedBTC = formatter.string(from: NSNumber(value: btcDouble)) ?? String(format: "%.8f", btcDouble)
            return "₿ \(formattedBTC)"
        }
    }
    
    private var accountGradient: LinearGradient {
        let baseBlue = Color.blue
        let darkerBlue = Color(red: 0.0, green: 0.4, blue: 0.8)
        
        let hash = abs((account.name ?? "").hashValue)
        let variation = Double(hash % 20) / 100.0
        
        return LinearGradient(
            gradient: Gradient(colors: [
                baseBlue.opacity(1.0 - variation),
                darkerBlue.opacity(0.9 + variation)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Transactions Section
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private var groupedTransactions: [Date: [LedgerEntry]] {
        let calendar = Calendar.current
        return Dictionary(grouping: accountTransactions) { entry in
            guard let date = entry.date else { return Date.distantPast }
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? Date.distantPast
        }
    }
    
    private func transactionsForMonth(_ monthDate: Date) -> [LedgerEntry] {
        return groupedTransactions[monthDate] ?? []
    }
    
    private func monthSectionHeader(for date: Date) -> some View {
        Text(monthFormatter.string(from: date))
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
    
    private func loadTransactions() {
        // Try multiple approaches to fetch transactions
        var entries: [LedgerEntry] = []
        
        // First, try using the account's relationship directly
        if let accountEntries = account.ledgerEntries as? Set<LedgerEntry> {
            entries = Array(accountEntries)
        }
        
        // If relationship is empty or not loaded, use ViewModel method
        if entries.isEmpty {
            entries = accountViewModel.ledgerEntries(for: account)
        }
        
        accountTransactions = entries
            .sorted { entry1, entry2 in
                // Sort by date descending (most recent first)
                guard let date1 = entry1.date, let date2 = entry2.date else {
                    return false
                }
                if date1 != date2 {
                    return date1 > date2
                }
                // If dates are equal, sort by creation date
                guard let created1 = entry1.createdAt, let created2 = entry2.createdAt else {
                    return false
                }
                return created1 > created2
            }
    }
    
    private func saveReconciledTransaction(entry: LedgerEntry) {
        // Get sats amount
        let cleanedSats = reconcileSatsString.replacingOccurrences(of: ",", with: "")
        guard let sats = Int(cleanedSats), sats > 0 else {
            return
        }
        
        // Convert sats to BTC
        let btcAmount = Decimal(sats) / 100_000_000
        
        // Get BTC price (use provided or calculate from USD and BTC)
        let btcPrice: Decimal
        if !reconcileBTCPriceString.isEmpty {
            let cleanedPrice = reconcileBTCPriceString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            btcPrice = Decimal(string: cleanedPrice) ?? bitcoinPriceService.btcToUsdRate
        } else {
            // Calculate from USD amount and BTC amount
            let usdAmount = entry.usdAmountDecimal
            btcPrice = usdAmount > 0 && btcAmount > 0 ? usdAmount / btcAmount : bitcoinPriceService.btcToUsdRate
        }
        
        // Update the entry with sats and price
        entry.btcAmount = NSDecimalNumber(decimal: btcAmount)
        entry.amount = NSDecimalNumber(decimal: btcAmount) // Set amount to BTC for BTC accounts
        entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
        
        // Mark as reconciled
        entry.isReconciledFlag = true
        
        // Save and refresh
        accountViewModel.saveContext()
        accountViewModel.fetchAccounts()
        loadTransactions()
        
        // Close drawer
        showingReconcileDrawer = false
        transactionToReconcile = nil
        reconcileSatsString = ""
        reconcileBTCPriceString = ""
    }
}

// MARK: - Transaction Reconcile Drawer

private struct TransactionReconcileDrawer: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let entry: LedgerEntry
    @Binding var satsString: String
    @Binding var btcPriceString: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focusedField: Field?
    
    enum Field {
        case sats
        case btcPrice
    }
    
    private var usdAmount: Decimal {
        entry.usdAmountDecimal
    }
    
    private var formattedUSDAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: usdAmount as NSDecimalNumber) ?? "$0.00"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("USD Amount")
                        Spacer()
                        Text(formattedUSDAmount)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Transaction Amount")
                }
                
                Section {
                    HStack {
                        TextField("Sats", text: $satsString)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .sats)
                            .onChange(of: satsString) { _, newValue in
                                // Auto-calculate BTC price when sats are entered
                                autoCalculatePrice()
                            }
                        if !satsString.isEmpty {
                            Button {
                                satsString = ""
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
                        } else {
                            Text("$\(formatPrice(bitcoinPriceService.btcToUsdRate))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Bitcoin Details")
                } footer: {
                    if !satsString.isEmpty, let sats = Int(satsString.replacingOccurrences(of: ",", with: "")) {
                        let btcAmount = Decimal(sats) / 100_000_000
                        let calculatedPrice = usdAmount > 0 && btcAmount > 0 ? usdAmount / btcAmount : Decimal(0)
                        if calculatedPrice > 0 {
                            Text("Calculated price: $\(formatPrice(calculatedPrice))")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Reconcile Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(satsString.isEmpty)
                }
            }
            .onAppear {
                focusedField = .sats
            }
        }
    }
    
    private func autoCalculatePrice() {
        let cleanedSats = satsString.replacingOccurrences(of: ",", with: "")
        guard let sats = Int(cleanedSats), sats > 0, usdAmount > 0 else {
            btcPriceString = ""
            return
        }
        
        let btcAmount = Decimal(sats) / 100_000_000
        guard btcAmount > 0 else {
            btcPriceString = ""
            return
        }
        
        let calculatedPrice = usdAmount / btcAmount
        btcPriceString = formatPrice(calculatedPrice)
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: price as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let entry: LedgerEntry
    let account: Account
    let onReconcile: (LedgerEntry) -> Void
    let onTap: () -> Void
    
    private var transactionAmount: Decimal {
        if account.currencyCode == "BTC" {
            // For BTC accounts, use BTC amount for BTC display, USD amount for USD display
            if bitcoinPriceService.showInBitcoin {
                return entry.amountInCurrency(for: account)
            } else {
                // Show USD amount directly (stored USD value with correct sign)
                let usd = entry.usdAmountDecimal
                return entry.isCredit ? usd : -usd
            }
        } else {
            return entry.amountDecimal
        }
    }
    
    private var runningBalance: Decimal {
        // Calculate running balance up to and including this transaction
        // Traditional checkbook: running balance = starting balance + all transactions up to this point
        // This shows the balance after each transaction in chronological order
        let entries = accountViewModel.ledgerEntries(for: account)
        let sortedEntries = entries
            .sorted { entry1, entry2 in
                guard let date1 = entry1.date, let date2 = entry2.date else { return false }
                if date1 != date2 {
                    return date1 < date2
                }
                guard let created1 = entry1.createdAt, let created2 = entry2.createdAt else { return false }
                return created1 < created2
            }
        
        var balance = account.startingBalanceDecimal
        for e in sortedEntries {
            // Add this transaction's amount
            if account.currencyCode == "BTC" {
                balance += e.signedAmountInCurrency(for: account)
            } else {
                balance += e.signedAmount
            }
            
            // If we've reached the current transaction, return the balance
            if e.objectID == entry.objectID {
                break
            }
        }
        return balance
    }
    
    private var formattedAmount: String {
        let amount = abs(transactionAmount)
        if account.currencyCode == "BTC" {
            if bitcoinPriceService.showInBitcoin {
                return formatBTCAmount(amount)
            } else {
                // Show USD amount directly
                return formatUSDAmount(amount)
            }
        } else {
            return formatUSDAmount(amount)
        }
    }
    
    private var formattedRunningBalance: String {
        let balance = runningBalance
        if account.currencyCode == "BTC" {
            if bitcoinPriceService.showInBitcoin {
                return formatBTCAmount(balance)
            } else {
                // Convert running balance to USD using current BTC price
                let usd = bitcoinPriceService.convertBTCToUSD(balance)
                return formatUSDAmount(usd)
            }
        } else {
            return formatUSDAmount(balance)
        }
    }
    
    private func formatUSDAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
    
    private func formatBTCAmount(_ amount: Decimal) -> String {
        let displayFormat = account.btcDisplayFormat ?? "sats"
        if displayFormat == "sats" {
            let sats = amount * 100_000_000
            let satsDouble = (sats as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 0
            let formattedSats = formatter.string(from: NSNumber(value: satsDouble)) ?? String(format: "%.0f", satsDouble)
            return "₿ \(formattedSats) sats"
        } else {
            let btcDouble = (amount as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
            let formattedBTC = formatter.string(from: NSNumber(value: btcDouble)) ?? String(format: "%.8f", btcDouble)
            return "₿ \(formattedBTC)"
        }
    }
    
    private func formatTransactionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Transaction status icon - green circle with white checkmark for cleared
            // Tappable to toggle reconciled status
            Button {
                // Check if this is a BTC account and transaction is missing sats
                if account.currencyCode == "BTC" && !entry.isReconciledFlag && entry.btcAmountDecimal == 0 {
                    // Missing sats - show reconciliation drawer
                    onReconcile(entry)
                } else {
                    // Has sats or not BTC account - toggle directly
                    accountViewModel.toggleReconciled(for: entry)
                }
            } label: {
                if entry.isReconciledFlag {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                } else {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                // Transaction title
                Text(entry.title ?? "Transaction")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // Date
                if let date = entry.date {
                    Text(formatTransactionDate(date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Account/Category line
                HStack(spacing: 4) {
                    if let accountName = account.name {
                        Text(accountName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let category = entry.category, !category.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Transaction amount with +/- prefix
                Text((entry.isCredit ? "+ " : "- ") + formattedAmount)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(entry.isCredit ? .green : .red)
                
                // Running balance after this transaction
                Text(formattedRunningBalance)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .id("\(entry.objectID)-\(bitcoinPriceService.showInBitcoin)")
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            // Swipe right to toggle reconciled status
            Button {
                accountViewModel.toggleReconciled(for: entry)
            } label: {
                Label(entry.isReconciledFlag ? "Unreconcile" : "Reconcile", 
                      systemImage: entry.isReconciledFlag ? "circle" : "checkmark.circle.fill")
            }
            .tint(entry.isReconciledFlag ? .orange : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Swipe left to delete
            Button(role: .destructive) {
                accountViewModel.deleteLedgerEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            // Swipe left to edit
            Button {
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Transaction Editor Sheet

private struct TransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var categoryManager: CategoryManager
    
    let entry: LedgerEntry
    
    @State private var date: Date
    @State private var title: String
    @State private var isCredit: Bool
    @State private var btcSatsAmountString: String = ""
    @State private var usdAmountString: String = ""
    @State private var btcPriceString: String = ""
    @State private var feeAmountString: String = ""
    @State private var isCleared: Bool
    @State private var notes: String
    @State private var category: String
    
    init(entry: LedgerEntry) {
        self.entry = entry
        _date = State(initialValue: entry.date ?? Date())
        _title = State(initialValue: entry.title ?? "")
        _isCredit = State(initialValue: entry.isCredit)
        _isCleared = State(initialValue: entry.isReconciledFlag)
        _notes = State(initialValue: entry.notes ?? "")
        _category = State(initialValue: entry.category ?? "")
        
        // Initialize amount strings based on entry data with proper formatting
        if let account = entry.account, account.currencyCode == "BTC" {
            let btc = entry.btcAmountDecimal
            if btc != .zero {
                let displayFormat = account.btcDisplayFormat ?? "sats"
                if displayFormat == "sats" {
                    let sats = btc * 100_000_000
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.groupingSeparator = ","
                    formatter.usesGroupingSeparator = true
                    formatter.maximumFractionDigits = 0
                    _btcSatsAmountString = State(initialValue: formatter.string(from: sats as NSDecimalNumber) ?? "")
                } else {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.groupingSeparator = ","
                    formatter.usesGroupingSeparator = true
                    formatter.minimumFractionDigits = 2
                    formatter.maximumFractionDigits = 8
                    _btcSatsAmountString = State(initialValue: formatter.string(from: btc as NSDecimalNumber) ?? "")
                }
            }
            let usd = entry.usdAmountDecimal
            if usd != .zero {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.groupingSeparator = ","
                formatter.usesGroupingSeparator = true
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                _usdAmountString = State(initialValue: formatter.string(from: abs(usd) as NSDecimalNumber) ?? "")
            }
            let price = entry.btcPriceAtTransactionDecimal
            if price != .zero {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.groupingSeparator = ","
                formatter.usesGroupingSeparator = true
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                _btcPriceString = State(initialValue: formatter.string(from: price as NSDecimalNumber) ?? "")
            }
            // Initialize fee amount if present
            let fee = entry.feeAmountDecimal
            if fee != .zero {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.groupingSeparator = ","
                formatter.usesGroupingSeparator = true
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                _feeAmountString = State(initialValue: formatter.string(from: fee as NSDecimalNumber) ?? "")
            }
        } else {
            let usd = entry.usdAmountDecimal
            if usd != .zero {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.groupingSeparator = ","
                formatter.usesGroupingSeparator = true
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                _usdAmountString = State(initialValue: formatter.string(from: abs(usd) as NSDecimalNumber) ?? "")
            } else {
                let amount = entry.amountDecimal
                if amount != .zero {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.groupingSeparator = ","
                    formatter.usesGroupingSeparator = true
                    formatter.minimumFractionDigits = 2
                    formatter.maximumFractionDigits = 2
                    _usdAmountString = State(initialValue: formatter.string(from: abs(amount) as NSDecimalNumber) ?? "")
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Title", text: $title)
                            .onChange(of: title) { _, newValue in
                                // Auto-categorize based on transaction name
                                if category.isEmpty {
                                    let suggested = CategorySuggester.suggest(for: newValue)
                                    if !suggested.isEmpty {
                                        category = suggested
                                    }
                                }
                            }
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
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("", selection: $isCredit) {
                        Text("Add (+)").tag(true)
                        Text("Subtract (-)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                } header: {
                    Text("Transaction Details")
                }
                    
                if let account = entry.account, account.currencyCode == "BTC" {
                    Section {
                        // Sats Amount
                        HStack {
                            TextField("Sats Amount", text: $btcSatsAmountString)
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
                        
                        // USD Amount
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("USD Amount", text: $usdAmountString)
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
                        
                        // Fee Amount
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("Fee (Optional)", text: $feeAmountString)
                                .keyboardType(.decimalPad)
                            if !feeAmountString.isEmpty {
                                Button {
                                    feeAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        
                        // BTC Price (read-only display of current or stored price)
                        HStack {
                            Text("BTC Price")
                            Spacer()
                            if !btcPriceString.isEmpty {
                                Text("$\(btcPriceString)")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(formatPrice(bitcoinPriceService.btcToUsdRate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Amount")
                    }
                } else {
                    Section {
                        // USD accounts - simple amount field
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
                    
                    Toggle("Cleared", isOn: $isCleared)
                } header: {
                    Text("Additional Information")
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
                        saveTransaction()
                    }
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled()
        }
    }
    
    private func formatPrice(_ price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: price as NSDecimalNumber) ?? "$0.00"
    }
    
    private func saveTransaction() {
        guard let account = entry.account else {
            dismiss()
            return
        }
        
        let btcAmount: Decimal? = {
            if account.currencyCode == "BTC" {
                let displayFormat = account.btcDisplayFormat ?? "sats"
                if displayFormat == "sats" {
                    if let sats = Int(btcSatsAmountString), sats != 0 {
                        let btc = Decimal(sats) / 100_000_000 // Convert sats to BTC
                        return isCredit ? btc : -btc
                    }
                } else {
                    let cleaned = btcSatsAmountString.replacingOccurrences(of: ",", with: "")
                    if let btc = Decimal(string: cleaned), btc != 0 {
                        return isCredit ? btc : -btc
                    }
                }
            }
            return nil
        }()
        
        let usdAmount: Decimal? = {
            let cleaned = usdAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            if let amount = Decimal(string: cleaned), amount != 0 {
                return isCredit ? amount : -amount
            }
            return nil
        }()
        
        let btcPrice: Decimal? = {
            if account.currencyCode == "BTC" {
                let cleaned = btcPriceString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                if let price = Decimal(string: cleaned), price > 0 {
                    return price
                }
            }
            return nil
        }()
        
        let feeAmount: Decimal? = {
            if account.currencyCode == "BTC" {
                let cleaned = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                if let fee = Decimal(string: cleaned), fee > 0 {
                    return fee
                }
            }
            return nil
        }()
        
        let categoryValue = category.isEmpty ? nil : category
        
        accountViewModel.updateLedgerEntry(
            entry,
            date: date,
            title: title,
            btcAmount: btcAmount,
            usdAmount: usdAmount,
            btcPrice: btcPrice,
            isReconciled: isCleared,
            notes: notes.isEmpty ? nil : notes,
            category: categoryValue,
            feeAmount: feeAmount
        )
        
        // Refresh the account to update balances
        accountViewModel.fetchAccounts()
        accountViewModel.saveContext()
        
        // Refresh transactions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Trigger refresh via notification
            NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
        }
        
        dismiss()
    }
}
