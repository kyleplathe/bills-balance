//
//  AccountViewModel.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import Foundation
import CoreData

class AccountViewModel: ObservableObject {
    
    @Published var accounts: [Account] = []
    @Published var ledgerEntries: [LedgerEntry] = []
    @Published var selectedAccount: Account? {
        didSet {
            refreshLedgerEntries()
        }
    }
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        fetchAccounts()
        if selectedAccount == nil {
            selectedAccount = accounts.first
        }
        refreshLedgerEntries()
    }
    
    // MARK: - Fetch Data
    func fetchAccounts() {
        // Ensure we're on the main thread for UI updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.fetchAccounts()
            }
            return
        }
        
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Account.order, ascending: true),
            NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)
        ]
        
        do {
            let fetched = try context.fetch(request)
            // Refresh context to ensure we have latest data
            context.refreshAllObjects()
            accounts = fetched
            if let selected = selectedAccount, fetched.contains(selected) {
                // keep current selection
            } else {
                selectedAccount = fetched.first
            }
        } catch {
            print("Error fetching accounts: \(error)")
            accounts = []
            selectedAccount = nil
        }
    }
    
    func refreshLedgerEntries() {
        guard let account = selectedAccount else {
            ledgerEntries = []
            return
        }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@", account)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: true),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: true)
        ]
        
        do {
            ledgerEntries = try context.fetch(request)
        } catch {
            print("Error fetching ledger entries: \(error)")
            ledgerEntries = []
        }
    }
    
    // MARK: - Accounts
    @discardableResult
    func addAccount(name: String, type: String, startingBalance: Decimal, isHidden: Bool = false, currency: String = "USD", btcDisplayFormat: String = "sats", feePercentage: Decimal = 0, startingBalanceUSD: Decimal? = nil, startingBalanceBTCPrice: Decimal? = nil) -> Account {
        let account = Account(context: context)
        account.id = UUID()
        account.name = name
        account.type = type
        account.startingBalance = NSDecimalNumber(decimal: startingBalance)
        account.createdAt = Date()
        account.updatedAt = Date()
        // Set order to 0 so new accounts appear first
        account.order = 0
        // Shift existing accounts' order down
        for existingAccount in accounts {
            existingAccount.order += 1
        }
        account.isHiddenFlag = isHidden
        account.currencyCode = currency
        account.btcDisplayFormat = btcDisplayFormat
        account.feePercentageDecimal = feePercentage
        
        // Store USD value and BTC price for BTC starting balances
        if let usdValue = startingBalanceUSD {
            account.startingBalanceUSD = NSDecimalNumber(decimal: usdValue)
        }
        if let btcPrice = startingBalanceBTCPrice {
            account.startingBalanceBTCPrice = NSDecimalNumber(decimal: btcPrice)
        }
        
        saveContext()
        fetchAccounts()
        selectedAccount = account
        refreshLedgerEntries()
        return account
    }
    
    func updateAccount(_ account: Account, name: String, type: String, startingBalance: Decimal, isHidden: Bool = false, currency: String = "USD", btcDisplayFormat: String = "sats", feePercentage: Decimal = 0, startingBalanceUSD: Decimal? = nil, startingBalanceBTCPrice: Decimal? = nil) {
        account.name = name
        account.type = type
        account.startingBalance = NSDecimalNumber(decimal: startingBalance)
        account.updatedAt = Date()
        account.isHiddenFlag = isHidden
        account.currencyCode = currency
        account.btcDisplayFormat = btcDisplayFormat
        account.feePercentageDecimal = feePercentage
        
        // Store USD value and BTC price for BTC starting balances
        if let usdValue = startingBalanceUSD {
            account.startingBalanceUSD = NSDecimalNumber(decimal: usdValue)
        } else {
            account.startingBalanceUSD = nil
        }
        if let btcPrice = startingBalanceBTCPrice {
            account.startingBalanceBTCPrice = NSDecimalNumber(decimal: btcPrice)
        } else {
            account.startingBalanceBTCPrice = nil
        }
        
        saveContext()
        fetchAccounts()
        if let updated = accounts.first(where: { $0.objectID == account.objectID }) {
            selectedAccount = updated
            refreshLedgerEntries()
        }
    }
    
    func updateAccountBalance(_ account: Account, newBalance: Decimal) {
        account.startingBalance = NSDecimalNumber(decimal: newBalance)
        account.updatedAt = Date()
        saveContext()
        fetchAccounts()
        if let updated = accounts.first(where: { $0.objectID == account.objectID }) {
            selectedAccount = updated
            refreshLedgerEntries()
        }
    }
    
    func deleteAccount(_ account: Account) {
        context.delete(account)
        saveContext()
        fetchAccounts()
        refreshLedgerEntries()
    }
    
    func reorderAccounts(draggedAccount: Account, targetAccount: Account) {
        guard draggedAccount != targetAccount else { return }
        var ordered = accounts
        guard let fromIndex = ordered.firstIndex(where: { $0.objectID == draggedAccount.objectID }),
              let toIndex = ordered.firstIndex(where: { $0.objectID == targetAccount.objectID }) else { return }
        let item = ordered.remove(at: fromIndex)
        ordered.insert(item, at: toIndex)
        for (index, account) in ordered.enumerated() {
            account.order = Int16(index)
        }
        saveContext()
        fetchAccounts()
    }
    
    func reorderAccounts(from source: IndexSet, to destination: Int) {
        var ordered = accounts
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, account) in ordered.enumerated() {
            account.order = Int16(index)
        }
        saveContext()
        fetchAccounts()
    }
    
    func account(with id: UUID?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }
    
    func clearedBalance(for account: Account) -> Decimal {
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        if account.currencyCode == "BTC" {
            // For BTC accounts, use BTC amounts from transactions
            let clearedSum = entries.reduce(Decimal.zero) { partial, entry in
                entry.isReconciledFlag ? partial + entry.signedAmountInCurrency(for: account) : partial
            }
            return account.startingBalanceDecimal + clearedSum
        } else {
            // For USD accounts, use regular amounts
            let clearedSum = entries.reduce(Decimal.zero) { partial, entry in
                entry.isReconciledFlag ? partial + entry.signedAmount : partial
            }
            return account.startingBalanceDecimal + clearedSum
        }
    }
    
    func totalBalance(for account: Account) -> Decimal {
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        if account.currencyCode == "BTC" {
            // For BTC accounts, use BTC amounts from transactions
            let totalSum = entries.reduce(Decimal.zero) { partial, entry in
                partial + entry.signedAmountInCurrency(for: account)
            }
            return account.startingBalanceDecimal + totalSum
        } else {
            // For USD accounts, use regular amounts
            let totalSum = entries.reduce(Decimal.zero) { partial, entry in
                partial + entry.signedAmount
            }
            return account.startingBalanceDecimal + totalSum
        }
    }
    
    func totalClearedBalance(bitcoinPriceService: BitcoinPriceService? = nil) -> Decimal {
        accounts.reduce(Decimal.zero) { partial, account in
            let balance = clearedBalance(for: account)
            if account.currencyCode == "BTC" {
                // Convert BTC balance to USD for total
                let priceService = bitcoinPriceService ?? BitcoinPriceService.shared
                return partial + priceService.convertBTCToUSD(balance)
            } else {
                return partial + balance
            }
        }
    }
    
    // MARK: - Available Balance (Current Balance minus Pending Bills plus Pending Income)
    func availableBalance(for account: Account, billViewModel: BillViewModel? = nil, paycheckViewModel: PaycheckViewModel? = nil, bitcoinPriceService: BitcoinPriceService? = nil) -> Decimal {
        // Refresh the account from context to ensure we have latest data
        context.refresh(account, mergeChanges: true)
        
        let currentBalance = totalBalance(for: account)
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        // Get future unpaid bills for this account (bills with dueDate >= today)
        // Only count bills that are unpaid AND have this account assigned
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "account == %@ AND isPaid == NO AND dueDate >= %@", account, startOfToday as NSDate)
        
        do {
            let futureUnpaidBills = try context.fetch(request)
            
            // Debug: Log all bills being considered
            #if DEBUG
            print("🔍 Pending Bills Calculation for \(account.name ?? "Unknown"):")
            print("   Found \(futureUnpaidBills.count) bills with dueDate >= today")
            #endif
            
            let pendingBillsAmount = futureUnpaidBills.reduce(Decimal.zero) { partial, bill in
                // Double-check: only count bills that are unpaid and have this account
                guard !bill.isPaid,
                      bill.account == account,
                      let amount = bill.amount?.decimalValue else {
                    #if DEBUG
                    if bill.account == account {
                        print("   ⚠️ Excluding: \(bill.name ?? "Unknown") - isPaid: \(bill.isPaid), amount: \(bill.amount?.decimalValue ?? 0)")
                    }
                    #endif
                    return partial
                }
                
                // For credit card only bills (no account), they don't affect account balance
                // But if bill has an account, it should be counted
                if let paymentCard = bill.paymentCard, !paymentCard.isEmpty, bill.account == nil {
                    return partial
                }
                
                // Check if this bill has already been paid via ledger entries
                // If a bill has reconciled ledger entries linked to it, it's already been processed
                if let billLedgerEntries = bill.ledgerEntries as? Set<LedgerEntry>, !billLedgerEntries.isEmpty {
                    // Check if any of the bill's ledger entries are reconciled
                    let hasReconciledEntries = billLedgerEntries.contains { $0.isReconciledFlag }
                    if hasReconciledEntries {
                        #if DEBUG
                        print("   ⚠️ Excluding (has reconciled entries): \(bill.name ?? "Unknown") - $\(amount)")
                        #endif
                        return partial
                    }
                }
                
                #if DEBUG
                print("   ✓ Including: \(bill.name ?? "Unknown") - $\(amount) (due: \(bill.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "unknown"))")
                #endif
                
                return partial + amount
            }
            
            // Get pending income (future paychecks for this account that haven't been processed)
            var pendingIncomeAmount: Decimal = .zero
            if let paycheckVM = paycheckViewModel {
                let futureInterval = DateInterval(start: now, end: calendar.date(byAdding: .month, value: 3, to: now) ?? now)
                
                let futureOccurrences = paycheckVM.occurrences(in: futureInterval)
                let accountFutureIncome = futureOccurrences.filter { occurrence in
                    occurrence.paycheck.account == account && occurrence.isProjected
                }
                
                pendingIncomeAmount = accountFutureIncome.reduce(Decimal.zero) { partial, occurrence in
                    guard let amount = occurrence.paycheck.amount?.decimalValue else { return partial }
                    
                    // Check if this paycheck already has a ledger entry (already processed)
                    // Look for ledger entries with matching title and date
                    let ledgerEntries = account.ledgerEntries as? Set<LedgerEntry> ?? []
                    let hasLedgerEntry = ledgerEntries.contains { entry in
                        guard let entryDate = entry.date,
                              let entryTitle = entry.title else { return false }
                        // Check if entry matches this paycheck name and date
                        return entryTitle == occurrence.paycheck.name &&
                               calendar.isDate(entryDate, inSameDayAs: occurrence.date) &&
                               entry.isCredit // Income should be credit entries
                    }
                    
                    // Only count if not already processed
                    if !hasLedgerEntry {
                        return partial + amount
                    }
                    return partial
                }
            }
            
            // Calculate net pending (bills subtract, income adds)
            let netPending = pendingBillsAmount - pendingIncomeAmount
            
            if account.currencyCode == "BTC" {
                // For BTC accounts, convert USD amounts to BTC
                let priceService = bitcoinPriceService ?? BitcoinPriceService.shared
                let btcPending = priceService.convertUSDtoBTC(netPending)
                let result = currentBalance - btcPending
                
                // Debug logging for BTC accounts
                #if DEBUG
                print("🔍 Available Balance Debug (BTC Account: \(account.name ?? "Unknown")):")
                print("   Current Balance: \(currentBalance) BTC")
                print("   Pending Bills: \(pendingBillsAmount) USD = \(btcPending) BTC")
                print("   Pending Income: \(pendingIncomeAmount) USD")
                print("   Net Pending: \(netPending) USD = \(btcPending) BTC")
                print("   Available Balance: \(result) BTC")
                #endif
                
                return result
            } else {
                let result = currentBalance - netPending
                
                // Debug logging for USD accounts
                #if DEBUG
                print("🔍 Available Balance Debug (Account: \(account.name ?? "Unknown")):")
                print("   Current Balance: \(currentBalance)")
                print("   Pending Bills: \(pendingBillsAmount)")
                print("   Pending Income: \(pendingIncomeAmount)")
                print("   Net Pending: \(netPending)")
                print("   Available Balance: \(result)")
                #endif
                
                return result
            }
        } catch {
            print("❌ Error calculating available balance: \(error)")
            return currentBalance
        }
    }
    
    func ledgerEntries(for account: Account) -> [LedgerEntry] {
        // Use objectID comparison for more reliable Core Data object matching
        if let selected = selectedAccount, selected.objectID == account.objectID {
            return ledgerEntries
        }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@", account)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: true),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: true)
        ]
        
        do {
            let entries = try context.fetch(request)
            print("AccountViewModel: Fetched \(entries.count) ledger entries for account: \(account.name ?? "Unknown")")
            return entries
        } catch {
            print("Error fetching ledger entries for account: \(error)")
            return []
        }
    }
    
    // MARK: - Ledger Helpers
    @discardableResult
    func recordLedgerEntry(for bill: Bill,
                           amount: Decimal,
                           date: Date,
                           isCredit: Bool,
                           title: String? = nil,
                           notes: String? = nil,
                           bitcoinPriceService: BitcoinPriceService? = nil,
                           satsAmount: Decimal? = nil) -> LedgerEntry? {
        // Don't create ledger entries for bills paid with credit cards unless they have an explicit account
        // Credit card payments don't affect account balances
        if let paymentCard = bill.paymentCard, !paymentCard.isEmpty, bill.account == nil {
            return nil
        }
        
        guard let account = bill.account ?? selectedAccount else {
            return nil
        }
        
        // Remove any existing entries for this bill before creating a fresh one
        removeLedgerEntries(for: bill)
        
        let entry = LedgerEntry(context: context)
        entry.id = UUID()
        entry.amount = NSDecimalNumber(decimal: amount)
        entry.date = date
        entry.isCredit = isCredit
        entry.entryType = isCredit ? "credit" : "debit"
        entry.title = title ?? bill.name
        entry.notes = notes
        entry.category = bill.category
        entry.createdAt = Date()
        entry.account = account
        entry.bill = bill
        
        // Handle BTC accounts: store both USD and BTC amounts at transaction time
        if account.currencyCode == "BTC" {
            // Store USD amount (from bill)
            entry.usdAmount = NSDecimalNumber(decimal: amount)
            
            if let sats = satsAmount {
                // Use provided sats amount (convert sats to BTC)
                let btcAmount = sats / 100_000_000
                entry.btcAmount = NSDecimalNumber(decimal: btcAmount)
                entry.amount = NSDecimalNumber(decimal: btcAmount) // Store BTC amount for BTC accounts
                
                // Calculate and store BTC price from USD amount and BTC amount
                if btcAmount > 0 {
                    let btcPrice = amount / btcAmount
                    entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
                }
            } else {
                // No sats provided - store USD only, BTC will be entered later
                // Don't set btcAmount or amount yet - will be set when user enters sats
                entry.amount = NSDecimalNumber(decimal: 0) // Temporary, will be updated
            }
        } else {
            // For USD accounts, store USD amount
            entry.usdAmount = NSDecimalNumber(decimal: amount)
        }
        
        saveContext()
        refreshLedgerEntries()
        return entry
    }
    
    func recordLedgerEntry(for paycheck: Paycheck,
                           amount: Decimal,
                           date: Date,
                           title: String? = nil,
                           notes: String? = nil,
                           satsAmount: Decimal? = nil) -> LedgerEntry? {
        guard let account = paycheck.account ?? selectedAccount else {
            return nil
        }
        
        // Remove any existing entries for this paycheck on this date before creating a fresh one
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date < %@ AND category == %@", 
                                       account, startOfDay as NSDate, endOfDay as NSDate, "Income")
        
        do {
            let existingEntries = try context.fetch(request)
            // Find entries that match the paycheck name
            let matchingEntries = existingEntries.filter { entry in
                entry.title == paycheck.name || entry.title == title
            }
            for entry in matchingEntries {
                context.delete(entry)
            }
        } catch {
            print("Error removing existing paycheck entries: \(error)")
        }
        
        let entry = LedgerEntry(context: context)
        entry.id = UUID()
        entry.amount = NSDecimalNumber(decimal: amount)  // Store amount directly, not magnitude
        entry.date = date
        entry.isCredit = true  // Income is always credit
        entry.entryType = "credit"
        entry.title = title ?? paycheck.name ?? "Income"
        entry.notes = notes ?? paycheck.notes
        entry.category = "Income"
        entry.createdAt = Date()
        entry.account = account
        
        // Store paycheck reference in notes (hidden from display)
        if let paycheckId = paycheck.id {
            let existingNotes = entry.notes ?? ""
            let paycheckRef = "\u{200B}__PAYCHECK_ID__:\(paycheckId.uuidString)\u{200B}"
            if !existingNotes.contains("__PAYCHECK_ID__") {
                entry.notes = existingNotes.isEmpty ? paycheckRef : "\(existingNotes)\n\(paycheckRef)"
            }
        }
        
        // Handle BTC accounts: store both USD and BTC amounts
        if account.currencyCode == "BTC" {
            // Store USD amount (from paycheck)
            entry.usdAmount = NSDecimalNumber(decimal: amount)
            
            if let sats = satsAmount {
                // Use provided sats amount (convert sats to BTC)
                let btcAmount = sats / 100_000_000
                entry.btcAmount = NSDecimalNumber(decimal: btcAmount)
                entry.amount = NSDecimalNumber(decimal: btcAmount)
                
                // Calculate and store BTC price from USD amount and BTC amount
                if btcAmount > 0 {
                    let btcPrice = amount / btcAmount
                    entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
                }
            } else {
                // No sats provided - store USD only, BTC will be entered later
                entry.amount = NSDecimalNumber(decimal: 0) // Temporary, will be updated when sats entered
            }
        } else {
            // For USD accounts, store USD amount directly (same as amount)
            entry.usdAmount = NSDecimalNumber(decimal: amount)
        }
        
        saveContext()
        refreshLedgerEntries()
        return entry
    }
    
    func addManualEntry(to account: Account,
                        title: String,
                        btcAmount: Decimal?,
                        usdAmount: Decimal?,
                        btcPriceAtTransaction: Decimal?,
                        date: Date,
                        notes: String?,
                        isReconciled: Bool,
                        category: String? = nil,
                        paycheck: Paycheck? = nil,
                        feeAmount: Decimal? = nil) {
        let entry = LedgerEntry(context: context)
        entry.id = UUID()
        entry.title = title
        entry.date = date
        entry.createdAt = Date()
        entry.account = account
        entry.notes = notes
        entry.category = category
        entry.isReconciledFlag = isReconciled
        
        // Explicitly mark income transactions as credits - this MUST be set before any amount logic
        let isIncome = (category == "Income")
        
        if account.currencyCode == "BTC" {
            // For BTC accounts, store BTC and USD amounts
            if let btc = btcAmount {
                entry.btcAmount = NSDecimalNumber(decimal: btc.magnitude)
                entry.amount = NSDecimalNumber(decimal: btc.magnitude) // Set amount to BTC amount for display purposes
                // Income is always credit, regardless of amount sign
                entry.isCredit = isIncome
                entry.entryType = entry.isCredit ? "credit" : "debit"
            } else if let usd = usdAmount, let price = btcPriceAtTransaction, price > 0 {
                // USD only entry - calculate BTC amount from USD and current price
                let calculatedBTC = abs(usd.magnitude) / price
                entry.btcAmount = NSDecimalNumber(decimal: calculatedBTC)
                entry.amount = NSDecimalNumber(decimal: calculatedBTC) // Set amount to calculated BTC for display
                // Determine credit/debit from USD amount sign
                entry.isCredit = (usd >= 0) || isIncome
                entry.entryType = entry.isCredit ? "credit" : "debit"
            } else if let usd = usdAmount {
                // USD only entry without price - amount will be set to 0 temporarily (will be updated when reconciled)
                entry.amount = NSDecimalNumber(decimal: 0)
                // Determine credit/debit from USD amount sign
                entry.isCredit = (usd >= 0) || isIncome
                entry.entryType = entry.isCredit ? "credit" : "debit"
            }
            if let usd = usdAmount {
                entry.usdAmount = NSDecimalNumber(decimal: usd.magnitude)
            }
            if let price = btcPriceAtTransaction {
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: price)
            }
        } else {
            // For USD accounts, use regular amount
            if let usd = usdAmount {
                // Ensure we store the amount in both fields for consistency
                let amountValue = usd.magnitude
                entry.amount = NSDecimalNumber(decimal: amountValue)
                entry.usdAmount = NSDecimalNumber(decimal: amountValue)
                // Income is ALWAYS credit - set this explicitly and unconditionally
                if isIncome {
                    entry.isCredit = true
                    entry.entryType = "credit"
                } else {
                    entry.isCredit = (usd >= 0)
                    entry.entryType = entry.isCredit ? "credit" : "debit"
                }
            } else if let btc = btcAmount, let price = btcPriceAtTransaction, price > 0 {
                // Fallback: convert BTC to USD if only BTC provided
                let usd = btc * price
                let amountValue = usd.magnitude
                entry.amount = NSDecimalNumber(decimal: amountValue)
                entry.usdAmount = NSDecimalNumber(decimal: amountValue)
                // Income is ALWAYS credit
                if isIncome {
                    entry.isCredit = true
                    entry.entryType = "credit"
                } else {
                    entry.isCredit = (usd >= 0)
                    entry.entryType = entry.isCredit ? "credit" : "debit"
                }
            }
        }
        
        // Store fee amount if provided (for both BTC and USD accounts)
        if let fee = feeAmount {
            entry.feeAmount = NSDecimalNumber(decimal: fee.magnitude)
        }
        
        // Store paycheck reference separately (not in user-visible notes)
        // Since we can't add a relationship without Core Data migration,
        // we'll store the paycheck ID in a way that doesn't show to users
        // We'll use a special format that can be filtered out when displaying
        if let paycheck = paycheck, let paycheckId = paycheck.id {
            // Store paycheck reference in a format that can be filtered out
            // Use a prefix that's unlikely to appear in user notes
            let paycheckRef = "\u{200B}__PAYCHECK_ID__:\(paycheckId.uuidString)\u{200B}"
            let existingNotes = entry.notes ?? ""
            // Only append if not already present
            if !existingNotes.contains("__PAYCHECK_ID__") {
                entry.notes = existingNotes.isEmpty ? paycheckRef : "\(existingNotes)\n\(paycheckRef)"
            }
        }
        
        saveContext()
        if selectedAccount == account {
            refreshLedgerEntries()
        }
        
        // Refresh the account to ensure balance updates are reflected
        context.refresh(account, mergeChanges: true)
    }
    
    func toggleReconciled(for entry: LedgerEntry) {
        entry.isReconciledFlag.toggle()
        saveContext()
        refreshLedgerEntries()
        
        // Refresh the account to ensure balance calculations update
        if let account = entry.account {
            context.refresh(account, mergeChanges: true)
        }
    }
    
    func updateLedgerEntry(_ entry: LedgerEntry,
                           date: Date,
                           title: String,
                           btcAmount: Decimal?,
                           usdAmount: Decimal?,
                           btcPrice: Decimal?,
                           isReconciled: Bool,
                           notes: String?,
                           category: String? = nil,
                           feeAmount: Decimal? = nil) {
        entry.date = date
        entry.title = title
        entry.notes = notes
        entry.category = category
        entry.isReconciledFlag = isReconciled
        
        guard let account = entry.account else {
            saveContext()
            refreshLedgerEntries()
            return
        }
        
        if account.currencyCode == "BTC" {
            // For BTC accounts, handle BTC and USD amounts
            if let btc = btcAmount {
                entry.btcAmount = NSDecimalNumber(decimal: btc.magnitude)
                entry.amount = NSDecimalNumber(decimal: btc.magnitude)
                entry.isCredit = btc >= 0
                entry.entryType = btc >= 0 ? "credit" : "debit"
            }
            if let usd = usdAmount {
                entry.usdAmount = NSDecimalNumber(decimal: usd.magnitude)
            }
            if let price = btcPrice {
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: price)
            }
        } else {
            // For USD accounts, use regular amount
            if let usd = usdAmount {
                entry.amount = NSDecimalNumber(decimal: usd.magnitude)
                entry.usdAmount = NSDecimalNumber(decimal: usd.magnitude)
                entry.isCredit = usd >= 0
                entry.entryType = usd >= 0 ? "credit" : "debit"
            }
        }
        
        // Update fee amount if provided
        if let fee = feeAmount {
            entry.feeAmount = NSDecimalNumber(decimal: fee.magnitude)
        }
        
        saveContext()
        refreshLedgerEntries()
    }
    
    func deleteLedgerEntry(_ entry: LedgerEntry) {
        context.delete(entry)
        saveContext()
        refreshLedgerEntries()
    }
    
    // MARK: - Sample Data for Testing
    /// Adds sample transactions across multiple categories and dates for testing bar charts
    func addSampleDataForTesting(to account: Account) {
        let calendar = Calendar.current
        let now = Date()
        
        // Get current month start
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return }
        
        // Add transactions spread across the month (5 periods: 1-7, 8-14, 15-21, 22-28, 29-31)
        let periods = [
            (startDay: 1, endDay: 7, categories: [
                ("Credit Card", Decimal(800.00)),
                ("Housing", Decimal(400.00)),
                ("Utilities", Decimal(50.00))
            ]),
            (startDay: 8, endDay: 14, categories: [
                ("Credit Card", Decimal(600.00)),
                ("Housing", Decimal(300.00)),
                ("Food & Dining", Decimal(35.19))
            ]),
            (startDay: 15, endDay: 21, categories: [
                ("Credit Card", Decimal(500.00)),
                ("Housing", Decimal(300.00)),
                ("Utilities", Decimal(50.00)),
                ("Fee", Decimal(30.97))
            ]),
            (startDay: 22, endDay: 28, categories: [
                ("Credit Card", Decimal(400.00)),
                ("Housing", Decimal(264.80)),
                ("Utilities", Decimal(48.92))
            ]),
            (startDay: 29, endDay: 31, categories: [
                ("Credit Card", Decimal(109.08))
            ])
        ]
        
        for period in periods {
            // Distribute transactions across the period
            let daysInPeriod = period.endDay - period.startDay + 1
            var dayOffset = 0
            
            for (categoryName, amount) in period.categories {
                guard let transactionDate = calendar.date(byAdding: .day, value: period.startDay - 1 + dayOffset, to: monthStart) else { continue }
                
                addManualEntry(
                    to: account,
                    title: "\(categoryName) Payment",
                    btcAmount: nil,
                    usdAmount: -amount, // Negative for expenses
                    btcPriceAtTransaction: nil,
                    date: transactionDate,
                    notes: "Sample data for testing",
                    isReconciled: true,
                    category: categoryName,
                    paycheck: nil,
                    feeAmount: nil
                )
                
                dayOffset = (dayOffset + 1) % daysInPeriod
            }
        }
        
        saveContext()
        refreshLedgerEntries()
        print("✅ Added sample data for testing bar chart")
    }
    
    func updatePaycheckOccurrenceTransaction(paycheck: Paycheck,
                                            occurrenceDate: Date,
                                            name: String,
                                            amount: Decimal,
                                            account: Account) {
        // Find ledger entries for this paycheck on this specific date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: occurrenceDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date < %@ AND category == %@", 
                                       account, startOfDay as NSDate, endOfDay as NSDate, "Income")
        
        do {
            let entries = try context.fetch(request)
            // Find entries that match the paycheck name (or create new one if none found)
            let matchingEntry = entries.first { entry in
                entry.title == paycheck.name || entry.title == name
            }
            
            if let entry = matchingEntry {
                // Update existing entry
                entry.title = name
                entry.amount = NSDecimalNumber(decimal: amount.magnitude)
                entry.usdAmount = NSDecimalNumber(decimal: amount.magnitude)
                entry.isCredit = true
                entry.entryType = "credit"
            } else {
                // Create new entry for this occurrence
                addManualEntry(to: account,
                              title: name,
                              btcAmount: nil,
                              usdAmount: amount,
                              btcPriceAtTransaction: nil,
                              date: occurrenceDate,
                              notes: paycheck.notes,
                              isReconciled: false,
                              category: "Income")
            }
            
            saveContext()
            refreshLedgerEntries()
        } catch {
            print("Error updating paycheck occurrence transaction: \(error)")
        }
    }
    
    func deletePaycheckOccurrenceTransaction(paycheck: Paycheck, occurrenceDate: Date) {
        guard let account = paycheck.account else { return }
        
        // Find ledger entries for this paycheck on this specific date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: occurrenceDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date < %@ AND category == %@", 
                                       account, startOfDay as NSDate, endOfDay as NSDate, "Income")
        
        do {
            let entries = try context.fetch(request)
            // Find and delete entries that match the paycheck name
            let matchingEntries = entries.filter { entry in
                entry.title == paycheck.name
            }
            
            for entry in matchingEntries {
                context.delete(entry)
            }
            
            saveContext()
            refreshLedgerEntries()
        } catch {
            print("Error deleting paycheck occurrence transaction: \(error)")
        }
    }
    
    func removeLedgerEntries(for bill: Bill) {
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry> else { return }
        for entry in entries {
            context.delete(entry)
        }
        saveContext()
        refreshLedgerEntries()
    }
    
    func entries(on date: Date, account: Account? = nil) -> [LedgerEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        var predicates: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        ]
        if let account {
            predicates.append(NSPredicate(format: "account == %@", account))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: true),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: true)
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching ledger entries for date: \(error)")
            return []
        }
    }
    
    func refreshData() {
        fetchAccounts()
        refreshLedgerEntries()
    }
    
    // MARK: - Recent Transactions (Optimized)
    /// Fetches the most recent transactions across all accounts with efficient Core Data query
    /// - Parameters:
    ///   - limit: Maximum number of transactions to return (default: 5)
    ///   - daysBack: Number of days to look back (default: 30, nil = no limit)
    /// - Returns: Array of ledger entries sorted by date descending (most recent first)
    func recentTransactions(limit: Int = 5, daysBack: Int? = 30) -> [LedgerEntry] {
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        
        // Build predicate for date range if specified
        var predicates: [NSPredicate] = []
        if let daysBack = daysBack {
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date.distantPast
            predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        // Sort by date descending (most recent first), then by createdAt for consistency
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        
        // Limit results for performance
        request.fetchLimit = limit
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching recent transactions: \(error)")
            return []
        }
    }
    
    // MARK: - Category Usage (for sorted/filtered category picker)
    /// Aggregates category usage from all ledger entries: count and last-used date.
    func categoryUsage() -> [String: (count: Int, lastUsed: Date)] {
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "category != nil AND category != %@", "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false)]
        do {
            let entries = try context.fetch(request)
            var usage: [String: (count: Int, lastUsed: Date)] = [:]
            for e in entries {
                guard let cat = e.category, !cat.isEmpty, let d = e.date else { continue }
                if let u = usage[cat] {
                    usage[cat] = (u.count + 1, d > u.lastUsed ? d : u.lastUsed)
                } else {
                    usage[cat] = (1, d)
                }
            }
            return usage
        } catch {
            return [:]
        }
    }
    
    /// Transaction titles matching prefix, for predictive fill. Most recent first.
    func suggestedTitles(prefix: String, account: Account? = nil, limit: Int = 8) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        var preds: [NSPredicate] = [NSPredicate(format: "title BEGINSWITH[cd] %@", trimmed)]
        if let account { preds.append(NSPredicate(format: "account == %@", account)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false),
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        request.fetchLimit = limit * 4
        do {
            let entries = try context.fetch(request)
            var seen = Set<String>()
            var out: [String] = []
            for e in entries {
                guard let t = e.title, !t.isEmpty, seen.insert(t).inserted else { continue }
                out.append(t)
                if out.count >= limit { break }
            }
            return out
        } catch {
            return []
        }
    }
    
    // MARK: - Historical Transaction Lookup
    func findHistoricalTransaction(title: String, account: Account? = nil) -> LedgerEntry? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "title ==[c] %@", trimmedTitle) // Case-insensitive match
        ]
        
        // Optionally filter by account
        if let account {
            predicates.append(NSPredicate(format: "account == %@", account))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerEntry.date, ascending: false), // Most recent first
            NSSortDescriptor(keyPath: \LedgerEntry.createdAt, ascending: false)
        ]
        request.fetchLimit = 1 // Only need the most recent match
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching historical transaction: \(error)")
            return nil
        }
    }
    
    // MARK: - Persistence
    // MARK: - Clear All Data
    func clearAllLedgerEntries() -> (success: Bool, message: String) {
        do {
            // Fetch all ledger entries
            let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
            let allEntries = try context.fetch(request)
            
            // Delete all entries individually (works better with CloudKit)
            for entry in allEntries {
                context.delete(entry)
            }
            
            try context.save()
            refreshLedgerEntries()
            return (true, "All transactions cleared successfully")
        } catch {
            return (false, "Error clearing transactions: \(error.localizedDescription)")
        }
    }
    
    func clearAllAccounts(keepAccounts: Bool = true) -> (success: Bool, message: String) {
        do {
            // Refresh context first
            context.refreshAllObjects()
            
            let accounts = try context.fetch(NSFetchRequest<Account>(entityName: "Account"))
            
            if keepAccounts {
                // Just reset starting balances to 0 and ensure no orphaned relationships
                for account in accounts {
                    account.startingBalance = NSDecimalNumber(decimal: 0)
                    account.updatedAt = Date()
                    
                    // Verify no orphaned ledger entries (should be cleared already, but double-check)
                    if let entries = account.ledgerEntries as? Set<LedgerEntry>, !entries.isEmpty {
                        print("⚠️ Warning: Account \(account.name ?? "Unknown") still has \(entries.count) ledger entries after clear")
                    }
                }
                try context.save()
                
                // Refresh again after save
                context.refreshAllObjects()
                fetchAccounts()
                return (true, "All account balances reset to $0")
            } else {
                // Delete all accounts individually (works better with CloudKit)
                for account in accounts {
                    context.delete(account)
                }
                try context.save()
                
                // Refresh after save
                context.refreshAllObjects()
                fetchAccounts()
                return (true, "All accounts deleted")
            }
        } catch {
            return (false, "Error clearing accounts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Verify Account State (for debugging)
    func verifyAccountState(account: Account) -> String {
        let balance = totalBalance(for: account)
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        let bills = account.bills as? Set<Bill> ?? []
        let unpaidBills = bills.filter { !$0.isPaid }
        
        return """
        Account: \(account.name ?? "Unknown")
        Currency: \(account.currencyCode)
        Starting Balance: \(account.startingBalance?.decimalValue ?? 0)
        Total Balance: \(balance)
        Ledger Entries: \(entries.count)
        Total Bills: \(bills.count)
        Unpaid Bills: \(unpaidBills.count)
        """
    }
    
    func clearAllData(keepAccounts: Bool = true) -> (success: Bool, message: String) {
        var messages: [String] = []
        
        // Refresh context to ensure we have latest state
        context.refreshAllObjects()
        
        // Clear ledger entries
        let ledgerResult = clearAllLedgerEntries()
        if ledgerResult.success {
            messages.append(ledgerResult.message)
        } else {
            return (false, ledgerResult.message)
        }
        
        // Clear/reset accounts
        let accountResult = clearAllAccounts(keepAccounts: keepAccounts)
        if accountResult.success {
            messages.append(accountResult.message)
        } else {
            return (false, accountResult.message)
        }
        
        // Refresh context again after clearing
        context.refreshAllObjects()
        fetchAccounts()
        
        return (true, messages.joined(separator: ". "))
    }
    
    func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Error saving account context: \(error)")
        }
    }
    
    /// Finds a matching transaction for a payment import (checks both reconciled and unreconciled)
    func findMatchingTransaction(account: Account, amount: Decimal, date: Date, title: String) -> LedgerEntry? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        
        // Allow matching within 7 days (in case payment date differs slightly)
        guard let searchStart = calendar.date(byAdding: .day, value: -7, to: startOfDay),
              let searchEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else { return nil }
        
        // Check both reconciled and unreconciled transactions (payments are likely already reconciled)
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "account == %@ AND date >= %@ AND date < %@", 
                                       account, searchStart as NSDate, searchEnd as NSDate)
        
        do {
            let entries = try context.fetch(request)
            
            // Find best match by amount (within $0.01 tolerance) and optionally by title similarity
            let amountTolerance: Decimal = 0.01
            
            // First try exact amount match (prefer reconciled transactions since payments are usually already cleared)
            let sortedEntries = entries.sorted { entry1, entry2 in
                // Prioritize reconciled entries
                if entry1.isReconciledFlag != entry2.isReconciledFlag {
                    return entry1.isReconciledFlag
                }
                // Then by date proximity
                let date1 = abs((entry1.date ?? date).timeIntervalSince(date))
                let date2 = abs((entry2.date ?? date).timeIntervalSince(date))
                return date1 < date2
            }
            
            if let exactMatch = sortedEntries.first(where: { entry in
                guard let entryAmount = entry.usdAmount?.decimalValue else { return false }
                let diff = abs(entryAmount - amount)
                return diff <= amountTolerance
            }) {
                return exactMatch
            }
            
            // If no exact match, try matching by title keywords (for payments like "Payment to Chase")
            let titleLower = title.lowercased()
            let titleWords = Set(titleLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
            
            if let titleMatch = sortedEntries.first(where: { entry in
                guard let entryAmount = entry.usdAmount?.decimalValue else { return false }
                let diff = abs(entryAmount - amount)
                guard diff <= amountTolerance else { return false }
                
                // Check if entry title contains payment-related keywords
                guard let entryTitle = entry.title?.lowercased() else { return false }
                let entryWords = Set(entryTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
                
                // Match if titles share common words or if entry title suggests it's a payment
                let commonWords = titleWords.intersection(entryWords)
                let hasCommonWords = !commonWords.isEmpty
                let isPaymentTitle = entryTitle.contains("payment") || entryTitle.contains("transfer")
                
                return hasCommonWords || isPaymentTitle
            }) {
                return titleMatch
            }
            
            return nil
        } catch {
            print("Error finding matching transaction: \(error)")
            return nil
        }
    }

}
