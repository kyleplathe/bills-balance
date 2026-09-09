//
//  StatementImportSheet.swift
//  BillsAndBalance
//
//  Review and import parsed credit card statement transactions into an account.
//

import SwiftUI
import CoreData

struct StatementImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager

    let fileName: String
    let transactions: [ParsedStatementTransaction]
    var initialAccount: Account? = nil
    let onImport: (Account, [ParsedStatementTransaction], Bool) -> Void

    private var isStrikeImport: Bool {
        transactions.contains { $0.kind != .generic }
    }

    private var availableAccounts: [Account] {
        let visible = accountViewModel.accounts.filter { !$0.isHiddenFlag }
        if isStrikeImport {
            return visible
        }
        return visible.filter { $0.currencyCode != "BTC" }
    }

    @State private var selectedAccount: Account?
    @State private var includedIds: Set<UUID> = []
    @State private var isImporting = false
    @State private var showNoAccountAlert = false
    @State private var keepCurrentBalance = true
    @State private var categoryOverrides: [UUID: String] = [:]
    @State private var editingCategoryTxId: UUID?
    @State private var workingTransactions: [ParsedStatementTransaction] = []
    @State private var originalTitles: [UUID: String] = [:]
    @State private var expandedTxId: UUID?
    @State private var applySimilarPrompt: ApplySimilarPrompt?
    @State private var dismissedTransferIds: Set<UUID> = []
    @State private var rewriteSuggestions: [StatementImportMatching.TitleRewriteSuggestion] = []
    @State private var selectedRewriteKeys: Set<String> = []
    @State private var rewritePromptDismissed = false

    private struct ApplySimilarPrompt: Identifiable {
        let id = UUID()
        let txId: UUID
        let similarCount: Int
        let title: String
        let category: String?
    }

    private struct PossibleTransferSuggestion: Identifiable {
        var id: UUID { txId }
        var txId: UUID
        var counterpartURI: String
        var counterpartAccountName: String
        var counterpartDate: Date
        var amount: Decimal
        var importTitle: String
        var isCredit: Bool
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    private var displayTransactions: [ParsedStatementTransaction] {
        workingTransactions.isEmpty ? transactions : workingTransactions
    }

    private var selectedTransactions: [ParsedStatementTransaction] {
        displayTransactions.filter { includedIds.contains($0.id) }
    }

    private var skipCount: Int {
        duplicateIndexes.count
    }

    private var duplicateIndexes: Set<Int> {
        guard let account = selectedAccount else { return [] }
        let existing = accountViewModel.existingImportEntries(for: account)
        var used = Set<Int>()
        var skipped = Set<Int>()
        for (idx, tx) in selectedTransactions.enumerated() {
            if let match = StatementImportMatching.matchingIndex(for: tx, in: existing, used: used) {
                used.insert(match)
                skipped.insert(idx)
            }
        }
        return skipped
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if availableAccounts.isEmpty {
                        Text(isStrikeImport
                             ? "No accounts. Add a Strike / digital wallet account in Manage Accounts."
                             : "No USD accounts. Add an account in Manage Accounts.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Account", selection: $selectedAccount) {
                            Text("Select…").tag(nil as Account?)
                            ForEach(availableAccounts, id: \.objectID) { acc in
                                Text(accountLabel(acc)).tag(acc as Account?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Toggle("Keep current balance", isOn: $keepCurrentBalance)
                } header: {
                    Text("Import into")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !fileName.isEmpty {
                            Text("From: \(fileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(footerText)
                    }
                }

                if !visibleRewriteSuggestions.isEmpty {
                    Section {
                        ForEach(visibleRewriteSuggestions) { suggestion in
                            knownRewriteRow(suggestion)
                        }
                        HStack {
                            Button("Skip") {
                                rewritePromptDismissed = true
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("Apply \(selectedRewriteKeys.count)") {
                                applySelectedRewrites()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedRewriteKeys.isEmpty)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Known description updates")
                    } footer: {
                        Text("These match descriptions you previously renamed. Apply them to this import, or skip to keep the statement text.")
                    }
                }

                if !possibleTransfers.isEmpty {
                    Section {
                        ForEach(possibleTransfers) { suggestion in
                            possibleTransferRow(suggestion)
                        }
                    } header: {
                        Text("Possible transfers")
                    } footer: {
                        Text("Matching amounts on another account within 3 days. Confirm to label both sides as a transfer instead of income or spending.")
                    }
                }

                Section(header: Text("Transactions (\(displayTransactions.count))")) {
                    ForEach(displayTransactions) { tx in
                        importTransactionRow(tx)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(isStrikeImport ? "Import Strike" : "Import Statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedTransactions.count)") {
                        importTapped()
                    }
                    .disabled(selectedAccount == nil || selectedTransactions.isEmpty || isImporting)
                }
            }
            .onAppear {
                if workingTransactions.isEmpty {
                    prepareWorkingTransactions()
                }
                if includedIds.isEmpty {
                    includedIds = Set(displayTransactions.filter(defaultIncluded).map(\.id))
                }
                if selectedAccount == nil {
                    selectedAccount = preferredAccount()
                }
            }
            .alert("Select account", isPresented: $showNoAccountAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Choose an account to import into.")
            }
            .alert("Apply to similar?", isPresented: Binding(
                get: { applySimilarPrompt != nil },
                set: { if !$0 { applySimilarPrompt = nil } }
            ), presenting: applySimilarPrompt) { prompt in
                Button("This item only", role: .cancel) {
                    persistRewrite(for: prompt.txId)
                    applySimilarPrompt = nil
                }
                Button("Apply to \(prompt.similarCount + 1)") {
                    applyToSimilar(prompt)
                }
            } message: { prompt in
                Text("Update \(prompt.similarCount) other row\(prompt.similarCount == 1 ? "" : "s") that match this amount or description.")
            }
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if isStrikeImport {
            parts.append("Bill pay rows are merged into one entry: USD amount, Strike fee, BTC sold, and BTC price. Re-importing the same file skips transactions already stored by Strike reference.")
        } else {
            parts.append("Transactions will be added as ledger entries. Credits (payments) and debits (purchases) are detected from the CSV. Export from your bank’s website (e.g. Chase, Amex, Citi) for best results.")
        }
        if skipCount > 0 {
            parts.append("\(skipCount) already in this account will be skipped.")
        }
        if keepCurrentBalance {
            parts.append("New rows will not change the current cleared balance.")
        }
        return parts.joined(separator: " ")
    }

    private func accountLabel(_ account: Account) -> String {
        let name = account.name ?? "Account"
        if account.currencyCode == "BTC" {
            return "\(name) (BTC)"
        }
        return name
    }

    private func preferredAccount() -> Account? {
        if let initialAccount, availableAccounts.contains(where: { $0.objectID == initialAccount.objectID }) {
            return initialAccount
        }
        if isStrikeImport {
            if let strike = availableAccounts.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("strike") && $0.currencyCode == "BTC" }) {
                return strike
            }
            if let btc = availableAccounts.first(where: { $0.currencyCode == "BTC" }) {
                return btc
            }
        } else if StatementImportMatching.prefersCreditAccount(fileName: fileName) {
            if let credit = availableAccounts.first(where: { ($0.type ?? "").lowercased() == "credit" }) {
                return credit
            }
        }
        return availableAccounts.first
    }

    private func defaultIncluded(_ tx: ParsedStatementTransaction) -> Bool {
        switch tx.kind {
        case .generic:
            return true
        case .billPay, .purchase, .sale, .send:
            return true
        case .receive:
            return (tx.btcAmount ?? 0) >= Decimal(string: "0.000001") ?? 0
        case .deposit, .withdrawal:
            return false
        }
    }

    private func subtitle(for tx: ParsedStatementTransaction) -> String {
        var parts = [dateFormatter.string(from: tx.date)]
        switch tx.kind {
        case .billPay:
            parts.append("Bill pay")
        case .purchase:
            parts.append("Buy BTC")
        case .sale:
            parts.append("Sell BTC")
        case .send:
            parts.append("Send")
        case .receive:
            parts.append("Receive")
        case .deposit:
            parts.append("Deposit")
        case .withdrawal:
            parts.append("Withdrawal")
        case .generic:
            break
        }
        if let fee = tx.feeUSD, fee > 0, let feeText = currencyFormatter.string(from: fee as NSDecimalNumber) {
            parts.append("Fee \(feeText)")
        }
        if let btc = tx.btcAmount, btc > 0 {
            parts.append("\(CSVSupport.formatDecimal(btc, fractionDigits: 8)) BTC")
        }
        return parts.joined(separator: " · ")
    }

    private var possibleTransfers: [PossibleTransferSuggestion] {
        guard let account = selectedAccount else { return [] }
        let counterparts = accountViewModel.transferCounterparts(excluding: account)
        var used = Set<Int>()
        var suggestions: [PossibleTransferSuggestion] = []
        let bitcoinAccount = account.currencyCode == "BTC"
        for tx in displayTransactions {
            guard !dismissedTransferIds.contains(tx.id) else { continue }
            guard tx.transferCounterpartURI == nil else { continue }
            let isCredit = StatementImportRunner.credit(for: tx, bitcoinAccount: bitcoinAccount)
            if let idx = StatementImportMatching.transferMatchIndex(
                usdAmount: tx.amount,
                btcAmount: tx.btcAmount,
                isCredit: isCredit,
                date: tx.date,
                in: counterparts,
                used: used
            ) {
                used.insert(idx)
                let match = counterparts[idx]
                suggestions.append(PossibleTransferSuggestion(
                    txId: tx.id,
                    counterpartURI: match.uri,
                    counterpartAccountName: match.accountName,
                    counterpartDate: match.date,
                    amount: tx.amount,
                    importTitle: tx.title,
                    isCredit: isCredit
                ))
            }
        }
        return suggestions
    }

    private var visibleRewriteSuggestions: [StatementImportMatching.TitleRewriteSuggestion] {
        rewritePromptDismissed ? [] : rewriteSuggestions
    }

    private func prepareWorkingTransactions() {
        let prepared = transactions
        var originals: [UUID: String] = [:]
        for i in prepared.indices {
            originals[prepared[i].id] = prepared[i].title
        }
        originalTitles = originals
        workingTransactions = prepared
        refreshRewriteSuggestions()
    }

    private func refreshRewriteSuggestions() {
        let suggestions = StatementImportMatching.pendingTitleRewrites(
            originalTitles: originalTitles,
            store: ImportTitleRewriteStore.all(),
            ledgerHints: StatementImportMatching.rewriteHints(from: accountViewModel.ledgerTitleRewriteSamples())
        )
        rewriteSuggestions = suggestions
        selectedRewriteKeys = Set(suggestions.map(\.normalizedOriginal))
        rewritePromptDismissed = suggestions.isEmpty
    }

    private func knownRewriteRow(_ suggestion: StatementImportMatching.TitleRewriteSuggestion) -> some View {
        Toggle(isOn: rewriteSelectedBinding(for: suggestion.normalizedOriginal)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(suggestion.originalTitle) → \(suggestion.preferredTitle)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(suggestion.matchCount) transaction\(suggestion.matchCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func rewriteSelectedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedRewriteKeys.contains(id) },
            set: { on in
                if on {
                    selectedRewriteKeys.insert(id)
                } else {
                    selectedRewriteKeys.remove(id)
                }
            }
        )
    }

    private func applySelectedRewrites() {
        for suggestion in rewriteSuggestions where selectedRewriteKeys.contains(suggestion.normalizedOriginal) {
            ImportTitleRewriteStore.save(
                originalTitle: suggestion.originalTitle,
                preferredTitle: suggestion.preferredTitle,
                category: suggestion.category
            )
            for id in suggestion.transactionIds {
                guard let i = workingTransactions.firstIndex(where: { $0.id == id }) else { continue }
                workingTransactions[i].title = suggestion.preferredTitle
                if let cat = suggestion.category, !cat.isEmpty {
                    workingTransactions[i].category = cat
                    categoryOverrides[id] = cat
                }
            }
        }
        rewriteSuggestions = []
        selectedRewriteKeys = []
        rewritePromptDismissed = true
    }

    @ViewBuilder
    private func possibleTransferRow(_ suggestion: PossibleTransferSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.importTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(suggestion.counterpartAccountName) · \(dateFormatter.string(from: suggestion.counterpartDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(currencyFormatter.string(from: suggestion.amount as NSDecimalNumber) ?? "$0")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.teal)
            }
            HStack {
                Button("Not a transfer") {
                    dismissedTransferIds.insert(suggestion.txId)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Confirm") {
                    confirmTransfer(suggestion)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private func confirmTransfer(_ suggestion: PossibleTransferSuggestion) {
        guard let idx = workingTransactions.firstIndex(where: { $0.id == suggestion.txId }) else { return }
        workingTransactions[idx].transferCounterpartURI = suggestion.counterpartURI
        workingTransactions[idx].category = LedgerTransfer.category
        categoryOverrides[suggestion.txId] = LedgerTransfer.category
        if suggestion.isCredit {
            workingTransactions[idx].title = LedgerTransfer.creditTitle(
                fromAccountName: suggestion.counterpartAccountName,
                fromIsCreditAccount: false
            )
        } else {
            workingTransactions[idx].title = LedgerTransfer.debitTitle(
                toAccountName: suggestion.counterpartAccountName,
                toIsCreditAccount: false
            )
        }
        includedIds.insert(suggestion.txId)
    }

    @ViewBuilder
    private func importTransactionRow(_ tx: ParsedStatementTransaction) -> some View {
        let isExpanded = expandedTxId == tx.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { includedIds.contains(tx.id) },
                    set: { on in
                        var next = includedIds
                        if on { next.insert(tx.id) } else { next.remove(tx.id) }
                        includedIds = next
                    }
                ))
                .labelsHidden()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTxId = isExpanded ? nil : tx.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tx.title)
                            .lineLimit(isExpanded ? 4 : 2)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(subtitle(for: tx))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !isExpanded {
                            importCategoryChip(for: tx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text(currencyFormatter.string(from: (tx.amount as NSDecimalNumber)) ?? "$0")
                    .foregroundStyle(tx.isCredit ? .green : .primary)
            }

            if isExpanded {
                TextField("Description", text: titleBinding(for: tx.id))
                    .textFieldStyle(.roundedBorder)
                TextField("Notes (optional)", text: notesBinding(for: tx.id), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                importCategoryChip(for: tx)
                let similarCount = similarIds(for: tx).count
                if similarCount > 0 {
                    Button {
                        promptApplySimilar(tx)
                    } label: {
                        Label("Apply to \(similarCount) similar", systemImage: "rectangle.stack")
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { workingTransactions.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let i = workingTransactions.firstIndex(where: { $0.id == id }) {
                    workingTransactions[i].title = newValue
                }
            }
        )
    }

    private func notesBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { workingTransactions.first(where: { $0.id == id })?.notes ?? "" },
            set: { newValue in
                if let i = workingTransactions.firstIndex(where: { $0.id == id }) {
                    workingTransactions[i].notes = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    private func similarIds(for tx: ParsedStatementTransaction) -> [UUID] {
        let original = originalTitles[tx.id] ?? tx.title
        return StatementImportMatching.similarTransactionIds(
            to: tx,
            originalTitle: original,
            in: displayTransactions,
            originalTitles: originalTitles
        )
    }

    private func promptApplySimilar(_ tx: ParsedStatementTransaction) {
        let similar = similarIds(for: tx)
        persistRewrite(for: tx.id)
        guard !similar.isEmpty else { return }
        applySimilarPrompt = ApplySimilarPrompt(
            txId: tx.id,
            similarCount: similar.count,
            title: tx.title,
            category: resolvedCategory(for: tx)
        )
    }

    private func applyToSimilar(_ prompt: ApplySimilarPrompt) {
        persistRewrite(for: prompt.txId)
        let source = displayTransactions.first(where: { $0.id == prompt.txId })
        let similar = source.map { similarIds(for: $0) } ?? []
        for id in similar {
            if let i = workingTransactions.firstIndex(where: { $0.id == id }) {
                workingTransactions[i].title = prompt.title
                if let cat = prompt.category {
                    workingTransactions[i].category = cat
                    categoryOverrides[id] = cat
                }
            }
        }
        applySimilarPrompt = nil
    }

    private func persistRewrite(for txId: UUID) {
        guard let original = originalTitles[txId],
              let tx = workingTransactions.first(where: { $0.id == txId })
        else { return }
        let cat = resolvedCategory(for: tx)
        ImportTitleRewriteStore.save(
            originalTitle: original,
            preferredTitle: tx.title,
            category: cat.isEmpty ? nil : cat
        )
    }

    // MARK: - Category suggestion helpers

    private func resolvedCategory(for tx: ParsedStatementTransaction) -> String {
        if let over = categoryOverrides[tx.id], !over.isEmpty { return over }
        if let existing = tx.category, !existing.isEmpty { return existing }
        let prior = accountViewModel.suggestedCategory(forTitle: tx.title)
        if let prior, !prior.isEmpty { return prior }
        return CategorySuggester.suggest(for: tx.title)
    }

    @ViewBuilder
    private func importCategoryChip(for tx: ParsedStatementTransaction) -> some View {
        let cat = resolvedCategory(for: tx)
        Button {
            editingCategoryTxId = tx.id
        } label: {
            HStack(spacing: 4) {
                if cat.isEmpty {
                    Image(systemName: "tag")
                        .font(.caption2)
                    Text("Add Category")
                        .font(.caption)
                } else {
                    Image(systemName: CategoryStyle.icon(for: cat))
                        .font(.caption2)
                        .foregroundStyle(CategoryStyle.color(for: cat))
                    Text(cat)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(cat.isEmpty ? Color(.tertiarySystemFill) : CategoryStyle.color(for: cat).opacity(0.12))
            )
            .foregroundStyle(cat.isEmpty ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { editingCategoryTxId == tx.id },
            set: { if !$0 { editingCategoryTxId = nil } }
        ), arrowEdge: .top) {
            ImportCategoryPickerPopover(
                currentCategory: cat,
                usage: accountViewModel.categoryUsage(),
                onSelect: { chosen in
                    categoryOverrides[tx.id] = chosen
                    if let i = workingTransactions.firstIndex(where: { $0.id == tx.id }) {
                        workingTransactions[i].category = chosen.isEmpty ? nil : chosen
                    }
                    persistRewrite(for: tx.id)
                    let similar = similarIds(for: tx)
                    for otherId in similar {
                        if categoryOverrides[otherId] == nil || categoryOverrides[otherId]?.isEmpty == true {
                            categoryOverrides[otherId] = chosen
                            if let i = workingTransactions.firstIndex(where: { $0.id == otherId }) {
                                workingTransactions[i].category = chosen.isEmpty ? nil : chosen
                            }
                        }
                    }
                    editingCategoryTxId = nil
                }
            )
            .environmentObject(categoryManager)
        }
    }

    func importTapped() {
        guard let account = selectedAccount else {
            showNoAccountAlert = true
            return
        }
        var toImport = selectedTransactions
        for i in toImport.indices {
            let cat = resolvedCategory(for: toImport[i])
            if !cat.isEmpty {
                toImport[i].category = cat
            }
        }
        guard !toImport.isEmpty else { return }

        for tx in workingTransactions {
            persistRewrite(for: tx.id)
        }

        isImporting = true
        onImport(account, toImport, keepCurrentBalance)
        isImporting = false
        dismiss()
    }
}

// MARK: - Import Category Picker Popover

struct ImportCategoryPickerPopover: View {
    let currentCategory: String
    let usage: [String: CategoryUsage]
    let onSelect: (String) -> Void
    @EnvironmentObject private var categoryManager: CategoryManager
    @State private var searchText = ""

    private var categories: [String] {
        let all = categoryManager.displayCategories(usage: usage, selected: currentCategory)
        if searchText.isEmpty { return all }
        let q = searchText.lowercased()
        return all.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !currentCategory.isEmpty {
                    Button {
                        onSelect("")
                    } label: {
                        Label("Remove Category", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                ForEach(categories, id: \.self) { cat in
                    Button {
                        onSelect(cat)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: CategoryStyle.icon(for: cat))
                                .foregroundStyle(CategoryStyle.color(for: cat))
                                .frame(width: 24)
                            Text(cat)
                                .foregroundStyle(.primary)
                            Spacer()
                            if cat == currentCategory {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search categories")
        }
        .frame(minWidth: 280, minHeight: 350)
    }
}

struct StatementImportResult {
    var importedCount: Int
    var matchedCount: Int
    var skippedCount: Int
    var keptBalance: Bool
}

@MainActor
enum StatementImportRunner {
    static func credit(for tx: ParsedStatementTransaction, bitcoinAccount: Bool) -> Bool {
        guard bitcoinAccount else { return tx.isCredit }
        switch tx.kind {
        case .purchase, .receive, .deposit:
            return true
        case .billPay, .sale, .send, .withdrawal:
            return false
        case .generic:
            return tx.isCredit
        }
    }

    static func importTransactions(
        account: Account,
        transactions: [ParsedStatementTransaction],
        keepCurrentBalance: Bool,
        accountViewModel: AccountViewModel,
        billViewModel: BillViewModel
    ) -> StatementImportResult {
        var importedCount = 0
        var matchedCount = 0
        var skippedCount = 0
        var importedForBalance: [ParsedStatementTransaction] = []
        let isBTC = account.currencyCode == "BTC"
        let existing = accountViewModel.existingImportEntries(for: account)
        var usedExisting = Set<Int>()
        var batchFingerprints: [StatementImportMatching.ExistingEntry] = []

        for tx in transactions {
            if let idx = StatementImportMatching.matchingIndex(for: tx, in: existing, used: usedExisting) {
                usedExisting.insert(idx)
                skippedCount += 1
                continue
            }
            if StatementImportMatching.matchingIndex(for: tx, in: batchFingerprints, used: []) != nil {
                skippedCount += 1
                continue
            }

            if isBTC, (tx.btcAmount ?? 0) <= 0 {
                skippedCount += 1
                continue
            }

            let notes: String = {
                if let custom = tx.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                    var lines = [custom]
                    if let ref = tx.sourceReference, !ref.isEmpty, !custom.contains(StrikeCSVParser.referenceNotePrefix) {
                        lines.append("\(StrikeCSVParser.referenceNotePrefix) \(ref)")
                    }
                    return lines.joined(separator: "\n")
                }
                if tx.kind == .billPay {
                    return StrikeCSVParser.notes(payee: tx.title, feeUSD: tx.feeUSD, reference: tx.sourceReference)
                }
                var lines = ["Imported from CSV"]
                if let fee = tx.feeUSD, fee > 0 {
                    lines.append("Strike fee: $\(CSVSupport.formatDecimal(fee, fractionDigits: 2))")
                }
                if let ref = tx.sourceReference, !ref.isEmpty {
                    lines.append("\(StrikeCSVParser.referenceNotePrefix) \(ref)")
                }
                return lines.joined(separator: "\n")
            }()

            if tx.transferCounterpartURI == nil,
               tx.kind == .billPay,
               let matched = BillPayMatcher.match(payee: tx.title, amount: tx.amount, on: tx.date, among: billViewModel.allBills()) {
                billViewModel.applyImportedPayment(
                    to: matched,
                    paidDate: tx.date,
                    usdAmount: tx.amount,
                    btcAmount: tx.btcAmount,
                    feeUSD: tx.feeUSD,
                    btcPrice: tx.btcPrice,
                    notes: notes
                )
                importedCount += 1
                matchedCount += 1
                importedForBalance.append(tx)
                rememberImported(tx, isBTC: isBTC, batch: &batchFingerprints)
                continue
            }

            let isCredit = credit(for: tx, bitcoinAccount: isBTC)
            let usdAmount = isCredit ? tx.amount : -tx.amount
            let signedBTC: Decimal? = {
                guard let btc = tx.btcAmount, btc > 0 else { return nil }
                return isCredit ? btc : -btc
            }()

            let category = tx.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = accountViewModel.addManualEntry(
                to: account,
                title: tx.title,
                btcAmount: signedBTC,
                usdAmount: usdAmount,
                btcPriceAtTransaction: tx.btcPrice,
                date: tx.date,
                notes: notes,
                isReconciled: true,
                category: (category?.isEmpty == false) ? category : nil,
                feeAmount: tx.feeUSD,
                isCreditOverride: isCredit,
                save: false
            )
            if let uri = tx.transferCounterpartURI, !uri.isEmpty {
                accountViewModel.pairImportedTransfer(created, counterpartURI: uri)
            }
            importedCount += 1
            importedForBalance.append(tx)
            rememberImported(tx, isBTC: isBTC, batch: &batchFingerprints)
        }

        if keepCurrentBalance {
            let netSigned = StatementImportMatching.keepBalanceNetSigned(
                transactions: importedForBalance,
                bitcoinAccount: isBTC,
                isCredit: { credit(for: $0, bitcoinAccount: isBTC) }
            )
            accountViewModel.applyStartingBalanceOffset(
                to: account,
                delta: StatementImportMatching.startingBalanceDelta(keepingCurrentBalance: netSigned)
            )
        }

        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        billViewModel.fetchBills(skipAutoPay: true)

        return StatementImportResult(
            importedCount: importedCount,
            matchedCount: matchedCount,
            skippedCount: skippedCount,
            keptBalance: keepCurrentBalance
        )
    }

    private static func rememberImported(
        _ tx: ParsedStatementTransaction,
        isBTC: Bool,
        batch: inout [StatementImportMatching.ExistingEntry]
    ) {
        batch.append(StatementImportMatching.ExistingEntry(
            date: tx.date,
            amount: tx.amount,
            title: tx.title,
            isCredit: credit(for: tx, bitcoinAccount: isBTC),
            sourceReference: tx.sourceReference
        ))
    }
}
