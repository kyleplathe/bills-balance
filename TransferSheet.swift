//
//  TransferSheet.swift
//  BillsAndBalance
//
//  Created on 1/26/26.
//

import SwiftUI

struct TransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let fromAccount: Account
    
    @State private var toAccount: Account?
    @State private var amountString: String = ""
    @State private var feeAmountString: String = ""
    @State private var satsAmountString: String = ""
    @State private var btcPriceString: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var isCleared: Bool = false
    @State private var showValidationAlert = false
    @State private var validationMessage: String = ""
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isFeeFocused: Bool
    @FocusState private var isSatsFocused: Bool
    
    private var isBTCTransfer: Bool {
        fromAccount.currencyCode == "BTC" || toAccount?.currencyCode == "BTC"
    }
    
    private var availableAccounts: [Account] {
        accountViewModel.accounts.filter { account in
            account.objectID != fromAccount.objectID && !account.isHiddenFlag
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // From Account (read-only)
                    HStack {
                        Text("From")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(fromAccount.name ?? "Account")
                            .foregroundStyle(.primary)
                    }
                    
                    // To Account Picker
                    Picker("To", selection: $toAccount) {
                        Text("Select Account")
                            .tag(nil as Account?)
                        ForEach(availableAccounts, id: \.objectID) { account in
                            Text(account.name ?? "Account")
                                .tag(account as Account?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                
                Section {
                    if isBTCTransfer {
                        // USD Amount
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $amountString)
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .onChange(of: isAmountFocused) { oldValue, newValue in
                                    if !newValue {
                                        formatAmountOnBlur()
                                    }
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
                        
                        // Fee Amount (optional)
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("Fee (Optional)", text: $feeAmountString)
                                .keyboardType(.decimalPad)
                                .focused($isFeeFocused)
                                .onChange(of: isFeeFocused) { oldValue, newValue in
                                    if !newValue {
                                        formatFeeOnBlur()
                                    }
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
                        
                        // Sats Amount (for BTC accounts)
                        if fromAccount.currencyCode == "BTC" || toAccount?.currencyCode == "BTC" {
                            HStack {
                                Text("₿")
                                    .foregroundColor(.secondary)
                                TextField("0", text: $satsAmountString)
                                    .keyboardType(.numberPad)
                                    .focused($isSatsFocused)
                                    .onChange(of: isSatsFocused) { oldValue, newValue in
                                        if !newValue {
                                            formatSatsOnBlur()
                                        }
                                    }
                                Text("sats")
                                    .foregroundColor(.secondary)
                                if !satsAmountString.isEmpty {
                                    Button {
                                        satsAmountString = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 16))
                                    }
                                }
                            }
                        }
                    } else {
                        // USD Amount for USD-to-USD transfers
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            TextField("0.00", text: $amountString)
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .onChange(of: isAmountFocused) { oldValue, newValue in
                                    if !newValue {
                                        formatAmountOnBlur()
                                    }
                                }
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
                } header: {
                    Text("Amount")
                }
                
                Section {
                    TextField("Notes (Optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Toggle("Cleared", isOn: $isCleared)
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LiveDateTimeView()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        saveTransfer()
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
    
    // MARK: - Formatting Functions
    
    private func formatAmountOnBlur() {
        var cleaned = amountString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        let components = cleaned.components(separatedBy: ".")
        if components.count > 2 {
            cleaned = components[0] + "." + components.dropFirst().joined()
        }
        guard let number = Decimal(string: cleaned), number > 0 else {
            if cleaned.isEmpty {
                amountString = ""
            }
            return
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        amountString = formatter.string(from: number as NSDecimalNumber) ?? cleaned
    }
    
    private func formatFeeOnBlur() {
        var cleaned = feeAmountString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        let components = cleaned.components(separatedBy: ".")
        if components.count > 2 {
            cleaned = components[0] + "." + components.dropFirst().joined()
        }
        guard let number = Decimal(string: cleaned), number >= 0 else {
            if cleaned.isEmpty {
                feeAmountString = ""
            }
            return
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        feeAmountString = formatter.string(from: number as NSDecimalNumber) ?? cleaned
    }
    
    private func formatSatsOnBlur() {
        let cleaned = satsAmountString.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard let number = Int(cleaned), number > 0 else {
            if cleaned.isEmpty {
                satsAmountString = ""
            }
            return
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        satsAmountString = formatter.string(from: NSNumber(value: number)) ?? cleaned
    }
    
    // MARK: - Save Function
    
    private func saveTransfer() {
        // Validate to account
        guard let toAccount = toAccount else {
            validationMessage = "Please select a destination account."
            showValidationAlert = true
            return
        }
        
        // Validate amount
        guard !amountString.isEmpty, !amountString.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Please enter an amount."
            showValidationAlert = true
            return
        }
        
        let cleanedAmount = amountString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let amount = Decimal(string: cleanedAmount), amount > 0 else {
            validationMessage = "Please enter a valid amount."
            showValidationAlert = true
            return
        }
        
        // Parse fee if provided
        let feeAmount: Decimal? = {
            if feeAmountString.isEmpty {
                return nil
            }
            let cleaned = feeAmountString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            return Decimal(string: cleaned)
        }()
        
        // Parse sats if provided (for BTC accounts)
        let satsAmount: Decimal? = {
            if satsAmountString.isEmpty {
                return nil
            }
            let cleaned = satsAmountString.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            guard let sats = Int(cleaned), sats > 0 else {
                return nil
            }
            return Decimal(sats) / 100_000_000 // Convert sats to BTC
        }()
        
        // Calculate BTC price if needed
        let btcPrice: Decimal? = {
            if !isBTCTransfer {
                return nil
            }
            if !btcPriceString.isEmpty {
                let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                return Decimal(string: cleanedPrice) ?? bitcoinPriceService.btcToUsdRate
            } else if let sats = satsAmount, sats > 0, amount > 0 {
                return amount / sats
            } else {
                return bitcoinPriceService.btcToUsdRate
            }
        }()
        
        // Create transfer title
        let transferTitle = "Transfer to \(toAccount.name ?? "Account")"
        
        // Create debit entry on from account (negative amount = debit)
        let totalDebitAmount = amount + (feeAmount ?? 0)
        if fromAccount.currencyCode == "BTC" {
            accountViewModel.addManualEntry(
                to: fromAccount,
                title: transferTitle,
                btcAmount: satsAmount.map { -$0 }, // Negative for debit
                usdAmount: -totalDebitAmount, // Negative for debit, include fee
                btcPriceAtTransaction: btcPrice,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: "Transfer",
                feeAmount: feeAmount
            )
        } else {
            accountViewModel.addManualEntry(
                to: fromAccount,
                title: transferTitle,
                btcAmount: nil,
                usdAmount: -totalDebitAmount, // Negative for debit, include fee
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: "Transfer",
                feeAmount: feeAmount
            )
        }
        
        // Create credit entry on to account (positive amount = credit)
        let toTransferTitle = "Transfer from \(fromAccount.name ?? "Account")"
        if toAccount.currencyCode == "BTC" {
            accountViewModel.addManualEntry(
                to: toAccount,
                title: toTransferTitle,
                btcAmount: satsAmount, // Positive for credit
                usdAmount: amount, // Positive for credit (fee not included on receiving side)
                btcPriceAtTransaction: btcPrice,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: "Transfer",
                feeAmount: nil
            )
        } else {
            accountViewModel.addManualEntry(
                to: toAccount,
                title: toTransferTitle,
                btcAmount: nil,
                usdAmount: amount, // Positive for credit
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: "Transfer",
                feeAmount: nil
            )
        }
        
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        accountViewModel.fetchAccounts()
        
        dismiss()
    }
}
