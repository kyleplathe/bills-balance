//
//  BillRowView.swift
//  BillsAndBalance
//

import SwiftUI
import CoreData

struct BillRowView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let bill: Bill
    var onMarkPaid: ((Bill) -> Void)? = nil
    var compact: Bool = false
    
    @State private var showingReconcileDrawer = false
    @State private var billAmountString: String = ""
    @State private var feeAmountString: String = ""
    @State private var btcSatsAmountString: String = ""
    @State private var btcPriceString: String = ""
    @FocusState private var focusedField: ReconcileField?
    
    enum ReconcileField {
        case billAmount
        case feeAmount
        case btcSatsAmount
        case btcPrice
    }
    
    private var isOverdue: Bool {
        guard let dueDate = bill.dueDate else { return false }
        return dueDate < Date() && !bill.isPaid
    }
    
    private var daysUntilDue: Int {
        guard let dueDate = bill.dueDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }
    
    // Check if bill is paid with credit card only (no account)
    private var isCreditCardOnlyBill: Bool {
        if let paymentCard = bill.paymentCard, !paymentCard.isEmpty, bill.account == nil {
            return true
        }
        return false
    }
    
    // Check if bill has pending transactions (unreconciled ledger entries)
    private var hasPendingTransaction: Bool {
        // Credit card bills shouldn't have pending transactions
        if isCreditCardOnlyBill {
            return false
        }
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry>, !entries.isEmpty else { return false }
        return entries.contains { !$0.isReconciledFlag }
    }
    
    // Get the pending ledger entry for this bill
    private var pendingEntry: LedgerEntry? {
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry> else { return nil }
        return entries.first { !$0.isReconciledFlag }
    }
    
    // Check if bill is in a BTC account
    private var isBTCAccount: Bool {
        bill.account?.currencyCode == "BTC"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: compact ? 10 : 16) {
            // Status indicator with bitcoin theme
            Button {
                // Tap circle = Mark as cleared (paid)
                let willMarkPaid = !bill.isPaid
                
                if willMarkPaid {
                    // For BTC accounts, check if we need to show reconcile drawer
                    if isBTCAccount {
                        // Check if pending entry already has BTC price and sats values
                        if let entry = pendingEntry {
                            // Verify both BTC amount (sats) and BTC price are present and valid
                            let hasBTCAmount = entry.btcAmountDecimal > 0
                            let hasBTCPrice = entry.btcPriceAtTransactionDecimal > 0
                            
                            if hasBTCAmount && hasBTCPrice {
                                // Both sats and BTC price are present - reconcile with current info
                                // Mark the entry as reconciled
                                entry.isReconciledFlag = true
                                accountViewModel.saveContext()
                                billViewModel.markPaidPreservingLedger(for: bill)
                                
                                HapticManager.shared.billMarkedPaid()
                            } else {
                                // Missing BTC values (sats or price) - show drawer to enter them
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    showingReconcileDrawer = true
                                }
                            }
                        } else {
                            // No pending entry - show drawer to create new entry with BTC values
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                showingReconcileDrawer = true
                            }
                        }
                    } else {
                        // Non-BTC account - mark as paid directly
                        if let callback = onMarkPaid {
                            callback(bill)
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                billViewModel.togglePaidStatus(for: bill)
                            }
                            HapticManager.shared.billMarkedPaid()
                        }
                    }
                } else {
                    // Unmark as paid
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        billViewModel.togglePaidStatus(for: bill)
                    }
                    HapticManager.shared.buttonTapped()
                }
            } label: {
                // Show as unpaid (open circle) if bill has pending transactions, even if marked as paid
                let isFullyPaid = bill.isPaid && !hasPendingTransaction
                Circle()
                    .fill(isFullyPaid ? statusColor : Color.clear)
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    .overlay(
                        Circle()
                            .stroke(bitcoinPriceService.showInBitcoin && !isFullyPaid ? .orange : statusColor, lineWidth: 2)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: compact ? 11 : 14, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(isFullyPaid ? 1 : 0)
                    )
                    .padding(.vertical, compact ? 0 : 4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((bill.isPaid && !hasPendingTransaction) ? "Mark unpaid" : "Mark paid")
            .accessibilityHint("Tap to toggle paid state")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
            
            if compact {
                compactBillInfo
                Spacer(minLength: 8)
                compactAmount
            } else {
            // Bill info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bill.name ?? "Unknown")
                        .font(.body)
                        .fontWeight(.medium)
                        // Only strikethrough if paid AND fully reconciled (no pending transactions)
                        .strikethrough(bill.isPaid && !hasPendingTransaction)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if bill.autoPay {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    // Show PENDING badge if bill has pending transactions
                    if hasPendingTransaction {
                        Text("PENDING")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if bill.isPaid {
                        // Only show PAID if fully reconciled (no pending transactions)
                        Text("PAID")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if let accountName = bill.account?.name, !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let paymentCard = bill.paymentCard, !paymentCard.isEmpty {
                    Label(paymentCard, systemImage: "creditcard.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    if let dueDate = bill.dueDate {
                        Text(dateFormatter.string(from: dueDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !bill.isPaid {
                            if daysUntilDue < 0 {
                                Text("• \(abs(daysUntilDue))d overdue")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            } else if daysUntilDue <= 3 {
                                Text("• \(daysUntilDue)d left")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    if bill.recurrenceType != "none", let recurrenceType = bill.recurrenceType {
                        Text("• \(formatRecurrenceType(recurrenceType, interval: Int(bill.recurrenceInterval)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Amount with smooth animation
            Group {
                if bitcoinPriceService.showInBitcoin, let amount = bill.amount?.decimalValue {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bitcoinPriceService.formatAsSats(amount))
                            .font(.headline)
                            .foregroundColor(bill.isPaid ? .green : .orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("$\(amount, format: .number.precision(.fractionLength(2)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                } else {
                    Text("$\(bill.amount?.stringValue ?? "0")")
                        .font(.headline)
                        .foregroundColor(bill.isPaid ? .green : .primary)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
            }
            
            // Removed arrow button - keeping it simple: just check off the bill
        }
        .padding(.vertical, compact ? 0 : 4)
        
            // Reconcile drawer for BTC accounts (with or without pending transactions)
            if showingReconcileDrawer && isBTCAccount {
                reconcileDrawer
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity).combined(with: .move(edge: .top)),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity).combined(with: .move(edge: .top))
                    ))
            }
        }
        .onChange(of: showingReconcileDrawer) { oldValue, newValue in
            if newValue {
                // Initialize fields when drawer opens
                if let entry = pendingEntry {
                    // Has pending transaction - use entry values
                    // Try to extract bill amount and fee from notes
                    var extractedBillAmount = entry.usdAmountDecimal
                    var extractedFee: Decimal = 0
                    
                    if let notes = entry.notes,
                       let feeRange = notes.range(of: #"Strike fee:.*?\$([\d,]+\.?\d*)"#, options: .regularExpression) {
                        let feeMatch = notes[feeRange]
                        if let amountRange = feeMatch.range(of: #"([\d,]+\.?\d*)"#, options: .regularExpression) {
                            let feeString = String(feeMatch[amountRange]).replacingOccurrences(of: ",", with: "")
                            if let fee = Decimal(string: feeString) {
                                extractedFee = fee
                                extractedBillAmount = extractedBillAmount - fee
                            }
                        }
                    }
                    
                    if extractedBillAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: extractedBillAmount as NSDecimalNumber) ?? ""
                        
                        if extractedFee > 0 {
                            feeAmountString = formatter.string(from: extractedFee as NSDecimalNumber) ?? ""
                        }
                    } else if let billAmount = bill.amount?.decimalValue, billAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: billAmount as NSDecimalNumber) ?? ""
                    }
                    
                    // Initialize BTC/sats amount if available
                    if entry.btcAmountDecimal > 0 {
                        let sats = entry.btcAmountDecimal * 100_000_000
                        let satsFormatter = NumberFormatter()
                        satsFormatter.numberStyle = .decimal
                        satsFormatter.maximumFractionDigits = 0
                        satsFormatter.groupingSeparator = ","
                        btcSatsAmountString = satsFormatter.string(from: sats as NSDecimalNumber) ?? ""
                    }
                    
                    // Always default to current BTC price if no price set
                    if entry.btcPriceAtTransactionDecimal > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        btcPriceString = formatter.string(from: entry.btcPriceAtTransactionDecimal as NSDecimalNumber) ?? ""
                    } else {
                        // Pre-fill with current BTC price
                        let currentPrice = bitcoinPriceService.btcToUsdRate
                        if currentPrice > 0 {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            formatter.maximumFractionDigits = 2
                            btcPriceString = formatter.string(from: currentPrice as NSDecimalNumber) ?? ""
                        }
                    }
                } else {
                    // No pending transaction - use bill amount and current BTC price
                    if let billAmount = bill.amount?.decimalValue, billAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: billAmount as NSDecimalNumber) ?? ""
                    }
                    
                    // Pre-fill with current BTC price
                    let currentPrice = bitcoinPriceService.btcToUsdRate
                    if currentPrice > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        btcPriceString = formatter.string(from: currentPrice as NSDecimalNumber) ?? ""
                    }
                }
                // Auto-focus bill amount field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .billAmount
                }
            }
        }
    }
    
    private var compactBillInfo: some View {
        HStack(spacing: 6) {
            Text(bill.name ?? "Unknown")
                .font(.subheadline.weight(.medium))
                .strikethrough(bill.isPaid && !hasPendingTransaction)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if bill.autoPay {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            if hasPendingTransaction {
                Text("PENDING")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var compactAmount: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if bitcoinPriceService.showInBitcoin, let amount = bill.amount?.decimalValue {
                Text(bitcoinPriceService.formatAsSats(amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(bill.isPaid ? .green : .orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("$\(bill.amount?.stringValue ?? "0")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(bill.isPaid ? .green : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            if let dueDate = bill.dueDate {
                if !bill.isPaid, daysUntilDue < 0 {
                    Text("\(abs(daysUntilDue))d overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.red)
                } else if !bill.isPaid, daysUntilDue <= 3 {
                    Text("\(daysUntilDue)d left")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text(dateFormatter.string(from: dueDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var statusColor: Color {
        if bill.isPaid {
            return .green
        } else if isOverdue {
            return .red
        } else if daysUntilDue <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    private func formatRecurrenceType(_ type: String, interval: Int) -> String {
        switch type {
        case "none":
            return ""
        case "daily":
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case "weekly":
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case "biweekly":
            return "Bi-weekly"
        case "monthly":
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        case "bimonthly":
            return "Bi-monthly"
        case "quarterly":
            return interval == 1 ? "Quarterly" : "Every \(interval) quarters"
        case "semiannually":
            return "Semi-annually"
        case "yearly":
            return interval == 1 ? "Yearly" : "Every \(interval) years"
        default:
            return type.capitalized
        }
    }
    
    @ViewBuilder
    private var reconcileDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)
            
            Text("Enter Transaction Details")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bill Amount (USD)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $billAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .billAmount)
                        .onChange(of: billAmountString) { oldValue, newValue in
                            // Auto-calculate total and BTC/sats if price is available
                            updateCalculations()
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fee Amount (USD) - Optional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $feeAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .feeAmount)
                        .onChange(of: feeAmountString) { oldValue, newValue in
                            // Auto-calculate total and BTC/sats if price is available
                            updateCalculations()
                        }
                    
                    // Show total calculation
                    if !billAmountString.isEmpty,
                       let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                       billAmount > 0 {
                        let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                        let totalAmount = billAmount + feeAmount
                        if let totalString = formatUSD(totalAmount) {
                            HStack {
                                Text("Total:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(totalString)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("BTC/Sats Amount (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter BTC or sats", text: $btcSatsAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .btcSatsAmount)
                        .onChange(of: btcSatsAmountString) { oldValue, newValue in
                            updateCalculations()
                        }
                    
                    // BTC Price - show below BTC/sats field
                    HStack {
                        Text("BTC Price:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Check if we can auto-calculate price (have bill amount, fee, and sats)
                        let canAutoCalculatePrice: Bool = {
                            guard !billAmountString.isEmpty,
                                  let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                                  billAmount >= 0,
                                  !btcSatsAmountString.isEmpty,
                                  let btcSatsValue = Decimal(string: btcSatsAmountString.replacingOccurrences(of: ",", with: "")),
                                  btcSatsValue > 0 else {
                                return false
                            }
                            let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let totalAmount = billAmount + feeAmount
                            return totalAmount > 0
                        }()
                        
                        if canAutoCalculatePrice {
                            // Auto-calculated price - show as read-only
                            let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let totalAmount = billAmount + feeAmount
                            let btcSatsValue = Decimal(string: btcSatsAmountString.replacingOccurrences(of: ",", with: "")) ?? 0
                            let btcAmount = detectAndConvertToBTC(btcSatsValue)
                            let calculatedPrice = btcAmount > 0 ? totalAmount / btcAmount : 0
                            
                            HStack {
                                Spacer()
                                if let priceString = formatUSD(calculatedPrice) {
                                    Text(priceString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("")
                                }
                            }
                            .onAppear {
                                updateCalculations()
                            }
                            .onChange(of: billAmountString) { _, _ in
                                updateCalculations()
                            }
                            .onChange(of: feeAmountString) { _, _ in
                                updateCalculations()
                            }
                            .onChange(of: btcSatsAmountString) { _, _ in
                                updateCalculations()
                            }
                        } else {
                            // Manual price entry - editable
                            TextField("0.00", text: $btcPriceString)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .btcPrice)
                                .frame(maxWidth: 120)
                                .onChange(of: btcPriceString) { oldValue, newValue in
                                    // Only calculate sats if we have USD but not sats
                                    if !newValue.isEmpty && !billAmountString.isEmpty && btcSatsAmountString.isEmpty,
                                       let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                                       let btcPrice = Decimal(string: newValue.replacingOccurrences(of: ",", with: "")),
                                       btcPrice > 0 {
                                        let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                                        let totalAmount = billAmount + feeAmount
                                        let btcAmount = totalAmount / btcPrice
                                        let sats = btcAmount * 100_000_000
                                        let formatter = NumberFormatter()
                                        formatter.numberStyle = .decimal
                                        formatter.maximumFractionDigits = 0
                                        formatter.groupingSeparator = ","
                                        btcSatsAmountString = formatter.string(from: sats as NSDecimalNumber) ?? ""
                                    }
                                }
                        }
                    }
                }
                
                // Show calculated BTC amount when total USD and price are entered
                if !billAmountString.isEmpty && !btcPriceString.isEmpty,
                   let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                   let btcPrice = Decimal(string: btcPriceString.replacingOccurrences(of: ",", with: "")),
                   btcPrice > 0 {
                    let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                    let totalAmount = billAmount + feeAmount
                    let btcAmount = totalAmount / btcPrice
                    let sats = btcAmount * 100_000_000
                    
                    HStack {
                        Text("Total BTC Amount:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatSats(sats))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingReconcileDrawer = false
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveReconcile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(billAmountString.isEmpty || (billAmountString != "0" && billAmountString != "0.00" && btcSatsAmountString.isEmpty && btcPriceString.isEmpty))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.top, 8)
    }
    
    // Helper function to update calculations when amounts change
    private func updateCalculations() {
        let cleanedBill = billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedFee = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedBTCSats = btcSatsAmountString.replacingOccurrences(of: ",", with: "")
        let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "")
        
        guard let billAmount = Decimal(string: cleanedBill), billAmount >= 0 else { return }
        let feeAmount = Decimal(string: cleanedFee) ?? 0
        let totalAmount = billAmount + feeAmount
        
        // If we have bill amount, fee, and sats, calculate BTC price
        if !cleanedBTCSats.isEmpty,
           let btcSatsValue = Decimal(string: cleanedBTCSats),
           btcSatsValue > 0,
           totalAmount > 0 {
            let btcAmount = detectAndConvertToBTC(btcSatsValue)
            if btcAmount > 0 {
                let calculatedPrice = totalAmount / btcAmount
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 2
                btcPriceString = formatter.string(from: calculatedPrice as NSDecimalNumber) ?? ""
            }
        }
        // Otherwise, if we have price and USD, calculate sats (only if sats field is empty)
        else if !cleanedPrice.isEmpty,
                let btcPrice = Decimal(string: cleanedPrice),
                btcPrice > 0,
                totalAmount > 0,
                btcSatsAmountString.isEmpty {
            let btcAmount = totalAmount / btcPrice
            let sats = btcAmount * 100_000_000
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            btcSatsAmountString = formatter.string(from: sats as NSDecimalNumber) ?? ""
        }
    }
    
    private func saveReconcile() {
        let cleanedBill = billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedFee = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedBTCSats = btcSatsAmountString.replacingOccurrences(of: ",", with: "")
        let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "")
        
        // Allow zero amounts (for $0 bills)
        guard let billAmount = Decimal(string: cleanedBill), billAmount >= 0 else {
            return
        }
        
        let feeAmount = Decimal(string: cleanedFee) ?? 0
        let totalAmount = billAmount + feeAmount
        
        var btcAmount: Decimal = 0
        var btcPrice: Decimal = 0
        
        // Determine BTC amount and price from available inputs
        if !cleanedBTCSats.isEmpty, let btcSatsValue = Decimal(string: cleanedBTCSats), btcSatsValue > 0 {
            // BTC/sats amount provided
            btcAmount = detectAndConvertToBTC(btcSatsValue)
            
            if !cleanedPrice.isEmpty, let priceValue = Decimal(string: cleanedPrice), priceValue > 0 {
                // BTC price provided
                btcPrice = priceValue
            } else if totalAmount > 0 && btcAmount > 0 {
                // Calculate BTC price from total USD and BTC amounts
                btcPrice = totalAmount / btcAmount
            } else {
                // Use current BTC price as fallback
                btcPrice = bitcoinPriceService.btcToUsdRate
            }
        } else if !cleanedPrice.isEmpty, let priceValue = Decimal(string: cleanedPrice), priceValue > 0 {
            // Only USD and price provided - calculate BTC amount
            btcPrice = priceValue
            btcAmount = totalAmount / btcPrice
        } else if totalAmount > 0 {
            // Only USD provided - use current price as fallback
            btcPrice = bitcoinPriceService.btcToUsdRate
            btcAmount = totalAmount / btcPrice
        }
        
        // Build notes with fee breakdown (matching Strike format)
        var transactionNotes = bill.notes ?? ""
        if feeAmount > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            if let feeString = formatter.string(from: feeAmount as NSDecimalNumber) {
                if transactionNotes.isEmpty {
                    transactionNotes = "Strike fee: \(feeString)"
                } else {
                    transactionNotes = "\(transactionNotes)\nStrike fee: \(feeString)"
                }
            }
        }
        
        // Check if we have a pending transaction to reconcile
        if let entry = pendingEntry {
            // Reconcile existing pending transaction
            // For zero amounts, just mark as reconciled
            if totalAmount == 0 {
                entry.isReconciledFlag = true
                entry.usdAmount = NSDecimalNumber(decimal: .zero)
                entry.btcAmount = NSDecimalNumber(decimal: .zero)
                entry.amount = NSDecimalNumber(decimal: .zero)
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: .zero)
                entry.notes = transactionNotes.isEmpty ? nil : transactionNotes
                accountViewModel.saveContext()
                accountViewModel.refreshLedgerEntries()
                billViewModel.markPaidPreservingLedger(for: bill)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingReconcileDrawer = false
                }
                HapticManager.shared.billMarkedPaid()
                return
            }
            
            // Update entry with reconciled values (total amount includes fee)
            entry.usdAmount = NSDecimalNumber(decimal: totalAmount)
            entry.btcAmount = NSDecimalNumber(decimal: btcAmount)
            entry.amount = NSDecimalNumber(decimal: btcAmount)
            entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
            entry.notes = transactionNotes.isEmpty ? nil : transactionNotes
            entry.isReconciledFlag = true // Mark as fully reconciled
            
            accountViewModel.saveContext()
            accountViewModel.refreshLedgerEntries()
            billViewModel.markPaidPreservingLedger(for: bill)
        } else {
            // No pending transaction - create new ledger entry with BTC/sats value
            // For zero amounts, just mark bill as paid without creating entry
            if totalAmount == 0 {
                billViewModel.markPaidPreservingLedger(for: bill)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingReconcileDrawer = false
                }
                HapticManager.shared.billMarkedPaid()
                return
            }
            
            // Create new ledger entry directly and mark as reconciled immediately
            let satsAmount = btcAmount * 100_000_000
            let paidDate = Date()
            
            // Create the ledger entry with total amount (bill + fee) and mark it as reconciled
            if let entry = accountViewModel.recordLedgerEntry(for: bill,
                                                              amount: totalAmount, // Store total (bill + fee)
                                                              date: paidDate,
                                                              isCredit: false,
                                                              title: bill.name,
                                                              notes: transactionNotes,
                                                              satsAmount: satsAmount) {
                // Set BTC price and mark as reconciled
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
                entry.isReconciledFlag = true
                accountViewModel.saveContext()
                accountViewModel.refreshLedgerEntries()
            }
            billViewModel.markPaidPreservingLedger(for: bill)
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingReconcileDrawer = false
        }
        HapticManager.shared.billMarkedPaid()
    }
    
    // Helper function to detect if input is BTC or sats and convert to BTC
    private func detectAndConvertToBTC(_ value: Decimal) -> Decimal {
        // If value is >= 1, assume it's sats (convert to BTC)
        // If value is < 1, assume it's BTC
        if value >= 1 {
            return value / 100_000_000
        } else {
            return value
        }
    }
    
    private func formatSats(_ sats: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        
        if sats >= 1_000_000 {
            return "\(formatter.string(from: sats as NSDecimalNumber) ?? "") sats"
        } else {
            return "\(formatter.string(from: sats as NSDecimalNumber) ?? "") sats"
        }
    }
    
    private func formatUSD(_ value: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber)
    }
}

#Preview {
    let controller = PersistenceController.preview
    let notif = NotificationManager()
    let accountVM = AccountViewModel(context: controller.container.viewContext)
    let billVM = BillViewModel(context: controller.container.viewContext,
                               notificationManager: notif,
                               accountViewModel: accountVM)
    BillListView()
        .environmentObject(billVM)
        .environmentObject(accountVM)
        .environmentObject(notif)
}

