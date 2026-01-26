//
//  ManualTransactionEntrySheet.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI

struct ManualTransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let account: Account
    
    @State private var title: String = ""
    @State private var amountString: String = ""
    @State private var feeAmountString: String = ""
    @State private var satsAmountString: String = ""
    @State private var btcPriceString: String = ""
    @State private var isCredit: Bool = false
    @State private var category: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var isCleared: Bool = false
    @State private var showValidationAlert = false
    @State private var validationMessage: String = ""
    
    private var isBTCAccount: Bool {
        account.currencyCode == "BTC"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Name", text: $title)
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
                    
                    if isBTCAccount {
                        // USD Amount
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $amountString)
                                .keyboardType(.decimalPad)
                                .onChange(of: amountString) { _, newValue in
                                    // Auto-calculate fee when amount changes
                                    autoCalculateFee()
                                }
                            if !amountString.isEmpty {
                                Button {
                                    amountString = ""
                                    feeAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        
                        // Fee Amount with percentage
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("Fee (Optional)", text: $feeAmountString)
                                .keyboardType(.decimalPad)
                                .onChange(of: feeAmountString) { _, newValue in
                                    // Update fee percentage display when manually changed
                                }
                            if let amount = Decimal(string: amountString.replacingOccurrences(of: ",", with: "")), amount > 0,
                               let fee = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "")), fee > 0 {
                                let percentage = (fee / amount) * 100
                                Text("(\(String(format: "%.3f", (percentage as NSDecimalNumber).doubleValue))%)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
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
                        
                        // Total (calculated, read-only)
                        HStack {
                            Text("Total")
                            Spacer()
                            if let amount = Decimal(string: amountString.replacingOccurrences(of: ",", with: "")),
                               let fee = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "")) {
                                let total = amount + fee
                                Text(formatCurrency(total))
                                    .fontWeight(.semibold)
                            } else {
                                Text("$0.00")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Sats Amount
                        HStack {
                            TextField("Sats Amount", text: $satsAmountString)
                                .keyboardType(.numberPad)
                                .onChange(of: satsAmountString) { _, newValue in
                                    // Auto-calculate BTC price when sats are entered
                                    autoCalculateBTCPrice()
                                }
                            if !satsAmountString.isEmpty {
                                Button {
                                    satsAmountString = ""
                                    btcPriceString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        
                        // BTC Price (auto-calculated or current price)
                        HStack {
                            Text("BTC Price")
                            Spacer()
                            if !btcPriceString.isEmpty {
                                Text("$\(btcPriceString)")
                                    .foregroundColor(.secondary)
                            } else {
                                Text(formatCurrency(bitcoinPriceService.btcToUsdRate))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // USD accounts - simple amount field
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $amountString)
                                .keyboardType(.decimalPad)
                            if !amountString.isEmpty {
                                Button {
                                    amountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                    
                    Toggle("Cleared", isOn: $isCleared)
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
                }
            }
            .navigationTitle("New Transaction")
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
            .alert("Validation Error", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private func autoCalculateBTCPrice() {
        // Get USD amount (total including fee)
        let cleaned = amountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let feeCleaned = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        
        guard let amount = Decimal(string: cleaned), amount > 0 else {
            btcPriceString = ""
            return
        }
        
        let fee = Decimal(string: feeCleaned) ?? 0
        let totalUSD = amount + fee
        
        // Get sats amount
        let cleanedSats = satsAmountString.replacingOccurrences(of: ",", with: "")
        guard let sats = Int(cleanedSats), sats > 0 else {
            btcPriceString = ""
            return
        }
        
        // Calculate BTC price: USD / BTC
        let btcAmount = Decimal(sats) / 100_000_000
        guard btcAmount > 0 else {
            btcPriceString = ""
            return
        }
        
        let calculatedPrice = totalUSD / btcAmount
        
        // Format and update BTC price string
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        btcPriceString = formatter.string(from: calculatedPrice as NSDecimalNumber) ?? ""
    }
    
    private func autoCalculateFee() {
        // Get fee percentage from account settings
        let feePercentage = account.feePercentageDecimal
        
        guard feePercentage > 0 else {
            // No fee percentage set, clear fee amount
            feeAmountString = ""
            return
        }
        
        // Get the USD amount
        let cleaned = amountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard let amount = Decimal(string: cleaned), amount > 0 else {
            feeAmountString = ""
            return
        }
        
        // Calculate fee with rounded percentage
        // Round to 3 decimal places, with 3rd digit set to 5 if in range
        let roundedPercentage = roundFeePercentage(feePercentage)
        let calculatedFee = amount * (roundedPercentage / 100)
        
        // Format and update fee amount string
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        feeAmountString = formatter.string(from: calculatedFee as NSDecimalNumber) ?? ""
    }
    
    private func roundFeePercentage(_ percentage: Decimal) -> Decimal {
        // Convert to double for easier manipulation
        let percentageDouble = (percentage as NSDecimalNumber).doubleValue
        
        // Get the first two decimal places (e.g., 0.79 from 0.794)
        let firstTwoDecimals = floor(percentageDouble * 100) / 100
        
        // Get the third decimal digit (e.g., 4 from 0.794)
        let thirdDigit = Int((percentageDouble * 1000).truncatingRemainder(dividingBy: 10))
        
        // If third digit is 4, 5, 6, or 7, set it to 5
        // This handles the range .794-.797% -> .795%
        if thirdDigit >= 4 && thirdDigit <= 7 {
            return Decimal(firstTwoDecimals) + Decimal(5) / 1000
        }
        
        // Otherwise, round normally to 3 decimal places
        let rounded = (percentageDouble * 1000).rounded() / 1000
        return Decimal(rounded)
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
    
    private func saveTransaction() {
        guard !title.isEmpty else {
            validationMessage = "Please enter a title"
            showValidationAlert = true
            return
        }
        
        let cleaned = amountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty,
              let amount = Decimal(string: cleaned),
              amount > 0 else {
            validationMessage = "Please enter a valid amount"
            showValidationAlert = true
            return
        }
        
        // Determine the sign based on isCredit
        let signedAmount = isCredit ? amount : -amount
        
        // Create transaction entry
        let finalCategory = category.isEmpty ? nil : category
        
        if isBTCAccount {
            // For BTC accounts, calculate total including fee
            let feeAmount: Decimal = {
                let cleanedFee = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                return Decimal(string: cleanedFee) ?? 0
            }()
            
            let totalAmount = amount + feeAmount
            
            // Get sats amount if provided
            let satsAmount: Decimal? = {
                let cleanedSats = satsAmountString.replacingOccurrences(of: ",", with: "")
                if let sats = Int(cleanedSats), sats > 0 {
                    return Decimal(sats) / 100_000_000 // Convert sats to BTC
                }
                return nil
            }()
            
            // Get BTC price (use calculated price if available, otherwise current price)
            let btcPrice: Decimal = {
                if !btcPriceString.isEmpty {
                    let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                    return Decimal(string: cleanedPrice) ?? bitcoinPriceService.btcToUsdRate
                } else if let sats = satsAmount, sats > 0, totalAmount > 0 {
                    // Auto-calculate from USD and BTC amounts
                    return totalAmount / sats
                } else {
                    return bitcoinPriceService.btcToUsdRate
                }
            }()
            
            // Store fee separately (not in notes)
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: satsAmount,
                usdAmount: signedAmount > 0 ? totalAmount : -totalAmount,
                btcPriceAtTransaction: btcPrice,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: finalCategory,
                feeAmount: feeAmount > 0 ? feeAmount : nil
            )
        } else {
            // For USD accounts, store USD amount
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: nil,
                usdAmount: signedAmount,
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: finalCategory
            )
        }
        
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        accountViewModel.fetchAccounts()
        
        dismiss()
    }
}
