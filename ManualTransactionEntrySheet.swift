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
    private let originalCategory: String

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
    @State private var bulkMatchingCategory = ""
    @State private var bulkNewCategory: String?
    @State private var showMissingCategorySheet = false
    @State private var promptCategoryName = ""
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isTitleFocused: Bool

    init(account: Account) {
        mode = .create(account)
        originalCategory = ""
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
        originalCategory = entry.category ?? ""
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

    /// Previous payee names matching what the user has typed. Amount is never copied.
    private var titleSuggestions: [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        return accountViewModel.suggestedTitles(prefix: trimmed, limit: 5)
            .filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
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
                        .textInputAutocapitalization(.words)
                        .focused($isTitleFocused)
                        .onChange(of: title) { _, newValue in
                            applyRememberedCategory(for: newValue, overwrite: false)
                        }
                    if isTitleFocused, !titleSuggestions.isEmpty {
                        ForEach(titleSuggestions, id: \.self) { suggestion in
                            Button {
                                applyTitleSuggestion(suggestion)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(suggestion)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .accessibilityLabel("Use previous description \(suggestion)")
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
                    onSave: { saveTransaction() }
                )
            }
            .interactiveDismissDisabled(isEditing)
            .onAppear {
                if !isEditing {
                    isAmountFocused = true
                }
            }
            .sheet(isPresented: $showMissingCategorySheet) {
                TransactionCategoryPromptSheet(
                    categoryName: $promptCategoryName,
                    usage: accountViewModel.categoryUsage(),
                    onAdd: { name in
                        category = categoryManager.addCategory(name) ?? name
                        proceedWithSave(allowEmptyCategory: false)
                    },
                    onPick: { name in
                        category = name
                        proceedWithSave(allowEmptyCategory: false)
                    },
                    onSkip: {
                        proceedWithSave(allowEmptyCategory: true)
                    },
                    onCancel: {
                        showMissingCategorySheet = false
                    }
                )
                .environmentObject(categoryManager)
            }
            .alert("Apply to All?", isPresented: $showBulkCategoryAlert) {
                Button("Just This One") {
                    finishSave()
                }
                Button("Apply to All (\(bulkCategoryCount))") {
                    accountViewModel.bulkSetCategory(
                        bulkNewCategory,
                        forTitle: title,
                        matchingCategory: bulkMatchingCategory
                    )
                    finishSave()
                }
            } message: {
                if let name = bulkNewCategory, !name.isEmpty {
                    Text("Set \(bulkCategoryCount) other \"\(title)\" transaction\(bulkCategoryCount == 1 ? "" : "s") to \"\(name)\" too?")
                } else {
                    Text("Remove \"\(bulkMatchingCategory)\" from \(bulkCategoryCount) other \"\(title)\" transaction\(bulkCategoryCount == 1 ? "" : "s") too?")
                }
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

    private func applyRememberedCategory(for text: String, overwrite: Bool) {
        guard overwrite || category.isEmpty else { return }
        let suggested = CategorySuggester.suggest(
            for: text,
            priorCategory: accountViewModel.suggestedCategory(forTitle: text)
        )
        if !suggested.isEmpty { category = suggested }
    }

    private func applyTitleSuggestion(_ suggestion: String) {
        title = suggestion
        applyRememberedCategory(for: suggestion, overwrite: true)
        isTitleFocused = false
        HapticManager.shared.buttonTapped()
    }

    private func proceedWithSave(allowEmptyCategory: Bool) {
        showMissingCategorySheet = false
        DispatchQueue.main.async {
            saveTransaction(allowEmptyCategory: allowEmptyCategory)
        }
    }

    private func saveTransaction(allowEmptyCategory: Bool = false) {
        guard canSave, let amount = parsedAmount else { return }
        let isClearingAssignedCategory: Bool = {
            if case .edit = mode { return !originalCategory.isEmpty }
            return false
        }()
        if !allowEmptyCategory,
           category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isClearingAssignedCategory {
            promptCategoryName = ""
            showMissingCategorySheet = true
            return
        }
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

        ImportTitleRewriteStore.learn(
            fromNotes: notes.isEmpty ? nil : notes,
            preferredTitle: title,
            category: category
        )

        let newCategory = category ?? ""
        if newCategory != originalCategory, !title.isEmpty {
            let matchCount = accountViewModel.countEntries(withTitle: title, category: originalCategory)
            if matchCount > 0 {
                bulkCategoryCount = matchCount
                bulkMatchingCategory = originalCategory
                bulkNewCategory = newCategory.isEmpty ? nil : newCategory
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

/// Shown when saving a transaction with no category. Add one, pick an existing, or skip.
private struct TransactionCategoryPromptSheet: View {
    @Binding var categoryName: String
    let usage: [String: CategoryUsage]
    let onAdd: (String) -> Void
    let onPick: (String) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject private var categoryManager: CategoryManager
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCategories: [String] {
        let all = categoryManager.displayCategories(usage: usage)
        guard !trimmedName.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmedName) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category name", text: $categoryName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !trimmedName.isEmpty { onAdd(trimmedName) }
                        }
                } footer: {
                    Text("Add a category so this shows up clearly in Activity, or save without one.")
                }

                if !filteredCategories.isEmpty {
                    Section("Your Categories") {
                        ForEach(filteredCategories, id: \.self) { cat in
                            Button {
                                onPick(cat)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: CategoryStyle.icon(for: cat))
                                        .foregroundStyle(CategoryStyle.color(for: cat))
                                        .frame(width: 24)
                                    Text(cat)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Save Without Category", action: onSkip)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add a Category?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(trimmedName)
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .formEntryChrome()
    }
}

typealias ManualTransactionEntrySheet = TransactionEditorSheet
