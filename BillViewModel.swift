//
//  BillViewModel.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import Foundation
import CoreData
import SwiftUI
import UIKit
import UserNotifications

class BillViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    
    private let context: NSManagedObjectContext
    private let notificationManager: NotificationManager
    private var isProcessingAutoPay = false
    private weak var accountViewModel: AccountViewModel?
    private var businessDayCalculator = BusinessDayCalculator()
    private var pendingRecurringBills: Set<String> = [] // Track bills being created to prevent duplicates (key format: "seriesId-dateKey")
    private var billsBeingToggled: Set<NSManagedObjectID> = [] // Track bills currently being toggled to prevent rapid duplicate calls
    private var skipAutoPayUntil: Date? = nil // Skip auto-pay processing until this date (used during import)
    
    init(context: NSManagedObjectContext,
         notificationManager: NotificationManager = NotificationManager(),
         accountViewModel: AccountViewModel? = nil) {
        self.context = context
        self.notificationManager = notificationManager
        self.accountViewModel = accountViewModel
        fetchBills()
        // Clean up any existing duplicates on initialization (delayed to ensure context is ready)
        // Only run once per app session to avoid interfering with user deletions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.removeDuplicateBills()
        }
    }
    
    func attachAccountViewModel(_ accountViewModel: AccountViewModel) {
        self.accountViewModel = accountViewModel
    }
    
    // MARK: - Fetch All Bills for Month (including paid ones)
    func fetchAllBillsForMonth(_ month: Date) -> [Bill] {
        let calendar = Calendar.current
        
        // Get the proper month interval
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return []
        }
        
        // Use start of first day and end of last day of the month
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        
        // Get the last day of the month by getting the first day of next month and subtracting 1 day
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthInterval.start) else {
            return []
        }
        guard let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonthStart) else {
            return []
        }
        // Get end of the last day (23:59:59)
        let monthEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDayOfMonth) ?? lastDayOfMonth
        
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "dueDate >= %@ AND dueDate <= %@",
                                       monthStart as NSDate,
                                       monthEnd as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
        
        do {
            let bills = try context.fetch(request)
            // Debug logging removed - was causing excessive console output during SwiftUI view updates
            // Uncomment below for debugging if needed:
            // #if DEBUG
            // let dateFormatter = DateFormatter()
            // dateFormatter.dateFormat = "MMM d, yyyy"
            // print("📊 Month: \(dateFormatter.string(from: month)), Found \(bills.count) bills")
            // #endif
            return bills
        } catch {
            print("Error fetching all bills for month: \(error)")
            return []
        }
    }
    
    // MARK: - Fetch Bills
    func fetchBills(skipAutoPay: Bool = false) {
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
        
        do {
            let fetched = try context.fetch(request)
            let visible = filterVisibleBills(from: fetched)
            bills = visible
            
            // Skip auto-pay if explicitly requested, or if we're in a skip window (e.g., during import)
            let shouldSkipAutoPay = skipAutoPay || (skipAutoPayUntil != nil && Date() < skipAutoPayUntil!)
            
            if !isProcessingAutoPay && !shouldSkipAutoPay {
                processAutoPayBills(sourceBills: fetched)
            }
            updateAppBadge()
        } catch {
            print("Error fetching bills: \(error)")
        }
    }
    
    // MARK: - Skip Auto-Pay Processing (for import)
    func skipAutoPayProcessing(for duration: TimeInterval = 5.0) {
        skipAutoPayUntil = Date().addingTimeInterval(duration)
    }
    
    // MARK: - Check for Existing Bill
    func billExists(name: String, dueDate: Date, amount: Decimal) -> Bool {
        // Refresh context to see any recently saved bills
        context.refreshAllObjects()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: dueDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        
        // Also check pending changes in context (inserted objects that haven't been saved yet)
        let insertedObjects = context.insertedObjects
        let hasPendingDuplicate = insertedObjects.contains { object in
            guard let pendingBill = object as? Bill,
                  let pendingName = pendingBill.name,
                  let pendingDue = pendingBill.dueDate,
                  let pendingAmount = pendingBill.amount?.decimalValue else { return false }
            // Use comparison with small tolerance for decimal amounts
            let diff = pendingAmount - amount
            let amountDiff = abs(NSDecimalNumber(decimal: diff).doubleValue)
            return pendingName == name &&
                   calendar.isDate(pendingDue, inSameDayAs: dueDate) &&
                   amountDiff < 0.01 // Allow small difference for floating point precision
        }
        if hasPendingDuplicate {
            print("⚠️ Found pending duplicate: \(name) on \(dueDate)")
            return true
        }
        
        // Use a more flexible amount comparison to handle precision issues
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        // First get bills matching name and date
        request.predicate = NSPredicate(format: "name == %@ AND dueDate >= %@ AND dueDate < %@", 
                                       name, startOfDay as NSDate, endOfDay as NSDate)
        
        do {
            let existingBills = try context.fetch(request)
            // Filter by amount with tolerance for precision
            let matchingBills = existingBills.filter { bill in
                guard let billAmount = bill.amount?.decimalValue else { return false }
                let diff = billAmount - amount
                let amountDiff = abs(NSDecimalNumber(decimal: diff).doubleValue)
                return amountDiff < 0.01 // Allow small difference for floating point precision
            }
            
            if !matchingBills.isEmpty {
                print("⚠️ Found existing duplicate: \(name) on \(dueDate) - \(matchingBills.count) bill(s)")
            }
            return !matchingBills.isEmpty
        } catch {
            print("Error checking for existing bill: \(error)")
            return false
        }
    }
    
    // MARK: - Add Bill
    func addBill(name: String,
                 amount: Decimal,
                 dueDate: Date,
                 notes: String = "",
                 recurrenceType: String = "none",
                 recurrenceInterval: Int = 0,
                 autoPay: Bool = false,
                 paymentCard: String? = nil,
                 account: Account? = nil,
                 category: String? = nil,
                 skipDuplicateCheck: Bool = false,
                 skipSave: Bool = false) -> Bill? {
        // Check for duplicates unless explicitly skipped
        if !skipDuplicateCheck && billExists(name: name, dueDate: dueDate, amount: amount) {
            print("⚠️ Skipping duplicate bill: \(name) on \(dueDate)")
            return nil
        }
        
        let newBill = Bill(context: context)
        newBill.id = UUID()
        newBill.name = name
        newBill.amount = NSDecimalNumber(decimal: amount)
        newBill.dueDate = dueDate
        newBill.notes = notes
        newBill.recurrenceType = recurrenceType
        newBill.recurrenceInterval = recurrenceType == "none" ? 0 : Int16(max(recurrenceInterval, 1))
        newBill.autoPay = autoPay
        newBill.isPaid = false
        newBill.createdAt = Date()
        newBill.updatedAt = Date()
        newBill.seriesId = recurrenceType == "none" ? nil : UUID()
        newBill.paymentCard = paymentCard
        newBill.account = account
        newBill.category = category
        
        notificationManager.scheduleNotification(for: newBill)
        
        // Only save if not skipping (for batch imports)
        if !skipSave {
            // If this bill has auto-pay enabled, skip auto-pay processing for a few seconds
            // to prevent it from being immediately processed and creating duplicates
            if autoPay {
                skipAutoPayProcessing(for: 3.0)
                print("⏸️ Skipping auto-pay processing for newly created bill: \(name)")
            }
            
            do {
                try context.save()
                // Manually refresh bills without triggering auto-pay processing
                // This prevents processAutoPayBills() from running and creating duplicates
                let request = NSFetchRequest<Bill>(entityName: "Bill")
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
                let fetched = try context.fetch(request)
                let visible = filterVisibleBills(from: fetched)
                bills = visible
                accountViewModel?.refreshData()
                updateAppBadge()
            } catch {
                print("Error saving new bill: \(error)")
            }
        }
        return newBill
    }
    
    // MARK: - Update Bill
    func updateBill(_ bill: Bill,
                    name: String,
                    amount: Decimal,
                    dueDate: Date,
                    notes: String,
                    recurrenceType: String,
                    recurrenceInterval: Int,
                    autoPay: Bool,
                    paymentCard: String?,
                    account: Account?,
                    applyToSeries: Bool = false,
                    category: String? = nil) {
        let originalDueDate = bill.dueDate
        let previousRecurrenceType = bill.recurrenceType ?? "none"
        let previousAccount = bill.account
        
        bill.name = name
        bill.amount = NSDecimalNumber(decimal: amount)
        bill.dueDate = dueDate
        bill.notes = notes
        bill.recurrenceType = recurrenceType
        bill.recurrenceInterval = recurrenceType == "none" ? 0 : Int16(max(recurrenceInterval, 1))
        bill.autoPay = autoPay
        bill.updatedAt = Date()
        bill.seriesId = recurrenceType == "none" ? nil : (bill.seriesId ?? UUID())
        bill.paymentCard = paymentCard
        bill.account = account
        bill.category = category
        
        // If bill is now credit card only (has paymentCard but no account), remove any ledger entries
        // Credit card payments don't affect account balances
        if let paymentCard = paymentCard, !paymentCard.isEmpty, account == nil {
            accountViewModel?.removeLedgerEntries(for: bill)
        }
        
        if previousAccount != account {
            accountViewModel?.removeLedgerEntries(for: bill)
            if bill.isPaid,
               let amountDecimal = bill.amount?.decimalValue {
                let paidDate = bill.paidDate ?? Date()
                accountViewModel?.recordLedgerEntry(for: bill,
                                                    amount: amountDecimal,
                                                    date: paidDate,
                                                    isCredit: false,
                                                    title: bill.name,
                                                    notes: bill.notes)
            }
        }
        
        notificationManager.cancelNotification(for: bill)
        if !bill.isPaid {
            notificationManager.scheduleNotification(for: bill)
        }
        
        if applyToSeries {
            applyUpdateToFutureBills(from: bill,
                                     amount: amount,
                                     notes: notes,
                                     autoPay: autoPay,
                                     recurrenceType: recurrenceType,
                                     recurrenceInterval: recurrenceInterval,
                                     originalDueDate: originalDueDate,
                                     previousRecurrenceType: previousRecurrenceType,
                                     paymentCard: paymentCard,
                                     account: account,
                                     category: category)
        } else if recurrenceType == "none" && previousRecurrenceType != "none" {
            removeFutureBills(for: bill)
        }
        
        saveContext()
    }
    
    // MARK: - Delete Bill
    func deleteBill(_ bill: Bill) {
        // Ensure we're deleting the specific bill object, not a duplicate
        // Refresh the bill from context to ensure we have the correct managed object
        guard let objectID = bill.objectID.isTemporaryID ? nil : bill.objectID else {
            // If temporary ID, just delete directly
            notificationManager.cancelNotification(for: bill)
            accountViewModel?.removeLedgerEntries(for: bill)
            context.delete(bill)
            saveContext()
            return
        }
        
        // Get the bill from context to ensure we're deleting the right one
        guard let billToDelete = try? context.existingObject(with: objectID) as? Bill else {
            print("⚠️ Could not find bill to delete with objectID: \(objectID)")
            return
        }
        
        notificationManager.cancelNotification(for: billToDelete)
        accountViewModel?.removeLedgerEntries(for: billToDelete)
        context.delete(billToDelete)
        saveContext()
    }
    
    // MARK: - Toggle Paid Status
    func togglePaidStatus(for bill: Bill, viaAutoPay: Bool = false, satsAmount: Decimal? = nil) {
        // Prevent multiple rapid calls that could create duplicates
        let objectID = bill.objectID
        if billsBeingToggled.contains(objectID) {
            print("⚠️ Bill \(bill.name ?? "Unknown") is already being toggled, ignoring duplicate call")
            return
        }
        
        billsBeingToggled.insert(objectID)
        
        // Prevent multiple rapid calls that could create duplicates
        let wasPaid = bill.isPaid
        bill.isPaid.toggle()
        
        if bill.isPaid && !wasPaid {
            // Marking as paid
            bill.paidDate = Date()
            if !viaAutoPay {
                notificationManager.cancelNotification(for: bill)
            }
            
            // Save first to ensure bill state is persisted
            do {
                try context.save()
            } catch {
                print("❌ Error saving bill before generating next: \(error)")
            }
            
            // Generate next recurring bill AFTER saving
            // Only generate if this bill was actually marked as paid (not if it was already paid)
            if let recurrenceType = bill.recurrenceType, recurrenceType != "none" {
                // Small delay to ensure the current bill's state is fully saved first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.generateNextRecurringBill(from: bill)
                }
            }
            
            // Only create ledger entry for non-zero bills
            if let amountDecimal = bill.amount?.decimalValue, amountDecimal > 0 {
                let paidDate = bill.paidDate ?? Date()
                
                // Calculate total amount including digital wallet fees (if applicable)
                var totalAmount = amountDecimal
                var transactionNotes = bill.notes
                
                if let account = bill.account {
                    // Check if this is a digital wallet account
                    let accountType = (account.type ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                    let isDigitalWallet = accountType == "digital wallet"
                    
                    // Only calculate and add fees for digital wallet accounts
                    if isDigitalWallet && account.feePercentageDecimal > 0 {
                        // Calculate fee: bill_amount * (feePercentage / 100)
                        let fee = amountDecimal * (account.feePercentageDecimal / 100)
                        totalAmount = amountDecimal + fee
                        
                        // Add fee note to transaction notes (ONLY for digital wallet accounts)
                        let feeDouble = (fee as NSDecimalNumber).doubleValue
                        let feePercentageDouble = (account.feePercentageDecimal as NSDecimalNumber).doubleValue
                        let feeNote = "Digital Wallet Fee: \(String(format: "%.2f", feeDouble)) USD (\(String(format: "%.3f", feePercentageDouble))%)"
                        transactionNotes = bill.notes?.isEmpty == false ? "\(bill.notes ?? "")\n\(feeNote)" : feeNote
                    }
                }
                
                // Create transaction as PENDING (unreconciled) so user can check it off when it clears
                // This keeps it simple: bill is paid, transaction is pending until cleared
                let entry = accountViewModel?.recordLedgerEntry(for: bill,
                                                                amount: totalAmount,
                                                                date: paidDate,
                                                                isCredit: false,
                                                                title: bill.name,
                                                                notes: transactionNotes,
                                                                satsAmount: satsAmount)
                // Mark transaction as unreconciled (pending) so it shows up unchecked in account
                entry?.isReconciledFlag = false
            }
            // For $0 bills, just mark as paid without creating ledger entry
        } else if !bill.isPaid && wasPaid {
            // Unmarking as paid
            bill.paidDate = nil
            notificationManager.cancelNotification(for: bill)
            if let recurrenceType = bill.recurrenceType, recurrenceType != "none" {
                removeUpcomingBill(for: bill)
            }
            notificationManager.scheduleNotification(for: bill)
            accountViewModel?.removeLedgerEntries(for: bill)
        }
        
        // Save without triggering fetchBills() to prevent recursive calls and duplicate creation
        do {
            try context.save()
            // Manually update bills list without triggering auto-pay
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
            let fetched = try context.fetch(request)
            let visible = filterVisibleBills(from: fetched)
            bills = visible
            accountViewModel?.refreshData()
            updateAppBadge()
        } catch {
            print("Error saving bill toggle: \(error)")
        }
        
        // Remove from tracking after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.billsBeingToggled.remove(objectID)
        }
    }
    
    // MARK: - Add Pending Transaction
    func addPendingTransaction(for bill: Bill) {
        // Create a ledger entry without marking the bill as paid
        // This allows projecting future bills into account balance
        
        // Check if bill already has an unreconciled pending transaction
        if let entries = bill.ledgerEntries as? Set<LedgerEntry>,
           entries.contains(where: { !$0.isReconciledFlag }) {
            // Bill already has a pending transaction, don't create another one
            return
        }
        
        guard let amountDecimal = bill.amount?.decimalValue else { return }
        
        // Skip creating pending transaction for $0 bills
        if amountDecimal == 0 {
            return
        }
        
        // Use due date or current date for the transaction
        let transactionDate = bill.dueDate ?? Date()
        
        // Calculate total amount including digital wallet fees
        // IMPORTANT: Only apply fees for digital wallet accounts with a fee percentage set
        var totalAmount = amountDecimal
        var transactionNotes = bill.notes
        
        if let account = bill.account {
            // Check if this is a digital wallet account (using same logic as ReportsViewModel)
            let accountType = (account.type ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let isDigitalWallet = accountType == "digital wallet"
            
            // Only calculate and add fees for digital wallet accounts
            if isDigitalWallet && account.feePercentageDecimal > 0 {
                // Calculate fee: bill_amount * (feePercentage / 100)
                let fee = amountDecimal * (account.feePercentageDecimal / 100)
                totalAmount = amountDecimal + fee
                
                // Add fee note to transaction notes (ONLY for digital wallet accounts)
                // Convert Decimal to Double for String formatting
                let feeDouble = (fee as NSDecimalNumber).doubleValue
                let feePercentageDouble = (account.feePercentageDecimal as NSDecimalNumber).doubleValue
                let feeNote = "Digital Wallet Fee: \(String(format: "%.2f", feeDouble)) USD (\(String(format: "%.3f", feePercentageDouble))%)"
                transactionNotes = bill.notes?.isEmpty == false ? "\(bill.notes ?? "")\n\(feeNote)" : feeNote
            }
            // For non-digital-wallet accounts, totalAmount remains as amountDecimal (no fee added)
            
            // Store USD amount - include fee in total if digital wallet, otherwise just bill amount
            // No automatic BTC calculation - user will enter sats when marking as paid or reconciling
            accountViewModel?.recordLedgerEntry(for: bill,
                                                amount: totalAmount,
                                                date: transactionDate,
                                                isCredit: false,
                                                title: bill.name,
                                                notes: transactionNotes,
                                                satsAmount: nil) // No auto-calculation
        } else {
            // No account assigned - just use bill amount (no fees ever applied)
            accountViewModel?.recordLedgerEntry(for: bill,
                                                amount: amountDecimal,
                                                date: transactionDate,
                                                isCredit: false,
                                                title: bill.name,
                                                notes: bill.notes,
                                                satsAmount: nil) // No auto-calculation
        }
        
        saveContext()
    }
    
    // MARK: - Add Pending Transaction for Auto-Pay
    private func addPendingTransactionForAutoPay(for bill: Bill) {
        // Create a pending transaction for auto-pay bills
        // This creates a ledger entry without marking the bill as paid
        
        // Check if bill already has an unreconciled pending transaction
        if let entries = bill.ledgerEntries as? Set<LedgerEntry>,
           entries.contains(where: { !$0.isReconciledFlag }) {
            // Bill already has a pending transaction, don't create another one
            print("⏸️ Bill \(bill.name ?? "Unknown") already has a pending transaction")
            return
        }
        
        guard let amountDecimal = bill.amount?.decimalValue else { return }
        
        // Use due date or current date for the transaction
        let transactionDate = bill.dueDate ?? Date()
        
        // Create pending transaction (isReconciledFlag defaults to false)
        accountViewModel?.recordLedgerEntry(for: bill,
                                            amount: amountDecimal,
                                            date: transactionDate,
                                            isCredit: false,
                                            title: bill.name,
                                            notes: bill.notes,
                                            satsAmount: nil)
        
        // Save without triggering fetchBills() to prevent recursive calls
        do {
            try context.save()
            // Manually update bills list without triggering auto-pay
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
            let fetched = try context.fetch(request)
            let visible = filterVisibleBills(from: fetched)
            bills = visible
            accountViewModel?.refreshData()
            updateAppBadge()
            print("✅ Created pending transaction for auto-pay bill: \(bill.name ?? "Unknown")")
        } catch {
            print("❌ Error saving pending transaction: \(error)")
        }
    }
    
    private func filterVisibleBills(from bills: [Bill]) -> [Bill] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date.distantPast
        var visible: [Bill] = []
        var seenSeries: Set<UUID> = []
        
        let sortedBills = bills.sorted { first, second in
            let firstDate = first.dueDate ?? Date.distantFuture
            let secondDate = second.dueDate ?? Date.distantFuture
            return firstDate < secondDate
        }
        
        for bill in sortedBills {
            if bill.isPaid, let paidDate = bill.paidDate, paidDate < cutoff {
                continue
            }
            
            if let seriesId = bill.seriesId, !bill.isPaid {
                if seenSeries.contains(seriesId) {
                    continue
                }
                seenSeries.insert(seriesId)
            }
            
            visible.append(bill)
        }
        
        return visible
    }
    
    private func generateNextRecurringBill(from bill: Bill) {
        guard let recurrenceType = bill.recurrenceType, recurrenceType != "none",
              let dueDate = bill.dueDate else { return }
        
        if bill.seriesId == nil {
            bill.seriesId = UUID()
        }
        guard let seriesId = bill.seriesId else { return }
        
        let nextDate = getNextRecurrenceDate(from: dueDate, type: recurrenceType, interval: Int(max(bill.recurrenceInterval, 1)))
        let calendar = Calendar.current
        
        // Create a unique identifier for this recurring bill instance
        let nextDateKey = calendar.startOfDay(for: nextDate).timeIntervalSince1970
        let pendingKey = "\(seriesId.uuidString)-\(nextDateKey)"
        
        // Check if we're already creating this bill (prevent duplicate calls)
        if pendingRecurringBills.contains(pendingKey) {
            print("⚠️ Duplicate prevention: Already creating bill for series \(seriesId.uuidString) on \(nextDate)")
            return
        }
        
        // Check database for existing bills - use name, date, and amount for more comprehensive duplicate detection
        do {
            // First, refresh the context to see any recently saved bills
            context.refreshAllObjects()
            
            // Check by seriesId first (for recurring bills)
            let seriesRequest = NSFetchRequest<Bill>(entityName: "Bill")
            seriesRequest.predicate = NSPredicate(format: "seriesId == %@", seriesId as CVarArg)
            let seriesBills = try context.fetch(seriesRequest)
            let alreadyExistsInSeries = seriesBills.contains { candidate in
                guard candidate != bill, let candidateDue = candidate.dueDate else { return false }
                return calendar.isDate(candidateDue, inSameDayAs: nextDate)
            }
            if alreadyExistsInSeries {
                print("⚠️ Duplicate prevention: Bill already exists in series \(seriesId.uuidString) on \(nextDate)")
                return
            }
            
            // Also check by name, date, and amount (catches duplicates even without seriesId)
            guard let billName = bill.name, let billAmount = bill.amount?.decimalValue else { return }
            let startOfNextDate = calendar.startOfDay(for: nextDate)
            guard let endOfNextDate = calendar.date(byAdding: .day, value: 1, to: startOfNextDate) else { return }
            
            let nameDateRequest = NSFetchRequest<Bill>(entityName: "Bill")
            nameDateRequest.predicate = NSPredicate(format: "name == %@ AND dueDate >= %@ AND dueDate < %@",
                                                    billName, startOfNextDate as NSDate, endOfNextDate as NSDate)
            let nameDateBills = try context.fetch(nameDateRequest)
            let matchingBills = nameDateBills.filter { candidate in
                guard candidate != bill, let candidateAmount = candidate.amount?.decimalValue else { return false }
                // Check amount with tolerance for precision
                let diff = candidateAmount - billAmount
                let amountDiff = abs(NSDecimalNumber(decimal: diff).doubleValue)
                return amountDiff < 0.01
            }
            if !matchingBills.isEmpty {
                print("⚠️ Duplicate prevention: Bill with same name, date, and amount already exists: \(billName) on \(nextDate)")
                return
            }
            
            // Also check pending changes in context (inserted objects)
            let insertedObjects = context.insertedObjects
            let hasPendingDuplicate = insertedObjects.contains { object in
                guard let pendingBill = object as? Bill,
                      pendingBill != bill,
                      let pendingName = pendingBill.name,
                      let pendingDue = pendingBill.dueDate,
                      let pendingAmount = pendingBill.amount?.decimalValue else { return false }
                
                // Check if it matches by seriesId and date, or by name/date/amount
                let matchesBySeries = pendingBill.seriesId == seriesId && calendar.isDate(pendingDue, inSameDayAs: nextDate)
                let matchesByNameDateAmount = pendingName == billName &&
                                            calendar.isDate(pendingDue, inSameDayAs: nextDate) &&
                                            abs(NSDecimalNumber(decimal: pendingAmount - billAmount).doubleValue) < 0.01
                
                return matchesBySeries || matchesByNameDateAmount
            }
            if hasPendingDuplicate {
                print("⚠️ Duplicate prevention: Pending bill already being created for \(billName) on \(nextDate)")
                return
            }
        } catch {
            print("❌ Error checking for duplicates: \(error)")
            return
        }
        
        // Mark this bill as being created BEFORE creating it
        pendingRecurringBills.insert(pendingKey)
        
        let nextBill = Bill(context: context)
        nextBill.id = UUID()
        nextBill.name = bill.name
        nextBill.amount = bill.amount
        nextBill.dueDate = nextDate
        nextBill.notes = bill.notes
        nextBill.recurrenceType = bill.recurrenceType
        nextBill.recurrenceInterval = bill.recurrenceInterval
        nextBill.autoPay = bill.autoPay
        nextBill.isPaid = false
        nextBill.seriesId = seriesId
        nextBill.createdAt = Date()
        nextBill.updatedAt = Date()
        nextBill.paymentCard = bill.paymentCard
        nextBill.account = bill.account
        nextBill.category = bill.category
        
        notificationManager.scheduleNotification(for: nextBill)
        
        // Save immediately to prevent duplicates from multiple calls
        do {
            try context.save()
            print("✅ Created next recurring bill: \(bill.name ?? "Unknown") for \(nextDate)")
            // Remove from pending set after successful save
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pendingRecurringBills.remove(pendingKey)
            }
        } catch {
            print("❌ Error saving next recurring bill: \(error)")
            // Remove from pending set even on error to allow retry
            pendingRecurringBills.remove(pendingKey)
        }
    }
    
    private func removeUpcomingBill(for bill: Bill) {
        guard let recurrenceType = bill.recurrenceType, recurrenceType != "none",
              let seriesId = bill.seriesId,
              let dueDate = bill.dueDate else { return }
        
        let nextDate = getNextRecurrenceDate(from: dueDate, type: recurrenceType, interval: Int(max(bill.recurrenceInterval, 1)))
        let calendar = Calendar.current
        
        do {
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            request.predicate = NSPredicate(format: "seriesId == %@", seriesId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
            let seriesBills = try context.fetch(request)
            if let upcoming = seriesBills.first(where: { candidate in
                guard candidate != bill, let candidateDue = candidate.dueDate else { return false }
                return !candidate.isPaid && calendar.isDate(candidateDue, inSameDayAs: nextDate)
            }) {
                notificationManager.cancelNotification(for: upcoming)
                context.delete(upcoming)
            }
        } catch {
            print("Error removing upcoming bill: \(error)")
        }
    }
    
    private func applyUpdateToFutureBills(from bill: Bill,
                                          amount: Decimal,
                                          notes: String,
                                          autoPay: Bool,
                                          recurrenceType: String,
                                          recurrenceInterval: Int,
                                          originalDueDate: Date?,
                                          previousRecurrenceType: String,
                                          paymentCard: String?,
                                          account: Account?,
                                          category: String?) {
        guard let seriesId = bill.seriesId else { return }
        
        do {
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            request.predicate = NSPredicate(format: "seriesId == %@", seriesId as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
            let seriesBills = try context.fetch(request)
            let futureBills = seriesBills.filter { $0 != bill }
            
            if recurrenceType == "none" {
                for futureBill in futureBills {
                    notificationManager.cancelNotification(for: futureBill)
                    context.delete(futureBill)
                }
                return
            }
            
            for futureBill in futureBills {
                futureBill.name = bill.name
                futureBill.amount = NSDecimalNumber(decimal: amount)
                futureBill.notes = notes
                futureBill.autoPay = autoPay
                futureBill.recurrenceType = recurrenceType
                futureBill.recurrenceInterval = Int16(max(recurrenceInterval, 1))
                futureBill.updatedAt = Date()
                futureBill.account = account
                futureBill.paymentCard = paymentCard
                futureBill.category = category
                
                if let originalDueDate,
                   let newBaseDate = bill.dueDate,
                   let futureDue = futureBill.dueDate {
                    let interval = futureDue.timeIntervalSince(originalDueDate)
                    futureBill.dueDate = newBaseDate.addingTimeInterval(interval)
                }
                
                notificationManager.cancelNotification(for: futureBill)
                if !futureBill.isPaid {
                    notificationManager.scheduleNotification(for: futureBill)
                }
            }
        } catch {
            print("Error updating future bills: \(error)")
        }
    }
    
    private func removeFutureBills(for bill: Bill) {
        guard let seriesId = bill.seriesId else { return }
        do {
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            request.predicate = NSPredicate(format: "seriesId == %@", seriesId as CVarArg)
            let seriesBills = try context.fetch(request)
            for futureBill in seriesBills where futureBill != bill {
                notificationManager.cancelNotification(for: futureBill)
                context.delete(futureBill)
            }
        } catch {
            print("Error removing future bills: \(error)")
        }
    }
    
    private func getNextRecurrenceDate(from date: Date, type: String, interval: Int) -> Date {
        let calendar = Calendar.current
        let actualInterval = max(interval, 1)
        
        switch type {
        case "daily":
            return calendar.date(byAdding: .day, value: actualInterval, to: date) ?? date
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: actualInterval, to: date) ?? date
        case "biweekly":
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case "monthly":
            return calendar.date(byAdding: .month, value: actualInterval, to: date) ?? date
        case "bimonthly":
            return calendar.date(byAdding: .month, value: 2, to: date) ?? date
        case "quarterly":
            return calendar.date(byAdding: .month, value: 3 * actualInterval, to: date) ?? date
        case "semiannually":
            return calendar.date(byAdding: .month, value: 6, to: date) ?? date
        case "yearly":
            return calendar.date(byAdding: .year, value: actualInterval, to: date) ?? date
        default:
            return date
        }
    }
    
    // MARK: - Delete Recurring Series
    func deleteRecurringBillAndFuture(_ bill: Bill) {
        guard let seriesId = bill.seriesId else {
            deleteBill(bill)
            return
        }
        
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "seriesId == %@", seriesId as CVarArg)
        
        do {
            let seriesBills = try context.fetch(request)
            for futureBill in seriesBills {
                notificationManager.cancelNotification(for: futureBill)
                context.delete(futureBill)
            }
            saveContext()
        } catch {
            print("Error deleting recurring bills: \(error)")
        }
    }
    
    // MARK: - Remove Duplicate Bills
    func removeDuplicateBills() {
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
        
        do {
            let allBills = try context.fetch(request)
            let calendar = Calendar.current
            var seenBills: [String: [Bill]] = [:]
            
            // Group bills by name, due date, and amount (more comprehensive duplicate detection)
            for bill in allBills {
                guard let name = bill.name,
                      let dueDate = bill.dueDate,
                      let amount = bill.amount?.decimalValue else { continue }
                
                let dateKey = calendar.startOfDay(for: dueDate).timeIntervalSince1970
                let amountKey = String(describing: amount)
                
                // Create key from name, date, and amount (catches duplicates even without seriesId)
                let key = "\(name)-\(dateKey)-\(amountKey)"
                
                if seenBills[key] == nil {
                    seenBills[key] = []
                }
                seenBills[key]?.append(bill)
            }
            
            // Remove duplicates, keeping the oldest one
            var removedCount = 0
            for (_, bills) in seenBills where bills.count > 1 {
                // Sort by creation date, keep the oldest
                let sortedBills = bills.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                
                // Delete all except the first (oldest) one
                for bill in sortedBills.dropFirst() {
                    print("🗑️ Removing duplicate bill: \(bill.name ?? "Unknown") - \(bill.dueDate?.formatted() ?? "No date")")
                    notificationManager.cancelNotification(for: bill)
                    context.delete(bill)
                    removedCount += 1
                }
            }
            
            if removedCount > 0 {
                do {
                    try context.save()
                    print("✅ Removed \(removedCount) duplicate bills")
                    fetchBills() // Refresh the list
                } catch {
                    print("❌ Error saving after removing duplicates: \(error)")
                }
            } else {
                print("✅ No duplicate bills found")
            }
        } catch {
            print("❌ Error removing duplicate bills: \(error)")
        }
    }
    
    // MARK: - Clear All Data
    func clearAllBills() -> (success: Bool, message: String) {
        do {
            // Fetch all bills
            let request = NSFetchRequest<Bill>(entityName: "Bill")
            let allBills = try context.fetch(request)
            
            // Cancel all notifications first
            for bill in allBills {
                notificationManager.cancelNotification(for: bill)
            }
            
            // Delete all bills individually (works better with CloudKit)
            for bill in allBills {
                context.delete(bill)
            }
            
            // Save context
            try context.save()
            fetchBills()
            
            return (true, "All bills cleared successfully")
        } catch {
            return (false, "Error clearing bills: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Comprehensive Cleanup (for user-initiated cleanup)
    func performComprehensiveCleanup() -> (duplicatesRemoved: Int, message: String) {
        var totalRemoved = 0
        
        // Refresh context to see all current bills
        context.refreshAllObjects()
        
        // Remove duplicates using improved detection
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bill.dueDate, ascending: true)]
        
        do {
            let allBills = try context.fetch(request)
            let calendar = Calendar.current
            var seenBills: [String: [Bill]] = [:]
            
            print("🔍 Checking \(allBills.count) bills for duplicates...")
            
            // Group bills by name, due date, and amount (more comprehensive)
            for bill in allBills {
                guard let name = bill.name,
                      let dueDate = bill.dueDate,
                      let amount = bill.amount?.decimalValue else { continue }
                
                let dateKey = calendar.startOfDay(for: dueDate).timeIntervalSince1970
                // Use a normalized amount string to handle precision issues
                let amountKey = NSDecimalNumber(decimal: amount).stringValue
                let key = "\(name)-\(dateKey)-\(amountKey)"
                
                if seenBills[key] == nil {
                    seenBills[key] = []
                }
                seenBills[key]?.append(bill)
            }
            
            // Remove duplicates, keeping the oldest one
            for (_, bills) in seenBills where bills.count > 1 {
                print("⚠️ Found \(bills.count) duplicate bills for: \(bills.first?.name ?? "Unknown")")
                let sortedBills = bills.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                
                for bill in sortedBills.dropFirst() {
                    print("🗑️ Removing duplicate: \(bill.name ?? "Unknown") - \(bill.dueDate?.formatted() ?? "No date")")
                    notificationManager.cancelNotification(for: bill)
                    context.delete(bill)
                    totalRemoved += 1
                }
            }
            
            if totalRemoved > 0 {
                try context.save()
                print("✅ Cleanup complete: Removed \(totalRemoved) duplicate bills")
                fetchBills()
            } else {
                print("✅ No duplicates found in \(allBills.count) bills")
            }
            
            return (totalRemoved, totalRemoved > 0 ? "Removed \(totalRemoved) duplicate bills" : "No duplicates found")
        } catch {
            print("❌ Error during cleanup: \(error)")
            return (0, "Error during cleanup: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    private func processAutoPayBills(sourceBills: [Bill]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = Date()
        
        let autoPayBills: [Bill] = sourceBills.compactMap { bill in
            guard bill.autoPay, !bill.isPaid else { return nil }
            
            // Skip bills that were just created (within last 5 seconds) to prevent immediate processing
            // This prevents newly created bills from being immediately marked as paid and creating duplicates
            if let createdAt = bill.createdAt, now.timeIntervalSince(createdAt) < 5.0 {
                print("⏸️ Skipping auto-pay for newly created bill: \(bill.name ?? "Bill") (created \(String(format: "%.1f", now.timeIntervalSince(createdAt)))s ago)")
                return nil
            }
            
            guard bill.account != nil else {
                print("Skipping auto-pay for \(bill.name ?? "Bill") – no debt account linked.")
                return nil
            }
            guard let processingDate = businessDayCalculator.processingDate(for: bill, businessDaysBefore: 3) else {
                return nil
            }
            return calendar.startOfDay(for: processingDate) <= today ? bill : nil
        }
        
        guard !autoPayBills.isEmpty else { return }
        
        isProcessingAutoPay = true
        defer { isProcessingAutoPay = false }
        
        for bill in autoPayBills {
            notificationManager.cancelNotification(for: bill)
            notificationManager.deliverAutoPayNotification(for: bill)
            
            // Create a pending transaction instead of marking as paid immediately
            // This allows the user to reconcile it later when the payment actually clears
            addPendingTransactionForAutoPay(for: bill)
        }
    }
    
    func isRunningInSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private func saveContext() {
        do {
            try context.save()
            // Don't call fetchBills() here - it can trigger processAutoPayBills() which might create duplicates
            // Instead, let the caller decide when to refresh
            accountViewModel?.refreshData()
            updateAppBadge()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    // Separate method for saving and refreshing (use when you need to refresh after save)
    private func saveContextAndRefresh() {
        do {
            try context.save()
            fetchBills() // Refresh the list
            accountViewModel?.refreshData()
            updateAppBadge()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    // MARK: - Update App Badge
    func updateAppBadge() {
        let calendar = Calendar.current
        let now = Date()
        
        // Count unpaid bills that are due today or overdue
        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "isPaid == NO")
        
        do {
            let unpaidBills = try context.fetch(request)
            let dueOrOverdueCount = unpaidBills.filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                let dueStart = calendar.startOfDay(for: dueDate)
                let todayStart = calendar.startOfDay(for: now)
                return dueStart <= todayStart
            }.count
            
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().setBadgeCount(dueOrOverdueCount) { error in
                    if let error = error {
                        print("Error setting badge count: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("Error updating badge: \(error)")
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().setBadgeCount(0) { error in
                    if let error = error {
                        print("Error resetting badge count: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

// MARK: - Business Day Calculator
private struct BusinessDayCalculator {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()
    
    private var holidaysCache: [Int: Set<Date>] = [:]
    private let lock = NSLock()
    
    mutating func processingDate(for bill: Bill, businessDaysBefore days: Int) -> Date? {
        guard let dueDate = bill.dueDate else { return nil }
        let dueStart = calendar.startOfDay(for: dueDate)
        return subtractBusinessDays(from: dueStart, count: days)
    }
    
    mutating func subtractBusinessDays(from date: Date, count: Int) -> Date {
        guard count > 0 else { return date }
        var remaining = count
        var candidate = date
        
        while remaining > 0 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: candidate) else {
                break
            }
            candidate = previous
            if isBusinessDay(candidate) {
                remaining -= 1
            }
        }
        
        return candidate
    }
    
    mutating func isBusinessDay(_ date: Date) -> Bool {
        if calendar.isDateInWeekend(date) { return false }
        return !isHoliday(date)
    }
    
    private mutating func isHoliday(_ date: Date) -> Bool {
        let normalized = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: normalized)
        
        if holidays(for: year).contains(normalized) { return true }
        if holidays(for: year - 1).contains(normalized) { return true }
        if holidays(for: year + 1).contains(normalized) { return true }
        
        return false
    }
    
    private mutating func holidays(for year: Int) -> Set<Date> {
        if let cached = holidaysCache[year] {
            return cached
        }
        
        var holidays: Set<Date> = []
        
        func addObserved(month: Int, day: Int, year: Int) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let rawDate = calendar.date(from: components) else { return }
            let normalized = calendar.startOfDay(for: rawDate)
            holidays.insert(normalized)
            
            if calendar.isDateInWeekend(normalized) {
                let weekday = calendar.component(.weekday, from: normalized)
                if weekday == 7, let observed = calendar.date(byAdding: .day, value: -1, to: normalized) {
                    holidays.insert(calendar.startOfDay(for: observed))
                } else if weekday == 1, let observed = calendar.date(byAdding: .day, value: 1, to: normalized) {
                    holidays.insert(calendar.startOfDay(for: observed))
                }
            }
        }
        
        func nthWeekday(of month: Int, weekday: Int, occurrence: Int, year: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.weekday = weekday
            components.weekdayOrdinal = occurrence
            return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
        }
        
        func lastWeekday(of month: Int, weekday: Int, year: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month + 1
            components.day = 0
            guard let endOfMonth = calendar.date(from: components) else { return nil }
            var current = calendar.startOfDay(for: endOfMonth)
            while calendar.component(.weekday, from: current) != weekday {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { break }
                current = previous
            }
            return current
        }
        
        addObserved(month: 1, day: 1, year: year)
        if let mlkDay = nthWeekday(of: 1, weekday: 2, occurrence: 3, year: year) { holidays.insert(mlkDay) }
        if let presidentsDay = nthWeekday(of: 2, weekday: 2, occurrence: 3, year: year) { holidays.insert(presidentsDay) }
        if let memorialDay = lastWeekday(of: 5, weekday: 2, year: year) { holidays.insert(memorialDay) }
        addObserved(month: 6, day: 19, year: year)
        addObserved(month: 7, day: 4, year: year)
        if let laborDay = nthWeekday(of: 9, weekday: 2, occurrence: 1, year: year) { holidays.insert(laborDay) }
        if let columbusDay = nthWeekday(of: 10, weekday: 2, occurrence: 2, year: year) { holidays.insert(columbusDay) }
        addObserved(month: 11, day: 11, year: year)
        if let thanksgiving = nthWeekday(of: 11, weekday: 5, occurrence: 4, year: year) { holidays.insert(thanksgiving) }
        addObserved(month: 12, day: 25, year: year)
        
        lock.lock()
        holidaysCache[year] = holidays
        lock.unlock()
        
        return holidays
    }
}

