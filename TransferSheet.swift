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
    @State private var bitcoinAmountString: String = ""
    @State private var amountEntryMode: AmountEntryMode = .usd
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var isCleared: Bool = false
    @State private var transferError: String?
    @FocusState private var isAmountFocused: Bool

    private enum AmountEntryMode: String, CaseIterable {
        case usd = "USD"
        case bitcoin = "BTC"
    }

    init(fromAccount: Account, allowsChangingSource: Bool = false) {
        _fromAccount = State(initialValue: fromAccount)
        self.allowsChangingSource = allowsChangingSource
    }

    private var isBTCTransfer: Bool {
        fromAccount.currencyCode == "BTC" || toAccount?.currencyCode == "BTC"
    }

    private var bitcoinDisplayFormat: String {
        if fromAccount.currencyCode == "BTC" {
            return fromAccount.btcDisplayFormat ?? "sats"
        }
        return toAccount?.btcDisplayFormat ?? "sats"
    }

    private var bitcoinKind: MoneyKind {
        MoneyFormatting.kindForBTCDisplay(bitcoinDisplayFormat)
    }

    private var sourceAccounts: [Account] {
        accountViewModel.accounts.filter { !$0.isHiddenFlag }
    }

    private var availableAccounts: [Account] {
        sourceAccounts.filter { $0.objectID != fromAccount.objectID }
    }

    private var parsedUSDAmount: Decimal? {
        if isBTCTransfer, amountEntryMode == .bitcoin {
            guard let btc = MoneyFormatting.btcAmount(fromInput: bitcoinAmountString, displayFormat: bitcoinDisplayFormat),
                  btc > 0 else { return nil }
            return btc * bitcoinPriceService.btcToUsdRate
        }
        return MoneyFormatting.parse(amountString, kind: .usd)
    }

    private var parsedBTCAmount: Decimal? {
        guard isBTCTransfer else { return nil }
        if amountEntryMode == .bitcoin {
            return MoneyFormatting.btcAmount(fromInput: bitcoinAmountString, displayFormat: bitcoinDisplayFormat)
        }
        guard let usd = MoneyFormatting.parse(amountString, kind: .usd), usd > 0 else { return nil }
        let rate = bitcoinPriceService.btcToUsdRate
        guard rate > 0 else { return nil }
        return usd / rate
    }

    private var parsedFee: Decimal {
        MoneyFormatting.parse(feeAmountString, kind: .usd) ?? 0
    }

    private var canSave: Bool {
        guard toAccount != nil, let usd = parsedUSDAmount, usd > 0 else { return false }
        if isBTCTransfer {
            guard let btc = parsedBTCAmount, btc > 0 else { return false }
        }
        return true
    }

    private var amountFooter: String? {
        if toAccount == nil {
            return "Choose a destination account"
        }
        if isBTCTransfer, amountEntryMode == .bitcoin {
            if bitcoinAmountString.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Enter a \(bitcoinDisplayFormat == "sats" ? "sats" : "BTC") amount"
            }
            if parsedBTCAmount == nil || (parsedBTCAmount ?? 0) <= 0 {
                return "Enter a valid \(bitcoinDisplayFormat == "sats" ? "sats" : "BTC") amount"
            }
            return nil
        }
        if amountString.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter an amount"
        }
        if parsedUSDAmount == nil || (parsedUSDAmount ?? 0) <= 0 {
            return "Enter a valid amount"
        }
        if isBTCTransfer, parsedBTCAmount == nil || (parsedBTCAmount ?? 0) <= 0 {
            return "Bitcoin amount could not be calculated"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isBTCTransfer {
                        Picker("Amount unit", selection: $amountEntryMode) {
                            ForEach(AmountEntryMode.allCases, id: \.self) { mode in
                                Text(mode == .bitcoin
                                     ? (bitcoinDisplayFormat == "sats" ? "Sats" : "BTC")
                                     : "USD")
                                .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Transfer amount unit")
                    }

                    if isBTCTransfer, amountEntryMode == .bitcoin {
                        MoneyAmountHeader(
                            text: $bitcoinAmountString,
                            kind: bitcoinKind,
                            tone: .neutral,
                            isFocused: $isAmountFocused
                        )
                        if let usd = parsedUSDAmount, usd > 0 {
                            Text("≈ \(MoneyFormatting.currencyString(usd))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else {
                        MoneyAmountHeader(
                            text: $amountString,
                            kind: .usd,
                            tone: .neutral,
                            isFocused: $isAmountFocused
                        )
                        if isBTCTransfer, let btc = parsedBTCAmount, btc > 0 {
                            Text("≈ \(MoneyFormatting.displayString(forBTC: btc, displayFormat: bitcoinDisplayFormat))\(bitcoinDisplayFormat == "sats" ? " sats" : " BTC")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    if parsedFee > 0, let amount = parsedUSDAmount {
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
                    syncAmountModeForAccounts()
                }
                .onChange(of: toAccount?.objectID) { _, _ in
                    syncAmountModeForAccounts()
                }

                Section {
                    MoneyTextField(
                        text: $feeAmountString,
                        kind: .usd,
                        placeholder: "Fee (optional)",
                        accessibilityLabel: "Transfer fee"
                    )
                } header: {
                    Text("Fee")
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
                syncAmountModeForAccounts()
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

    private func syncAmountModeForAccounts() {
        if isBTCTransfer {
            if fromAccount.currencyCode == "BTC" || toAccount?.currencyCode == "BTC" {
                // Prefer sats/BTC entry when a digital wallet BTC account is involved.
                if amountEntryMode == .usd,
                   (fromAccount.isBitcoinDigitalWallet || toAccount?.isBitcoinDigitalWallet == true) {
                    amountEntryMode = .bitcoin
                }
            }
        } else {
            amountEntryMode = .usd
        }
    }

    private func saveTransfer() {
        guard let toAccount, let amount = parsedUSDAmount, amount > 0 else { return }

        let feeAmount: Decimal? = parsedFee > 0 ? parsedFee : nil
        let btcAmount = parsedBTCAmount
        let btcPrice: Decimal? = {
            guard isBTCTransfer, let btc = btcAmount, btc > 0 else { return nil }
            return amount / btc
        }()

        if isBTCTransfer, btcAmount == nil || (btcAmount ?? 0) <= 0 {
            transferError = "Enter a BTC or sats amount for this transfer."
            return
        }

        guard accountViewModel.transfer(
            from: fromAccount,
            to: toAccount,
            usdAmount: amount,
            feeAmount: feeAmount,
            btcAmount: btcAmount,
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
