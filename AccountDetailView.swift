//
//  AccountDetailView.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct AccountDetailView: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    
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
    @State private var showingImportPicker = false
    @State private var showingStatementImportSheet = false
    @State private var statementImportFileName = ""
    @State private var statementImportTransactions: [ParsedStatementTransaction] = []
    @State private var showStatementImportSuccessAlert = false
    @State private var statementImportResult: StatementImportResult?
    @State private var isImportParsing = false
    @State private var importErrorMessage: String?
    @State private var showImportErrorAlert = false
    @State private var showingUsdBtcBacktest = false
    
    var body: some View {
        accountList
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
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
            AccountEditorSheet(account: account) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage, startingBalanceUSD, startingBalanceBTCPrice in
                accountViewModel.updateAccount(account,
                                               name: name,
                                               type: type,
                                               startingBalance: startingBalance,
                                               isHidden: isHidden,
                                               currency: currency,
                                               btcDisplayFormat: btcDisplayFormat,
                                               feePercentage: feePercentage,
                                               startingBalanceUSD: startingBalanceUSD,
                                               startingBalanceBTCPrice: startingBalanceBTCPrice)
                accountViewModel.fetchAccounts()
            }
            .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingAddTransaction) {
            TransactionEditorSheet(account: account)
                .environmentObject(accountViewModel)
                .environmentObject(categoryManager)
                .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingTransfer) {
            TransferSheet(fromAccount: account)
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
        }
        .sheet(isPresented: $showingUsdBtcBacktest) {
            UsdBtcBacktestView()
                .environmentObject(reportsViewModel)
                .environmentObject(bitcoinPriceService)
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleStatementFile(result)
        }
        .sheet(isPresented: $showingStatementImportSheet) {
            StatementImportSheet(
                fileName: statementImportFileName,
                transactions: statementImportTransactions,
                initialAccount: account,
                onImport: handleStatementImport
            )
            .environmentObject(accountViewModel)
            .environmentObject(categoryManager)
        }
        .overlay {
            if isImportParsing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Reading file…")
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .alert("Import Error", isPresented: $showImportErrorAlert, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .alert("Import successful", isPresented: $showStatementImportSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            statementImportSuccessMessage
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
            if newValue, let entry = transactionToReconcile, let account = entry.account {
                // Initialize fields when drawer opens
                let displayFormat = account.btcDisplayFormat ?? "sats"
                
                if entry.btcAmountDecimal > 0 {
                    // Already has BTC amount - populate fields
                    if displayFormat == "sats" {
                        let sats = entry.btcAmountDecimal * 100_000_000
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 0
                        formatter.groupingSeparator = ","
                        formatter.usesGroupingSeparator = true
                        reconcileSatsString = formatter.string(from: sats as NSDecimalNumber) ?? ""
                    } else {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.groupingSeparator = ","
                        formatter.usesGroupingSeparator = true
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 8
                        reconcileSatsString = formatter.string(from: entry.btcAmountDecimal as NSDecimalNumber) ?? ""
                    }
                }
                
                if entry.btcPriceAtTransactionDecimal > 0 {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.maximumFractionDigits = 2
                    reconcileBTCPriceString = formatter.string(from: entry.btcPriceAtTransactionDecimal as NSDecimalNumber) ?? ""
                } else {
                    // Pre-fill with current BTC price as a starting point
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
        .onChange(of: showingTransfer) { _, newValue in
            if !newValue {
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
            let now = Date()
            guard now.timeIntervalSince(lastShakeTime) > 0.5 else { return }
            lastShakeTime = now

            if account.currencyCode == "BTC" {
                withAnimation {
                    bitcoinPriceService.showInBitcoin.toggle()
                }
                if bitcoinPriceService.showInBitcoin {
                    bitcoinPriceService.fetchBitcoinPrice()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var accountList: some View {
        List {
            Section {
                balanceHero
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Statement", systemImage: "square.and.arrow.down")
                }
                if account.isBitcoinDigitalWallet {
                    Button {
                        showingUsdBtcBacktest = true
                    } label: {
                        Label("USD vs Bitcoin", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            transactionsSection
        }
    }
    
    private var transactionsSection: some View {
        Group {
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
                if !pendingTransactions.isEmpty {
                    Section {
                        ForEach(pendingTransactions, id: \.objectID) { entry in
                            transactionRow(for: entry)
                        }
                    }
                }
                ForEach(groupedTransactions.keys.sorted(by: >), id: \.self) { monthDate in
                    let transactions = transactionsForMonth(monthDate)
                    Section(header: monthSectionHeader(for: monthDate)) {
                        ForEach(transactions, id: \.objectID) { entry in
                            transactionRow(for: entry)
                        }
                    }
                }
            }
        }
    }
    
    private func transactionRow(for entry: LedgerEntry) -> some View {
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
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }
    
    // MARK: - Balance Hero
    
    private var balanceHero: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                if account.currencyCode == "BTC" {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingCurrencyToggle.toggle()
                        }
                    } label: {
                        ZStack {
                            if !showingCurrencyToggle {
                                Text(formattedAvailableBalance)
                                    .font(.system(size: dynamicHeroBalanceFontSize, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            }
                            
                            if showingCurrencyToggle {
                                Text(formattedAvailableBalance)
                                    .font(.system(size: dynamicHeroBalanceFontSize, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            }
                        }
                        .id(showingCurrencyToggle ? "btc" : "usd")
                        .frame(height: dynamicHeroBalanceFontSize + 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Available balance \(formattedAvailableBalance). Double tap to switch currency.")
                    
                    Text(showingCurrencyToggle ? "≈ \(usdEquivalent)" : "≈ \(btcEquivalent)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(formattedAvailableBalance)
                        .font(.system(size: dynamicHeroBalanceFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: dynamicHeroBalanceFontSize + 8)
                        .accessibilityLabel("Available balance \(formattedAvailableBalance)")
                }
            }
            
            balanceDetailsDisclosure
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    
    private var balanceDetailsDisclosure: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.32)) {
                    showingBalanceDetails.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Balance")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showingBalanceDetails ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .modifier(BalanceDetailsPillChrome())
            .accessibilityLabel(showingBalanceDetails ? "Hide Balance" : "Balance")
            .accessibilityHint("Shows cleared and pending")
            
            if showingBalanceDetails {
                VStack(spacing: 6) {
                    balanceBreakdownRow(label: "Cleared", value: formattedClearedBalance)
                    balanceBreakdownRow(
                        label: "Pending",
                        value: formattedPendingBalance,
                        valueColor: pendingForeground
                    )
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .clipped()
    }
    
    private func balanceBreakdownRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
    
    // MARK: - Cleared Balance Formatters
    
    private var clearedBalance: Decimal {
        accountViewModel.clearedBalance(for: account)
    }
    
    private var formattedClearedBalance: String {
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                return formatBTCBalance(clearedBalance)
            } else {
                let usd = bitcoinPriceService.convertBTCToUSD(clearedBalance)
                return formatUSDBalance(usd)
            }
        } else {
            return formatUSDBalance(clearedBalance)
        }
    }
    
    private var dynamicHeroBalanceFontSize: CGFloat {
        let balanceString = formattedAvailableBalance
        let characterCount = balanceString.count
        let baseSize: CGFloat = 48
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
    
    // MARK: - Balance Chip Card (Deprecated)
    
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
                
                // Account name and balance details - expands card
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingBalanceDetails.toggle()
                    }
                } label: {
                    HStack {
                        Text("\(account.name ?? "Account") Balance")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .rotationEffect(.degrees(showingBalanceDetails ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                
                if showingBalanceDetails {
                    VStack(spacing: 0) {
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.top, 12)
                        
                        balanceDetailRow(label: "Available", value: formattedAvailableBalance)
                            .padding(.vertical, 12)
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                        
                        balanceDetailRow(label: "Pending", value: formattedPendingBalance)
                            .padding(.vertical, 12)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    ))
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
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
        totalBalance
    }
    
    private var pendingForeground: Color {
        if pendingBalance > 0 { return .green }
        if pendingBalance < 0 { return .orange }
        return .secondary
    }
    
    private var pendingBalance: Decimal {
        // Pending balance = sum of unreconciled (unchecked) transactions
        // This represents transactions that haven't been reconciled yet
        // In checkbook terms: these are pending transactions that haven't cleared
        let entries = accountViewModel.ledgerEntries(for: account)
        if account.currencyCode == "BTC" {
            // For BTC accounts: use signedAmountInCurrency which handles conversion properly
            let unreconciledSum = entries.reduce(Decimal.zero) { partial, entry in
                guard !entry.isReconciledFlag else { return partial }
                // Use signedAmountInCurrency which properly handles BTC/sats conversion
                return partial + entry.signedAmountInCurrency(for: account)
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
        let balance = availableBalance
        
        if account.currencyCode == "BTC" {
            if showingCurrencyToggle {
                // Show in BTC/sats format
                return formatBTCBalance(balance)
            } else {
                // Convert BTC to USD for display
                let usd = bitcoinPriceService.convertBTCToUSD(balance)
                return formatUSDBalance(usd)
            }
        } else {
            return formatUSDBalance(balance)
        }
    }

    private var formattedPendingBalance: String {
        let pending = pendingBalance
        
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
                    return formatBTCBalance(pending)
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
                    let usd = bitcoinPriceService.convertBTCToUSD(pending)
                    return formatUSDBalance(usd)
                }
            }
        } else {
            return formatUSDBalance(pending)
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
        // Always show $0.00 for zero values
        if balance == 0 {
            return "$0.00"
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: balance as NSDecimalNumber) ?? "$0.00"
    }
    
    private func formatBTCBalance(_ balance: Decimal) -> String {
        // Always show 0 for zero values
        if balance == 0 {
            let displayFormat = account.btcDisplayFormat ?? "sats"
            if displayFormat == "sats" {
                return "₿ 0 sats"
            } else {
                return "₿ 0.00000000"
            }
        }
        
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
    
    private var pendingTransactions: [LedgerEntry] {
        accountTransactions.filter { !$0.isReconciledFlag }
    }
    
    private var groupedTransactions: [Date: [LedgerEntry]] {
        let calendar = Calendar.current
        let cleared = accountTransactions.filter { $0.isReconciledFlag }
        return Dictionary(grouping: cleared) { entry in
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

    private var statementImportSuccessMessage: Text {
        guard let result = statementImportResult else {
            return Text("Import complete.")
        }
        var parts: [String] = []
        parts.append("Imported \(result.importedCount) transaction\(result.importedCount == 1 ? "" : "s")")
        if result.skippedCount > 0 {
            parts[0] += " and skipped \(result.skippedCount) duplicate\(result.skippedCount == 1 ? "" : "s")"
        }
        parts[0] += "."
        if result.matchedCount > 0 {
            parts.append("Marked \(result.matchedCount) matching bill\(result.matchedCount == 1 ? "" : "s") paid.")
        }
        if result.keptBalance && result.importedCount > 0 {
            parts.append("Current balance is unchanged.")
        }
        return Text(parts.joined(separator: " "))
    }

    private func handleStatementFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let fileName = url.lastPathComponent
            isImportParsing = true
            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AccountExportError.decodeFailed
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    let txs = try TransactionCSVParser.parse(data: data)
                    await MainActor.run {
                        isImportParsing = false
                        statementImportFileName = fileName
                        statementImportTransactions = txs
                    }
                    try await Task.sleep(nanoseconds: 350_000_000)
                    await MainActor.run {
                        showingStatementImportSheet = true
                    }
                } catch {
                    await MainActor.run {
                        isImportParsing = false
                        importErrorMessage = error.localizedDescription
                        showImportErrorAlert = true
                    }
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportErrorAlert = true
        }
    }

    private func handleStatementImport(account: Account, transactions: [ParsedStatementTransaction], keepCurrentBalance: Bool) {
        let result = StatementImportRunner.importTransactions(
            account: account,
            transactions: transactions,
            keepCurrentBalance: keepCurrentBalance,
            accountViewModel: accountViewModel,
            billViewModel: billViewModel
        )
        reportsViewModel.refresh()
        statementImportResult = result
        showStatementImportSuccessAlert = true
        loadTransactions()
    }
    
    private func loadTransactions() {
        account.managedObjectContext?.refresh(account, mergeChanges: true)
        let entries = accountViewModel.ledgerEntries(for: account)
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
        guard let account = entry.account else { return }
        
        // Get BTC amount (sats or BTC based on account display format)
        let displayFormat = account.btcDisplayFormat ?? "sats"
        let cleaned = reconcileSatsString.replacingOccurrences(of: ",", with: "")
        
        let btcAmount: Decimal
        if displayFormat == "sats" {
            guard let sats = Int(cleaned), sats > 0 else {
                return
            }
            btcAmount = Decimal(sats) / 100_000_000
        } else {
            guard let btc = Decimal(string: cleaned), btc > 0 else {
                return
            }
            btcAmount = btc
        }
        
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

private struct BalanceDetailsPillChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
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

    private var usdAmount: Decimal {
        entry.usdAmountDecimal
    }

    private var formattedUSDAmount: String {
        MoneyFormatting.currencyString(usdAmount)
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
                    MoneyTextField(
                        text: $satsString,
                        kind: MoneyFormatting.kindForBTCDisplay(entry.account?.btcDisplayFormat ?? "sats"),
                        placeholder: (entry.account?.btcDisplayFormat ?? "sats") == "sats" ? "Sats" : "BTC Amount",
                        accessibilityLabel: "Bitcoin amount",
                        suffix: (entry.account?.btcDisplayFormat ?? "sats") == "sats" ? "sats" : nil,
                        autoFocus: true
                    )
                    .onChange(of: satsString) { _, _ in
                        autoCalculatePrice()
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
                    if !satsString.isEmpty {
                        let account = entry.account
                        let displayFormat = account?.btcDisplayFormat ?? "sats"
                        let cleaned = satsString.replacingOccurrences(of: ",", with: "")
                        
                        let btcAmount: Decimal = {
                            if displayFormat == "sats" {
                                if let sats = Int(cleaned) {
                                    return Decimal(sats) / 100_000_000
                                } else {
                                    return 0
                                }
                            } else {
                                return Decimal(string: cleaned) ?? 0
                            }
                        }()
                        
                        let calculatedPrice = usdAmount > 0 && btcAmount > 0 ? usdAmount / btcAmount : Decimal(0)
                        
                        if calculatedPrice > 0 {
                            Text("Calculated price: $\(formatPrice(calculatedPrice))")
                                .font(.caption)
                        } else {
                            EmptyView()
                        }
                    }
                }
            }
            .navigationTitle("Reconcile Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    canSave: !satsString.isEmpty,
                    onClose: onCancel,
                    onSave: onSave
                )
            }
        }
    }
    
    private func autoCalculatePrice() {
        guard let account = entry.account else {
            btcPriceString = ""
            return
        }
        
        let displayFormat = account.btcDisplayFormat ?? "sats"
        let cleaned = satsString.replacingOccurrences(of: ",", with: "")
        
        let btcAmount: Decimal
        if displayFormat == "sats" {
            guard let sats = Int(cleaned), sats > 0, usdAmount > 0 else {
                btcPriceString = ""
                return
            }
            btcAmount = Decimal(sats) / 100_000_000
        } else {
            guard let btc = Decimal(string: cleaned), btc > 0, usdAmount > 0 else {
                btcPriceString = ""
                return
            }
            btcAmount = btc
        }
        
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
