//
//  LedgerTransactionRow.swift
//  BillsAndBalance
//

import SwiftUI
import CoreData

// MARK: - Transaction Row

struct TransactionRow: View {
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
        RelativeDateFormatter.string(from: date)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Transaction status icon - green circle with white checkmark for cleared
            // Tappable to toggle reconciled status
            Button {
                // When checking off (reconciling) a transaction:
                // If it's a BTC account and missing sats, open reconcile drawer
                // Otherwise, toggle reconciled status directly
                if account.currencyCode == "BTC" && !entry.isReconciledFlag && entry.btcAmountDecimal == 0 {
                    // About to reconcile but missing sats - show reconciliation drawer
                    onReconcile(entry)
                } else {
                    // Has sats, not BTC account, or unreconciling - toggle directly
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

