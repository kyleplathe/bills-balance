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

    private var selectedTransactions: [ParsedStatementTransaction] {
        transactions.filter { includedIds.contains($0.id) }
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

                Section(header: Text("Transactions (\(transactions.count))")) {
                    ForEach(transactions) { tx in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { includedIds.contains(tx.id) },
                                set: { on in
                                    var next = includedIds
                                    if on { next.insert(tx.id) } else { next.remove(tx.id) }
                                    includedIds = next
                                }
                            ))
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(tx.title)
                                    .lineLimit(2)
                                Text(subtitle(for: tx))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                importCategoryChip(for: tx)
                            }

                            Spacer()

                            Text(currencyFormatter.string(from: (tx.amount as NSDecimalNumber)) ?? "$0")
                                .foregroundStyle(tx.isCredit ? .green : .primary)
                        }
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
                if includedIds.isEmpty {
                    includedIds = Set(transactions.filter(defaultIncluded).map(\.id))
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
                    // Also apply to all transactions with the same title
                    let normalizedTitle = tx.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    for other in transactions where other.id != tx.id {
                        if other.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedTitle {
                            if categoryOverrides[other.id] == nil || categoryOverrides[other.id]?.isEmpty == true {
                                categoryOverrides[other.id] = chosen
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
        // Apply category overrides + auto-suggestions to transactions before import
        var toImport = selectedTransactions
        for i in toImport.indices {
            let cat = resolvedCategory(for: toImport[i])
            if !cat.isEmpty {
                toImport[i].category = cat
            }
        }
        guard !toImport.isEmpty else { return }

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

            if tx.kind == .billPay,
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
            accountViewModel.addManualEntry(
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
                isCreditOverride: isCredit
            )
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
