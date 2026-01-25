//
//  AccountDetailView.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let account: Account
    
    @State private var showingCurrencyToggle: Bool = false // false = USD, true = BTC
    @State private var showingBalanceDetails: Bool = false
    @State private var showingEditAccount = false
    @State private var showingAddTransaction = false
    @State private var showingTransfer = false
    @State private var selectedTransaction: LedgerEntry?
    @State private var showingTransactionEditor = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                balanceChipCard
                transactionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
    }
    
    // MARK: - Balance Chip Card
    
    private var balanceChipCard: some View {
        VStack(spacing: 0) {
            // Main content area with centered balance
            ZStack(alignment: .center) {
                // Large centered balance display (centered both horizontally and vertically)
                // With rotating marquee animation when switching currencies
                VStack(spacing: 4) {
                    ZStack {
                        // USD value (shown when showingCurrencyToggle is false)
                        if !showingCurrencyToggle {
                            Text(formattedBalance)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
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
                                .font(.system(size: 36, weight: .bold, design: .rounded))
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
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                
                // Currency toggle button - only for digital wallet (BTC) accounts, positioned at top-right
                // Shows only one button at a time, switches between $ and ₿
                if account.currencyCode == "BTC" {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingCurrencyToggle.toggle()
                                }
                            } label: {
                                Text(showingCurrencyToggle ? "₿" : "$")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.3))
                                    )
                            }
                            .padding(.trailing, 20)
                            .padding(.top, 16)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 80)
            
            // Account name and balance details dropdown using iOS DisclosureGroup
            DisclosureGroup(isExpanded: $showingBalanceDetails) {
                VStack(spacing: 12) {
                    balanceDetailRow(label: "Available", value: formattedAvailableBalance)
                    balanceDetailRow(label: "Pending", value: formattedPendingBalance)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(account.name ?? "Account")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Text("Balance")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .tint(.white.opacity(0.9))
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accountGradient)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
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
    
    private var totalBalance: Decimal {
        accountViewModel.totalBalance(for: account)
    }
    
    private var availableBalance: Decimal {
        // Available balance = cleared (reconciled) balance minus pending bills/income
        // This represents the balance available after accounting for pending obligations
        // Base it on cleared balance (reconciled transactions only)
        let clearedBal = accountViewModel.clearedBalance(for: account)
        let availableBal = accountViewModel.availableBalance(
            for: account,
            billViewModel: billViewModel,
            paycheckViewModel: paycheckViewModel,
            bitcoinPriceService: bitcoinPriceService
        )
        // Calculate the difference between total and available (pending bills/income)
        let totalBal = accountViewModel.totalBalance(for: account)
        let pendingAdjustment = totalBal - availableBal
        // Apply the same adjustment to cleared balance
        return clearedBal - pendingAdjustment
    }
    
    private var pendingBalance: Decimal {
        // Pending balance = unreconciled transactions
        // This represents transactions that haven't been reconciled yet
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        if account.currencyCode == "BTC" {
            let unreconciledSum = entries.reduce(Decimal.zero) { partial, entry in
                !entry.isReconciledFlag ? partial + entry.signedAmountInCurrency(for: account) : partial
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
                return formatBTCBalance(availableBalance)
            } else {
                // Convert BTC to USD for display
                let usd = bitcoinPriceService.convertBTCToUSD(availableBalance)
                return formatUSDBalance(usd)
            }
        } else {
            return formatUSDBalance(availableBalance)
        }
    }
    
    private var formattedPendingBalance: String {
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                return formatBTCBalance(pendingBalance)
            } else {
                // Convert BTC to USD for display
                let usd = bitcoinPriceService.convertBTCToUSD(pendingBalance)
                return formatUSDBalance(usd)
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
            // Display in sats with commas
            let sats = balance * 100_000_000
            let satsDouble = (sats as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 0
            let formattedSats = formatter.string(from: NSNumber(value: satsDouble)) ?? String(format: "%.0f", satsDouble)
            return "\(formattedSats) sats"
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
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transactions")
                .font(.headline)
                .padding(.horizontal, 4)
            
            if accountTransactions.isEmpty {
                Text("No transactions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(accountTransactions, id: \.objectID) { entry in
                        TransactionRow(entry: entry, account: account, showingCurrencyToggle: showingCurrencyToggle) {
                            selectedTransaction = entry
                            showingTransactionEditor = true
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private var accountTransactions: [LedgerEntry] {
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        return Array(entries)
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
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let entry: LedgerEntry
    let account: Account
    let showingCurrencyToggle: Bool
    let onTap: () -> Void
    
    private var transactionAmount: Decimal {
        if account.currencyCode == "BTC" {
            return entry.amountInCurrency(for: account)
        } else {
            return entry.amountDecimal
        }
    }
    
    private var runningBalance: Decimal {
        // Calculate running balance up to this transaction
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        let sortedEntries = Array(entries)
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
            if e.objectID == entry.objectID {
                // Add this transaction's amount to get balance after this transaction
                if account.currencyCode == "BTC" {
                    balance += e.signedAmountInCurrency(for: account)
                } else {
                    balance += e.signedAmount
                }
                break
            }
            // Add previous transactions
            if account.currencyCode == "BTC" {
                balance += e.signedAmountInCurrency(for: account)
            } else {
                balance += e.signedAmount
            }
        }
        return balance
    }
    
    private var formattedAmount: String {
        let amount = abs(transactionAmount)
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                return formatBTCAmount(amount)
            } else {
                // Convert to USD
                let usd = bitcoinPriceService.convertBTCToUSD(amount)
                return formatUSDAmount(usd)
            }
        } else {
            return formatUSDAmount(amount)
        }
    }
    
    private var formattedRunningBalance: String {
        let balance = runningBalance
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                return formatBTCAmount(balance)
            } else {
                // Convert to USD
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
            return "\(formattedSats) sats"
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
        HStack(alignment: .top, spacing: 12) {
            // Transaction status icon - green circle with white checkmark for cleared
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
                // Transaction amount
                Text((entry.isCredit ? "+" : "-") + formattedAmount)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(entry.isCredit ? .green : .red)
                
                // Running balance after this transaction
                Text(formattedRunningBalance)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
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
        
        // Initialize amount strings based on entry data
        if let account = entry.account, account.currencyCode == "BTC" {
            let btc = entry.btcAmountDecimal
            if btc != .zero {
                let displayFormat = account.btcDisplayFormat ?? "sats"
                if displayFormat == "sats" {
                    let sats = btc * 100_000_000
                    let satsDouble = (sats as NSDecimalNumber).doubleValue
                    _btcSatsAmountString = State(initialValue: String(format: "%.0f", satsDouble))
                } else {
                    let btcDouble = (btc as NSDecimalNumber).doubleValue
                    _btcSatsAmountString = State(initialValue: String(format: "%.8f", btcDouble))
                }
            }
            let usd = entry.usdAmountDecimal
            if usd != .zero {
                let usdDouble = (usd as NSDecimalNumber).doubleValue
                _usdAmountString = State(initialValue: String(format: "%.2f", usdDouble))
            }
            let price = entry.btcPriceAtTransactionDecimal
            if price != .zero {
                let priceDouble = (price as NSDecimalNumber).doubleValue
                _btcPriceString = State(initialValue: String(format: "%.2f", priceDouble))
            }
        } else {
            let usd = entry.usdAmountDecimal
            if usd != .zero {
                let usdDouble = (usd as NSDecimalNumber).doubleValue
                _usdAmountString = State(initialValue: String(format: "%.2f", usdDouble))
            } else {
                let amount = entry.amountDecimal
                if amount != .zero {
                    let amountDouble = (amount as NSDecimalNumber).doubleValue
                    _usdAmountString = State(initialValue: String(format: "%.2f", amountDouble))
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Title", text: $title)
                    
                    Picker("", selection: $isCredit) {
                        Text("Add (+)").tag(true)
                        Text("Subtract (-)").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                
                if let account = entry.account, account.currencyCode == "BTC" {
                    Section("Bitcoin Amount") {
                        TextField("Sats", text: $btcSatsAmountString)
                            .keyboardType(.numberPad)
                    }
                    Section("USD Amount") {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                        }
                    }
                    Section("BTC Price") {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $btcPriceString)
                                .keyboardType(.decimalPad)
                        }
                    }
                } else {
                    Section("Amount") {
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                
                Section {
                    Toggle("Reconciled", isOn: $isCleared)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
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
                        saveTransaction()
                    }
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled()
        }
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
            category: categoryValue
        )
        
        // Refresh the account to update balances
        accountViewModel.fetchAccounts()
        
        dismiss()
    }
}
