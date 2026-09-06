//
//  ManualTransactionEntrySheet.swift
//  BillsAndBalance
//
//  Unified add/edit transaction sheet.
//

import SwiftUI
import CoreData

struct TransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager

    private enum Mode {
        case create(Account)
        case edit(LedgerEntry)
    }

    private let mode: Mode

    @State private var title: String
    @State private var amountString: String
    @State private var feeAmountString: String
    @State private var satsAmountString: String
    @State private var btcPriceString: String
    @State private var isCredit: Bool
    @State private var category: String
    @State private var notes: String
    @State private var date: Date
    @State private var isCleared: Bool
    @State private var showBulkCategoryAlert = false
    @State private var bulkCategoryCount = 0
    @FocusState private var isAmountFocused: Bool

    init(account: Account) {
        mode = .create(account)
        _title = State(initialValue: "")
        _amountString = State(initialValue: "")
        _feeAmountString = State(initialValue: "")
        _satsAmountString = State(initialValue: "")
        _btcPriceString = State(initialValue: "")
        _isCredit = State(initialValue: false)
        _category = State(initialValue: "")
        _notes = State(initialValue: "")
        _date = State(initialValue: Date())
        _isCleared = State(initialValue: false)
    }

    init(entry: LedgerEntry) {
        mode = .edit(entry)
        _title = State(initialValue: entry.title ?? "")
        _isCredit = State(initialValue: entry.isCredit)
        _isCleared = State(initialValue: entry.isReconciledFlag)
        _notes = State(initialValue: entry.notes ?? "")
        _category = State(initialValue: entry.category ?? "")
        _date = State(initialValue: entry.date ?? Date())

        let absUSD = abs(entry.usdAmountDecimal)
        let fee = entry.feeAmountDecimal
        let principal: Decimal
        if fee > 0, fee < absUSD {
            principal = absUSD - fee
            _feeAmountString = State(initialValue: MoneyFormatting.format(fee, kind: .usd))
        } else {
            principal = absUSD
            _feeAmountString = State(initialValue: fee > 0 ? MoneyFormatting.format(fee, kind: .usd) : "")
        }
        if principal != .zero {
            _amountString = State(initialValue: MoneyFormatting.format(principal, kind: .usd))
        } else {
            let fallback = abs(entry.amountDecimal)
            _amountString = State(initialValue: fallback != .zero ? MoneyFormatting.format(fallback, kind: .usd) : "")
        }

        if let account = entry.account, account.currencyCode == "BTC" {
            let btc = abs(entry.btcAmountDecimal)
            if btc != .zero {
                _satsAmountString = State(initialValue: MoneyFormatting.displayString(forBTC: btc, displayFormat: account.btcDisplayFormat ?? "sats"))
            } else {
                _satsAmountString = State(initialValue: "")
            }
            let price = entry.btcPriceAtTransactionDecimal
            _btcPriceString = State(initialValue: price != .zero ? MoneyFormatting.format(price, kind: .usd) : "")
        } else {
            _satsAmountString = State(initialValue: "")
            _btcPriceString = State(initialValue: "")
        }
    }

    private var account: Account? {
        switch mode {
        case .create(let account): return account
        case .edit(let entry): return entry.account
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isBTCAccount: Bool {
        account?.currencyCode == "BTC"
    }

    private var parsedAmount: Decimal? {
        MoneyFormatting.parse(amountString, kind: .usd)
    }

    private var parsedFee: Decimal {
        MoneyFormatting.parse(feeAmountString, kind: .usd) ?? 0
    }

    private var totalUSD: Decimal? {
        guard let amount = parsedAmount, amount > 0 else { return nil }
        return amount + parsedFee
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount != nil
            && (parsedAmount ?? 0) > 0
    }

    private var amountFooter: String? {
        if amountString.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter an amount"
        }
        if parsedAmount == nil || (parsedAmount ?? 0) <= 0 {
            return "Enter a valid amount"
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a description"
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
                        showsDirectionPicker: true,
                        isCredit: $isCredit,
                        isFocused: $isAmountFocused
                    )
                    if isBTCAccount, let total = totalUSD {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(MoneyFormatting.currencyString(total))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    if let amountFooter {
                        Text(amountFooter)
                    }
                }
                .onChange(of: amountString) { _, _ in
                    if isBTCAccount { autoCalculateFee() }
                }

                if isBTCAccount {
                    Section {
                        MoneyTextField(
                            text: $feeAmountString,
                            kind: .usd,
                            placeholder: "Fee (optional)",
                            accessibilityLabel: "Fee"
                        )
                        if parsedFee > 0, let amount = parsedAmount, amount > 0 {
                            let percentage = (parsedFee / amount) * 100
                            Text("\(String(format: "%.3f", (percentage as NSDecimalNumber).doubleValue))% of amount")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } header: {
                        Text("Fee")
                    }
                }

                Section {
                    TextField("Description", text: $title)
                        .onChange(of: title) { _, newValue in
                            if category.isEmpty && !newValue.isEmpty {
                                let suggested = CategorySuggester.suggest(
                                    for: newValue,
                                    priorCategory: accountViewModel.suggestedCategory(forTitle: newValue, account: account)
                                )
                                if !suggested.isEmpty { category = suggested }
                            }
                        }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                }

                Section {
                    Toggle("Cleared", isOn: $isCleared)
                    NotesField(text: $notes)
                }

                if isBTCAccount {
                    Section {
                        MoneyTextField(
                            text: $satsAmountString,
                            kind: MoneyFormatting.kindForBTCDisplay(account?.btcDisplayFormat ?? "sats"),
                            placeholder: (account?.btcDisplayFormat ?? "sats") == "sats" ? "Sats (optional)" : "BTC (optional)",
                            accessibilityLabel: "Bitcoin amount",
                            suffix: (account?.btcDisplayFormat ?? "sats") == "sats" ? "sats" : nil
                        )
                        .onChange(of: satsAmountString) { _, _ in
                            autoCalculateBTCPrice()
                        }

                        HStack {
                            Text("BTC Price")
                            Spacer()
                            if !btcPriceString.isEmpty {
                                Text(MoneyFormatting.currencyString(MoneyFormatting.parse(btcPriceString) ?? 0))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("Pending until sats are entered")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Bitcoin")
                    } footer: {
                        Text("Optional: add sats when reconciling a pending transaction.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    canSave: canSave,
                    onClose: { dismiss() },
                    onSave: saveTransaction
                )
            }
            .interactiveDismissDisabled(isEditing)
            .onAppear {
                if !isEditing {
                    isAmountFocused = true
                }
            }
            .alert("Apply to All?", isPresented: $showBulkCategoryAlert) {
                Button("Just This One") {
                    finishSave()
                }
                Button("Apply to All (\(bulkCategoryCount))") {
                    accountViewModel.bulkSetCategory(category, forTitle: title)
                    finishSave()
                }
            } message: {
                Text("Set \(bulkCategoryCount) other \"\(title)\" transaction\(bulkCategoryCount == 1 ? "" : "s") to \"\(category)\" too?")
            }
        }
    }

    private func autoCalculateBTCPrice() {
        guard let total = totalUSD, total > 0 else {
            btcPriceString = ""
            return
        }
        let displayFormat = account?.btcDisplayFormat ?? "sats"
        guard let btcAmount = MoneyFormatting.btcAmount(fromInput: satsAmountString, displayFormat: displayFormat), btcAmount > 0 else {
            btcPriceString = ""
            return
        }
        btcPriceString = MoneyFormatting.format(total / btcAmount, kind: .usd)
    }

    private func autoCalculateFee() {
        guard let account, account.feePercentageDecimal > 0,
              let amount = parsedAmount, amount > 0 else { return }
        let roundedPercentage = roundFeePercentage(account.feePercentageDecimal)
        let calculatedFee = amount * (roundedPercentage / 100)
        feeAmountString = MoneyFormatting.format(calculatedFee, kind: .usd)
    }

    private func roundFeePercentage(_ percentage: Decimal) -> Decimal {
        let percentageDouble = (percentage as NSDecimalNumber).doubleValue
        let firstTwoDecimals = floor(percentageDouble * 100) / 100
        let thirdDigit = Int((percentageDouble * 1000).truncatingRemainder(dividingBy: 10))
        if thirdDigit >= 4 && thirdDigit <= 7 {
            return Decimal(firstTwoDecimals) + Decimal(5) / 1000
        }
        let rounded = (percentageDouble * 1000).rounded() / 1000
        return Decimal(rounded)
    }

    private func saveTransaction() {
        guard canSave, let amount = parsedAmount else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = category.isEmpty ? nil : category
        let signedPrincipal = isCredit ? amount : -amount
        let fee = parsedFee
        let total = amount + fee
        let signedTotal = isCredit ? total : -total

        switch mode {
        case .create(let account):
            saveNew(account: account, title: trimmedTitle, signedPrincipal: signedPrincipal, signedTotal: signedTotal, fee: fee, category: finalCategory)
        case .edit(let entry):
            saveEdit(entry: entry, title: trimmedTitle, signedPrincipal: signedPrincipal, signedTotal: signedTotal, fee: fee, category: finalCategory)
        }
    }

    private func saveNew(account: Account, title: String, signedPrincipal: Decimal, signedTotal: Decimal, fee: Decimal, category: String?) {
        if isBTCAccount {
            let satsAmount = MoneyFormatting.btcAmount(fromInput: satsAmountString, displayFormat: account.btcDisplayFormat ?? "sats")
            let btcPrice: Decimal? = {
                if let parsed = MoneyFormatting.parse(btcPriceString), parsed > 0 { return parsed }
                if let sats = satsAmount, sats > 0, let total = totalUSD, total > 0 {
                    return total / sats
                }
                return nil
            }()
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: satsAmount,
                usdAmount: signedTotal,
                btcPriceAtTransaction: btcPrice,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: category,
                feeAmount: fee > 0 ? fee : nil,
                isCreditOverride: isCredit
            )
        } else {
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: nil,
                usdAmount: signedPrincipal,
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: category,
                isCreditOverride: isCredit
            )
        }
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        accountViewModel.fetchAccounts()
        dismiss()
    }

    private func saveEdit(entry: LedgerEntry, title: String, signedPrincipal: Decimal, signedTotal: Decimal, fee: Decimal, category: String?) {
        guard let account else {
            dismiss()
            return
        }

        let btcAmount: Decimal? = {
            guard isBTCAccount else { return nil }
            guard let btc = MoneyFormatting.btcAmount(fromInput: satsAmountString, displayFormat: account.btcDisplayFormat ?? "sats") else { return nil }
            return isCredit ? btc : -btc
        }()

        let btcPrice: Decimal? = {
            guard isBTCAccount, let parsed = MoneyFormatting.parse(btcPriceString), parsed > 0 else { return nil }
            return parsed
        }()

        accountViewModel.updateLedgerEntry(
            entry,
            date: date,
            title: title,
            btcAmount: btcAmount,
            usdAmount: isBTCAccount ? signedTotal : signedPrincipal,
            btcPrice: btcPrice,
            isReconciled: isCleared,
            notes: notes.isEmpty ? nil : notes,
            category: category,
            feeAmount: fee > 0 ? fee : nil
        )

        let originalCategory = entry.category ?? ""
        let newCategory = category ?? ""
        if !newCategory.isEmpty, newCategory != originalCategory, !title.isEmpty {
            let matchCount = accountViewModel.countMatchingUncategorizedEntries(title: title, category: newCategory)
            if matchCount > 0 {
                bulkCategoryCount = matchCount
                showBulkCategoryAlert = true
                return
            }
        }

        finishSave()
    }

    private func finishSave() {
        accountViewModel.fetchAccounts()
        accountViewModel.saveContext()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
        }
        dismiss()
    }
}

typealias ManualTransactionEntrySheet = TransactionEditorSheet
