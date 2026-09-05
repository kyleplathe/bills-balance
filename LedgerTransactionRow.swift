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
    var showsRunningBalance: Bool = true
    var showsAccountInSubtitle: Bool = false
    var showsReconcileControl: Bool = true
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

    private var subtitleText: String? {
        var parts: [String] = []
        if let date = entry.date {
            parts.append(formatTransactionDate(date))
        }
        if showsAccountInSubtitle, let name = account.name, !name.isEmpty {
            parts.append(name)
        }
        if let category = entry.category, !category.isEmpty {
            parts.append(category)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if showsReconcileControl {
                Button {
                    if account.currencyCode == "BTC" && !entry.isReconciledFlag && entry.btcAmountDecimal == 0 {
                        onReconcile(entry)
                    } else {
                        accountViewModel.toggleReconciled(for: entry)
                    }
                } label: {
                    if entry.isReconciledFlag {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 26, height: 26)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.isReconciledFlag ? "Mark uncleared" : "Mark cleared")
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(entry.title ?? "Transaction")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if !entry.isReconciledFlag {
                        Text("PENDING")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                            .fixedSize()
                    }
                }
                
                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 12)
            
            VStack(alignment: .trailing, spacing: 1) {
                Text((entry.isCredit ? "+ " : "- ") + formattedAmount)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(entry.isCredit ? .green : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if showsRunningBalance && entry.isReconciledFlag {
                    Text(formattedRunningBalance)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .layoutPriority(1)
            .id("\(entry.objectID)-\(bitcoinPriceService.showInBitcoin)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                accountViewModel.toggleReconciled(for: entry)
            } label: {
                Label(entry.isReconciledFlag ? "Unreconcile" : "Reconcile", 
                      systemImage: entry.isReconciledFlag ? "circle" : "checkmark.circle.fill")
            }
            .tint(entry.isReconciledFlag ? .orange : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                accountViewModel.deleteLedgerEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

