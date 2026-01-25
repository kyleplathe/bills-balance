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
    let onSave: (String, String, Decimal, Bool, String, String, Decimal) -> Void
    
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
    
    let accountTypes = ["checking", "savings", "credit", "cash", "investment", "digital wallet"]
    let currencies = ["USD", "BTC"]
    let btcDisplayFormats = ["sats", "bitcoin"]
    
    init(account: Account?, onSave: @escaping (String, String, Decimal, Bool, String, String, Decimal) -> Void) {
        self.account = account
        self.onSave = onSave
        
        if let account = account {
            _name = State(initialValue: account.name ?? "")
            _type = State(initialValue: account.type ?? "cash")
            // Use empty string if balance is zero, otherwise show the value
            // For BTC accounts, convert BTC to sats if display format is sats
            if let balance = account.startingBalance, balance.decimalValue != 0 {
                let balanceValue = balance.decimalValue
                if account.currencyCode == "BTC" {
                    let displayFormat = account.btcDisplayFormat ?? "sats"
                    if displayFormat == "sats" {
                        // Convert BTC to sats for display
                        let sats = balanceValue * 100_000_000
                        _startingBalance = State(initialValue: sats.description)
                    } else {
                        // Display in BTC
                        _startingBalance = State(initialValue: balanceValue.description)
                    }
                } else {
                    _startingBalance = State(initialValue: balanceValue.description)
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
                    
                    // Currency picker shown for digital wallet accounts
                    if type.lowercased() == "digital wallet" {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        
                        // Display Format only shown when BTC is selected
                        if currency == "BTC" {
                            Picker("Display Format", selection: $btcDisplayFormat) {
                                ForEach(btcDisplayFormats, id: \.self) { format in
                                    Text(format == "sats" ? "Sats" : "Bitcoin").tag(format)
                                }
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
                        
                        ZStack(alignment: .leading) {
                            if startingBalance.isEmpty {
                                Text(balanceInputFormat == "sats" ? "0" : "0.00")
                                    .foregroundColor(.secondary)
                            }
                            TextField("", text: $startingBalance)
                                .keyboardType(.decimalPad)
                        }
                    } else {
                        ZStack(alignment: .leading) {
                            if startingBalance.isEmpty {
                                Text("0.00")
                                    .foregroundColor(.secondary)
                            }
                            TextField("", text: $startingBalance)
                                .keyboardType(.decimalPad)
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
            guard let balance = Decimal(string: startingBalance) else {
                validationMessage = "Please enter a valid starting balance."
                showValidationAlert = true
                return
            }
            // If BTC currency and input format is sats, convert to BTC
            if currency == "BTC" && balanceInputFormat == "sats" {
                balanceDecimal = balance / 100_000_000 // Convert sats to BTC
            } else {
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
        
        onSave(name, type, balanceDecimal, isHidden, currency, btcDisplayFormat, feeDecimal)
        dismiss()
    }
}
