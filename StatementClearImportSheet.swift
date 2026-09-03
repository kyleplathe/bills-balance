//
//  StatementClearImportSheet.swift
//  BillsAndBalance
//
//  Pick a statement/Strike CSV and remove matching imported ledger rows.
//

import SwiftUI
import CoreData

struct StatementClearImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel

    let fileName: String
    let transactions: [ParsedStatementTransaction]
    let onClear: (Account, [ParsedStatementTransaction], Bool) -> Void

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
    @State private var isClearing = false
    @State private var showNoAccountAlert = false
    @State private var restoreBalance = true
    @State private var showConfirm = false

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

    private var matchedTransactions: [ParsedStatementTransaction] {
        guard let account = selectedAccount else { return [] }
        return accountViewModel.matchingImportEntries(for: transactions, account: account).map(\.transaction)
    }

    private var selectedTransactions: [ParsedStatementTransaction] {
        matchedTransactions.filter { includedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if availableAccounts.isEmpty {
                        Text("No accounts available.")
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
                    Toggle("Restore balance", isOn: $restoreBalance)
                } header: {
                    Text("Clear from")
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

                Section {
                    if selectedAccount == nil {
                        Text("Choose an account to find matching CSV lines.")
                            .foregroundStyle(.secondary)
                    } else if matchedTransactions.isEmpty {
                        Text("No matching imported transactions found in this account.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matchedTransactions) { tx in
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

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.title)
                                        .lineLimit(2)
                                    Text(subtitle(for: tx))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(currencyFormatter.string(from: (tx.amount as NSDecimalNumber)) ?? "$0")
                                    .foregroundStyle(tx.isCredit ? .green : .primary)
                            }
                        }
                    }
                } header: {
                    Text("Matching CSV lines (\(matchedTransactions.count))")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clear Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear \(selectedTransactions.count)") {
                        showConfirm = true
                    }
                    .disabled(selectedAccount == nil || selectedTransactions.isEmpty || isClearing)
                    .foregroundStyle(.red)
                }
            }
            .onAppear {
                if selectedAccount == nil {
                    selectedAccount = preferredAccount()
                }
                refreshSelection()
            }
            .onChange(of: selectedAccount) { _, _ in
                refreshSelection()
            }
            .alert("Select account", isPresented: $showNoAccountAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Choose an account to clear from.")
            }
            .confirmationDialog(
                "Clear \(selectedTransactions.count) imported transaction\(selectedTransactions.count == 1 ? "" : "s")?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Selected", role: .destructive) {
                    clearTapped()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(restoreBalance
                     ? "Matching ledger rows will be deleted and the starting balance adjustment from this import will be undone."
                     : "Matching ledger rows will be deleted. Starting balance will not be changed.")
            }
        }
    }

    private var footerText: String {
        var parts = [
            "Only CSV lines that already exist in the selected account are listed. Turn lines off to keep them."
        ]
        if restoreBalance {
            parts.append("Restore balance undoes the Keep current balance adjustment from this CSV (including the Strike USD-into-BTC import bug).")
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
            if let strike = availableAccounts.first(where: {
                ($0.name ?? "").localizedCaseInsensitiveContains("strike") && $0.currencyCode == "BTC"
            }) {
                return strike
            }
            if let btc = availableAccounts.first(where: { $0.currencyCode == "BTC" }) {
                return btc
            }
        }
        return availableAccounts.first
    }

    private func refreshSelection() {
        includedIds = Set(matchedTransactions.map(\.id))
    }

    private func subtitle(for tx: ParsedStatementTransaction) -> String {
        var parts = [dateFormatter.string(from: tx.date)]
        if let ref = tx.sourceReference, !ref.isEmpty {
            parts.append(String(ref.prefix(8)))
        }
        if let btc = tx.btcAmount, btc > 0 {
            parts.append("\(CSVSupport.formatDecimal(btc, fractionDigits: 8)) BTC")
        }
        return parts.joined(separator: " · ")
    }

    private func clearTapped() {
        guard let account = selectedAccount else {
            showNoAccountAlert = true
            return
        }
        let toClear = selectedTransactions
        guard !toClear.isEmpty else { return }
        isClearing = true
        onClear(account, toClear, restoreBalance)
        isClearing = false
        dismiss()
    }
}
