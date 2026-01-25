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

    let fileName: String
    let transactions: [ParsedStatementTransaction]
    let onImport: (Account, [ParsedStatementTransaction]) -> Void

    private var usdAccounts: [Account] {
        accountViewModel.accounts.filter { !$0.isHiddenFlag && $0.currencyCode != "BTC" }
    }

    @State private var selectedAccount: Account?
    @State private var includedIds: Set<UUID> = []
    @State private var isImporting = false
    @State private var showNoAccountAlert = false

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if usdAccounts.isEmpty {
                        Text("No USD accounts. Add an account in Manage Accounts.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Account", selection: $selectedAccount) {
                            Text("Select…").tag(nil as Account?)
                            ForEach(usdAccounts, id: \.objectID) { acc in
                                Text(acc.name ?? "Account").tag(acc as Account?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Import into")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !fileName.isEmpty {
                            Text("From: \(fileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Transactions will be added as ledger entries. Credits (payments) and debits (purchases) are detected from the CSV. Export from your bank’s website (e.g. Chase, Amex, Citi) for best results.")
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

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title)
                                    .lineLimit(2)
                                Text(dateFormatter.string(from: tx.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(currencyFormatter.string(from: (tx.amount as NSDecimalNumber)) ?? "$0")
                                .foregroundStyle(tx.isCredit ? .green : .primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import Statement")
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
                    includedIds = Set(transactions.map(\.id))
                }
                if selectedAccount == nil {
                    selectedAccount = usdAccounts.first
                }
            }
            .alert("Select account", isPresented: $showNoAccountAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Choose an account to import into.")
            }
        }
    }

    func importTapped() {
        guard let account = selectedAccount else {
            showNoAccountAlert = true
            return
        }
        let toImport = selectedTransactions
        guard !toImport.isEmpty else { return }

        isImporting = true
        onImport(account, toImport)
        isImporting = false
        dismiss()
    }
}
