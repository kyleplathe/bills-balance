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

    let account: Account?
    let onSave: (String, String, Decimal, Bool, String, String, Decimal, Decimal?, Decimal?) -> Void

    @State private var name: String
    @State private var type: String
    @State private var startingBalance: String
    @State private var isHidden: Bool
    @State private var currency: String
    @State private var btcDisplayFormat: String
    @State private var feePercentage: String
    @State private var balanceInputFormat: String = "sats"
    @FocusState private var isBalanceFocused: Bool

    let accountTypes = ["checking", "savings", "credit", "cash", "investment", "digital wallet"]
    let currencies = ["USD", "BTC"]
    let btcDisplayFormats = ["sats", "bitcoin"]

    private var isBTCWallet: Bool {
        type.lowercased() == "digital wallet" && currency == "BTC"
    }

    private var balanceKind: MoneyKind {
        if isBTCWallet {
            return MoneyFormatting.kindForBTCDisplay(balanceInputFormat)
        }
        return .usd
    }

    private var parsedBalance: Decimal? {
        if startingBalance.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return MoneyFormatting.parse(startingBalance, kind: balanceKind)
    }

    private var parsedFee: Decimal? {
        if feePercentage.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return MoneyFormatting.parse(feePercentage, kind: .percent)
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, parsedBalance != nil, let fee = parsedFee else {
            return false
        }
        return fee >= 0 && fee <= 100
    }

    private var detailsFooter: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Account name is required"
        }
        if let fee = parsedFee, fee < 0 || fee > 100 {
            return "Fee percentage must be between 0 and 100"
        }
        if parsedFee == nil {
            return "Enter a valid fee percentage"
        }
        return nil
    }

    private var balanceFooter: String? {
        if parsedBalance == nil {
            return "Enter a valid opening balance"
        }
        return nil
    }

    init(account: Account?, onSave: @escaping (String, String, Decimal, Bool, String, String, Decimal, Decimal?, Decimal?) -> Void) {
        self.account = account
        self.onSave = onSave

        if let account {
            _name = State(initialValue: account.name ?? "")
            _type = State(initialValue: account.type ?? "cash")
            _isHidden = State(initialValue: account.isHiddenFlag)
            _currency = State(initialValue: account.currencyCode)
            _btcDisplayFormat = State(initialValue: account.btcDisplayFormat ?? "sats")
            if account.currencyCode == "BTC" {
                _balanceInputFormat = State(initialValue: account.btcDisplayFormat ?? "sats")
            }
            let fee = account.feePercentageDecimal
            _feePercentage = State(initialValue: fee == 0 ? "" : MoneyFormatting.format(fee, kind: .percent))

            if let balance = account.startingBalance, balance.decimalValue != 0 {
                let value = balance.decimalValue
                if account.currencyCode == "BTC" {
                    _startingBalance = State(initialValue: MoneyFormatting.displayString(forBTC: value, displayFormat: account.btcDisplayFormat ?? "sats"))
                } else {
                    _startingBalance = State(initialValue: MoneyFormatting.format(value, kind: .usd))
                }
            } else {
                _startingBalance = State(initialValue: "")
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

                    if type.lowercased() == "digital wallet" {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(.menu)

                        if currency == "BTC" {
                            Picker("Display Format", selection: $btcDisplayFormat) {
                                ForEach(btcDisplayFormats, id: \.self) { format in
                                    Text(format == "sats" ? "Sats" : "Bitcoin").tag(format)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: btcDisplayFormat) { oldValue, newValue in
                                balanceInputFormat = newValue
                                convertStartingBalanceToNewFormat(from: oldValue, to: newValue)
                            }
                        }

                        HStack {
                            Text("Fee Percentage")
                            Spacer(minLength: 12)
                            MoneyTextField(
                                text: $feePercentage,
                                kind: .percent,
                                placeholder: "0.000",
                                accessibilityLabel: "Fee percentage",
                                suffix: "%",
                                textAlignment: .trailing
                            )
                            .frame(maxWidth: 160)
                        }
                    }

                    if account != nil {
                        Toggle("Hide account", isOn: $isHidden)
                    }
                } header: {
                    Text("Account Details")
                } footer: {
                    if let detailsFooter {
                        Text(detailsFooter)
                    } else if account != nil {
                        Text("Hidden accounts are left out of Current Balance and the accounts list. Use Show Inactive Accounts to view them without adding them back to the total.")
                    }
                }

                Section {
                    if isBTCWallet {
                        Picker("", selection: $balanceInputFormat) {
                            Text("Sats").tag("sats")
                            Text("BTC").tag("bitcoin")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: balanceInputFormat) { oldValue, newValue in
                            btcDisplayFormat = newValue
                            convertStartingBalanceToNewFormat(from: oldValue, to: newValue)
                        }
                        .accessibilityLabel("Balance input format")
                    }

                    MoneyAmountHeader(
                        text: $startingBalance,
                        kind: balanceKind,
                        tone: .neutral,
                        accessibilityLabel: "Opening balance",
                        isFocused: $isBalanceFocused
                    )
                } header: {
                    Text("Opening Balance")
                } footer: {
                    if let balanceFooter {
                        Text(balanceFooter)
                    }
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    canSave: canSave,
                    onClose: { dismiss() },
                    onSave: saveAccount
                )
            }
        }
    }

    private func accountTypeDisplayName(for type: String) -> String {
        switch type.lowercased() {
        case "checking": return "Checking"
        case "savings": return "Savings"
        case "credit": return "Credit"
        case "cash": return "Cash"
        case "investment": return "Investment"
        case "digital wallet": return "Digital Wallet"
        default: return type.capitalized
        }
    }

    private func convertStartingBalanceToNewFormat(from oldFormat: String, to newFormat: String) {
        guard !startingBalance.isEmpty, oldFormat != newFormat else { return }
        guard let number = MoneyFormatting.parse(startingBalance, kind: MoneyFormatting.kindForBTCDisplay(oldFormat)), number > 0 else { return }

        if oldFormat == "sats" && newFormat == "bitcoin" {
            startingBalance = MoneyFormatting.format(MoneyFormatting.btc(fromSats: number), kind: .bitcoin)
        } else if oldFormat == "bitcoin" && newFormat == "sats" {
            startingBalance = MoneyFormatting.format(MoneyFormatting.sats(fromBTC: number), kind: .sats)
        }
    }

    private func saveAccount() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        var balanceDecimal = parsedBalance ?? 0
        if currency == "BTC" && balanceInputFormat == "sats" {
            balanceDecimal = MoneyFormatting.btc(fromSats: balanceDecimal)
        }
        let feeDecimal = parsedFee ?? 0
        onSave(trimmedName, type, balanceDecimal, isHidden, currency, btcDisplayFormat, feeDecimal, nil, nil)
        dismiss()
    }
}
