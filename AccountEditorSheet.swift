//
//  AccountEditorSheet.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI
import CoreData

struct AccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let account: Account?
    let onSave: (String, String, Decimal, Bool, String, String, Decimal, Decimal?, Decimal?) -> Void // USD and BTC price params kept for compatibility but not used
    
    @State private var name: String
    @State private var type: String
    @State private var startingBalance: String
    @State private var isHidden: Bool
    @State private var currency: String
    @State private var btcDisplayFormat: String
    @State private var feePercentage: String
    @State private var showValidationAlert = false
    @State private var validationMessage: String?
    @State private var balanceInputFormat: String = "sats" // "sats" or "bitcoin" for BTC starting balance input
    @FocusState private var isBalanceFocused: Bool
    
    let accountTypes = ["checking", "savings", "credit", "cash", "investment", "digital wallet"]
    let currencies = ["USD", "BTC"]
    let btcDisplayFormats = ["sats", "bitcoin"]
    
    // Formatters for balance input
    private var usdFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }
    
    private var satsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    private var btcFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter
    }
    
    init(account: Account?, onSave: @escaping (String, String, Decimal, Bool, String, String, Decimal, Decimal?, Decimal?) -> Void) {
        self.account = account
        self.onSave = onSave
        
        if let account = account {
            _name = State(initialValue: account.name ?? "")
            _type = State(initialValue: account.type ?? "cash")
            // Use empty string if balance is zero, otherwise show the formatted value
            // For BTC accounts, convert BTC to sats if display format is sats
            if let balance = account.startingBalance, balance.decimalValue != 0 {
                let balanceValue = balance.decimalValue
                if account.currencyCode == "BTC" {
                    let displayFormat = account.btcDisplayFormat ?? "sats"
                    if displayFormat == "sats" {
                        // Convert BTC to sats for display and format with commas
                        let sats = balanceValue * 100_000_000
                        let satsInt = (sats as NSDecimalNumber).intValue
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.groupingSeparator = ","
                        formatter.usesGroupingSeparator = true
                        formatter.maximumFractionDigits = 0
                        _startingBalance = State(initialValue: formatter.string(from: NSNumber(value: satsInt)) ?? sats.description)
                    } else {
                        // Display in BTC with formatting
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.groupingSeparator = ","
                        formatter.usesGroupingSeparator = true
                        formatter.minimumFractionDigits = 2
                        formatter.maximumFractionDigits = 8
                        _startingBalance = State(initialValue: formatter.string(from: balanceValue as NSDecimalNumber) ?? balanceValue.description)
                    }
                } else {
                    // Format USD with currency formatting
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .currency
                    formatter.currencyCode = "USD"
                    formatter.currencySymbol = "$"
                    formatter.maximumFractionDigits = 2
                    formatter.minimumFractionDigits = 2
                    formatter.usesGroupingSeparator = true
                    // Store without $ symbol for editing
                    let usdFormatter = NumberFormatter()
                    usdFormatter.numberStyle = .decimal
                    usdFormatter.groupingSeparator = ","
                    usdFormatter.usesGroupingSeparator = true
                    usdFormatter.maximumFractionDigits = 2
                    usdFormatter.minimumFractionDigits = 2
                    _startingBalance = State(initialValue: usdFormatter.string(from: balanceValue as NSDecimalNumber) ?? balanceValue.description)
                }
            } else {
                _startingBalance = State(initialValue: "")
            }
            
            _isHidden = State(initialValue: account.isHiddenFlag)
            _currency = State(initialValue: account.currencyCode)
            _btcDisplayFormat = State(initialValue: account.btcDisplayFormat ?? "sats")
            let fee = account.feePercentageDecimal
            // Use empty string if fee is zero, otherwise show the value
            _feePercentage = State(initialValue: fee == 0 ? "" : fee.description)
            // Initialize balance input format based on btcDisplayFormat for BTC accounts
            if account.currencyCode == "BTC" {
                _balanceInputFormat = State(initialValue: account.btcDisplayFormat ?? "sats")
            }
        } else {
            _name = State(initialValue: "")
            _type = State(initialValue: "cash")
            _startingBalance = State(initialValue: "")
            _isHidden = State(initialValue: false)
            _currency = State(initialValue: "USD")
            _btcDisplayFormat = State(initialValue: "sats")
            _feePercentage = State(initialValue: "")
            _balanceInputFormat = State(initialValue: "sats")
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    
                    Picker("Type", selection: $type) {
                        ForEach(accountTypes, id: \.self) { accountType in
                            Text(accountTypeDisplayName(for: accountType)).tag(accountType)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    // Currency picker shown for digital wallet accounts
                    if type.lowercased() == "digital wallet" {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        // Display Format only shown when BTC is selected
                        if currency == "BTC" {
                            Picker("Display Format", selection: $btcDisplayFormat) {
                                ForEach(btcDisplayFormats, id: \.self) { format in
                                    Text(format == "sats" ? "Sats" : "Bitcoin").tag(format)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: btcDisplayFormat) { oldValue, newValue in
                                // Sync balance input format with display format
                                balanceInputFormat = newValue
                                // Convert starting balance to match new format
                                convertStartingBalanceToNewFormat(from: oldValue, to: newValue)
                            }
                        }
                    }
                    
                    // Fee Percentage only for digital wallet accounts
                    if type.lowercased() == "digital wallet" {
                        HStack {
                            Text("Fee Percentage")
                            Spacer()
                            HStack(spacing: 4) {
                                ZStack(alignment: .trailing) {
                                    if feePercentage.isEmpty {
                                        Text("0.000")
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    TextField("", text: $feePercentage)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(minWidth: 60)
                                }
                                Text("%")
                            }
                        }
                    }
                    
                    // Hide account toggle only shown in Edit Account (not New Account)
                    if account != nil {
                        Toggle("Hide account", isOn: $isHidden)
                    }
                } header: {
                    Text("Account Details")
                } footer: {
                    if account != nil {
                        Text("Hidden accounts won't appear in the main balance view but can still be used for bills and transactions.")
                    }
                }
                
                Section {
                    // When BTC currency is selected, show toggle for Sats/BTC input format
                    if type.lowercased() == "digital wallet" && currency == "BTC" {
                        Picker("", selection: $balanceInputFormat) {
                            Text("Sats").tag("sats")
                            Text("BTC").tag("bitcoin")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: balanceInputFormat) { oldValue, newValue in
                            // Sync display format with input format
                            btcDisplayFormat = newValue
                            // Convert starting balance to match new format
                            convertStartingBalanceToNewFormat(from: oldValue, to: newValue)
                        }
                        
                        HStack {
                            Text("₿")
                                .foregroundStyle(.secondary)
                            ZStack(alignment: .leading) {
                                if startingBalance.isEmpty {
                                    Text(balanceInputFormat == "sats" ? "0" : "0.00000000")
                                        .foregroundColor(.secondary)
                                }
                                TextField("", text: $startingBalance)
                                    .keyboardType(balanceInputFormat == "sats" ? .numberPad : .decimalPad)
                                    .focused($isBalanceFocused)
                                    .onChange(of: isBalanceFocused) { oldValue, newValue in
                                        if !newValue {
                                            // Format when field loses focus
                                            formatBalanceOnBlur()
                                        }
                                    }
                            }
                            if balanceInputFormat == "sats" {
                                Text("sats")
                                    .foregroundStyle(.secondary)
                            }
                            if !startingBalance.isEmpty {
                                Button {
                                    startingBalance = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text("$")
                                .foregroundStyle(.secondary)
                            ZStack(alignment: .leading) {
                                if startingBalance.isEmpty {
                                    Text("0.00")
                                        .foregroundColor(.secondary)
                                }
                                TextField("", text: $startingBalance)
                                    .keyboardType(.decimalPad)
                                    .focused($isBalanceFocused)
                                    .onChange(of: isBalanceFocused) { oldValue, newValue in
                                        if !newValue {
                                            // Format when field loses focus
                                            formatBalanceOnBlur()
                                        }
                                    }
                            }
                            if !startingBalance.isEmpty {
                                Button {
                                    startingBalance = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Starting Balance")
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAccount()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Validation Error", isPresented: $showValidationAlert, presenting: validationMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
    }
    
    private func accountTypeDisplayName(for type: String) -> String {
        switch type.lowercased() {
        case "checking":
            return "Checking"
        case "savings":
            return "Savings"
        case "credit":
            return "Credit"
        case "cash":
            return "Cash"
        case "investment":
            return "Investment"
        case "digital wallet":
            return "Digital Wallet"
        default:
            return type.capitalized
        }
    }
    
    private func convertStartingBalanceToNewFormat(from oldFormat: String, to newFormat: String) {
        // Only convert if there's a value and formats are different
        guard !startingBalance.isEmpty, oldFormat != newFormat else { return }
        
        // Remove formatting characters
        let cleaned = startingBalance.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let number = Decimal(string: cleaned), number > 0 else { return }
        
        let convertedValue: Decimal
        let formatted: String
        
        if oldFormat == "sats" && newFormat == "bitcoin" {
            // Converting from sats to BTC
            convertedValue = number / 100_000_000
            formatted = btcFormatter.string(from: convertedValue as NSDecimalNumber) ?? convertedValue.description
        } else if oldFormat == "bitcoin" && newFormat == "sats" {
            // Converting from BTC to sats
            convertedValue = number * 100_000_000
            let satsInt = (convertedValue as NSDecimalNumber).intValue
            formatted = satsFormatter.string(from: NSNumber(value: satsInt)) ?? convertedValue.description
        } else {
            // No conversion needed
            return
        }
        
        startingBalance = formatted
    }
    
    private func formatBalanceOnBlur() {
        // Remove any formatting characters (commas, currency symbols)
        var cleaned = startingBalance.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        
        // Handle multiple decimal points - keep only the first one
        let components = cleaned.components(separatedBy: ".")
        if components.count > 2 {
            cleaned = components[0] + "." + components.dropFirst().joined()
        }
        
        // Parse the number
        guard let number = Decimal(string: cleaned), number > 0 else {
            if cleaned.isEmpty {
                startingBalance = ""
            }
            return
        }
        
        // Format based on currency and input format
        let formatted: String
        if type.lowercased() == "digital wallet" && currency == "BTC" {
            if balanceInputFormat == "sats" {
                // Format sats with commas, no decimals (value is already in sats)
                let satsInt = (number as NSDecimalNumber).intValue
                formatted = satsFormatter.string(from: NSNumber(value: satsInt)) ?? cleaned
            } else {
                // Format BTC with decimals and commas (value is already in BTC)
                formatted = btcFormatter.string(from: number as NSDecimalNumber) ?? cleaned
            }
        } else {
            // Format USD with currency symbol, commas, and 2 decimals
            formatted = usdFormatter.string(from: number as NSDecimalNumber) ?? cleaned
        }
        
        // Update the formatted value
        startingBalance = formatted
    }
    
    private func saveAccount() {
        // Validate name
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Account name is required."
            showValidationAlert = true
            return
        }
        
        // Validate starting balance (empty string is treated as 0)
        // Convert sats to BTC if needed
        let balanceDecimal: Decimal
        if startingBalance.isEmpty || startingBalance.trimmingCharacters(in: .whitespaces).isEmpty {
            balanceDecimal = 0
        } else {
            // Remove formatting characters (commas, currency symbols, etc.)
            let cleaned = startingBalance.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            guard let balance = Decimal(string: cleaned) else {
                validationMessage = "Please enter a valid starting balance."
                showValidationAlert = true
                return
            }
            // If BTC currency and input format is sats, convert to BTC
            // For USD currency (including USD digital wallets), store as USD
            if currency == "BTC" && balanceInputFormat == "sats" {
                balanceDecimal = balance / 100_000_000 // Convert sats to BTC
            } else {
                // For USD or BTC (bitcoin format), use the value as-is
                balanceDecimal = balance
            }
        }
        
        // Validate fee percentage (empty string is treated as 0)
        let feeDecimal: Decimal
        if feePercentage.isEmpty || feePercentage.trimmingCharacters(in: .whitespaces).isEmpty {
            feeDecimal = 0
        } else {
            guard let fee = Decimal(string: feePercentage), fee >= 0, fee <= 100 else {
                validationMessage = "Fee percentage must be between 0 and 100."
                showValidationAlert = true
                return
            }
            feeDecimal = fee
        }
        
        onSave(name, type, balanceDecimal, isHidden, currency, btcDisplayFormat, feeDecimal, nil, nil)
        dismiss()
    }
}
