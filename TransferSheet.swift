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

    @State private var fromAccount: Account
    let allowsChangingSource: Bool

    @State private var toAccount: Account?
    @State private var amountString: String = ""
    @State private var feeAmountString: String = ""
    @State private var satsAmountString: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var isCleared: Bool = false
    @State private var transferError: String?
    @FocusState private var isAmountFocused: Bool

    init(fromAccount: Account, allowsChangingSource: Bool = false) {
        _fromAccount = State(initialValue: fromAccount)
        self.allowsChangingSource = allowsChangingSource
    }

    private var isBTCTransfer: Bool {
        fromAccount.currencyCode == "BTC" || toAccount?.currencyCode == "BTC"
    }

    private var sourceAccounts: [Account] {
        accountViewModel.accounts.filter { !$0.isHiddenFlag }
    }

    private var availableAccounts: [Account] {
        sourceAccounts.filter { $0.objectID != fromAccount.objectID }
    }

    private var parsedAmount: Decimal? {
        MoneyFormatting.parse(amountString, kind: .usd)
    }

    private var parsedFee: Decimal {
        MoneyFormatting.parse(feeAmountString, kind: .usd) ?? 0
    }

    private var canSave: Bool {
        toAccount != nil && (parsedAmount ?? 0) > 0
    }

    private var amountFooter: String? {
        if toAccount == nil {
            return "Choose a destination account"
        }
        if amountString.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter an amount"
        }
        if parsedAmount == nil || (parsedAmount ?? 0) <= 0 {
            return "Enter a valid amount"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyAmountHeader(
                        text: $amountString,
                        kind: .usd,
                        tone: .neutral,
                        isFocused: $isAmountFocused
                    )
                    if parsedFee > 0, let amount = parsedAmount {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(MoneyFormatting.currencyString(amount + parsedFee))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    if let amountFooter {
                        Text(amountFooter)
                    }
                }

                Section {
                    if allowsChangingSource {
                        Picker("From", selection: $fromAccount) {
                            ForEach(sourceAccounts, id: \.objectID) { account in
                                Text(account.name ?? "Account")
                                    .tag(account)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        LabeledContent("From", value: fromAccount.name ?? "Account")
                    }

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
                .onChange(of: fromAccount.objectID) { _, _ in
                    if toAccount?.objectID == fromAccount.objectID {
                        toAccount = nil
                    }
                }

                Section {
                    MoneyTextField(
                        text: $feeAmountString,
                        kind: .usd,
                        placeholder: "Fee (optional)",
                        accessibilityLabel: "Fee"
                    )
                    if isBTCTransfer {
                        MoneyTextField(
                            text: $satsAmountString,
                            kind: .sats,
                            placeholder: "0",
                            accessibilityLabel: "Sats",
                            suffix: "sats"
                        )
                    }
                } header: {
                    Text(isBTCTransfer ? "Bitcoin" : "Fee")
                }

                Section {
                    Toggle("Cleared", isOn: $isCleared)
                    NotesField(text: $notes)
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    saveTitle: "Transfer",
                    canSave: canSave,
                    onClose: { dismiss() },
                    onSave: saveTransfer
                )
            }
            .onAppear {
                isAmountFocused = true
            }
            .alert("Couldn't Transfer", isPresented: Binding(
                get: { transferError != nil },
                set: { if !$0 { transferError = nil } }
            )) {
                Button("OK", role: .cancel) { transferError = nil }
            } message: {
                Text(transferError ?? "")
            }
        }
    }

    private func saveTransfer() {
        guard let toAccount, let amount = parsedAmount, amount > 0 else { return }

        let feeAmount: Decimal? = parsedFee > 0 ? parsedFee : nil
        let satsAmount = MoneyFormatting.btcAmount(fromInput: satsAmountString, displayFormat: "sats")
        let btcPrice: Decimal? = {
            guard isBTCTransfer else { return nil }
            if let sats = satsAmount, sats > 0, amount > 0 {
                return amount / sats
            }
            return bitcoinPriceService.btcToUsdRate
        }()

        guard accountViewModel.transfer(
            from: fromAccount,
            to: toAccount,
            usdAmount: amount,
            feeAmount: feeAmount,
            btcAmount: satsAmount,
            btcPrice: btcPrice,
            date: date,
            notes: notes.isEmpty ? nil : notes,
            isCleared: isCleared
        ) != nil else {
            transferError = "Check the accounts and amount, then try again."
            return
        }

        dismiss()
    }
}

/// Chooses a source account, then presents `TransferSheet`. Used from the Balance menu.
struct TransferPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel

    private var sourceAccounts: [Account] {
        accountViewModel.accounts.filter { !$0.isHiddenFlag }
    }

    var body: some View {
        if let fromAccount = sourceAccounts.first {
            TransferSheet(fromAccount: fromAccount, allowsChangingSource: true)
        } else {
            NavigationStack {
                ContentUnavailableView("No Accounts", systemImage: "building.columns", description: Text("Add at least two accounts to transfer."))
                    .navigationTitle("Transfer From")
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
                            .accessibilityLabel("Close")
                        }
                    }
            }
        }
    }
}
