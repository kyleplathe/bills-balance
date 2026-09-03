//
//  ManageAccountsView.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import SwiftUI
import CoreData

struct ManageAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    
    @State private var showingAccountEditor = false
    @State private var accountToEdit: Account?
    @State private var showingClearBillsAlert = false
    @State private var showingClearIncomeAlert = false
    @State private var showingClearTransactionsAlert = false
    @State private var showingClearAllDataAlert = false
    @State private var showingClearSuccessAlert = false
    @State private var clearSuccessMessage = ""
    
    var body: some View {
        NavigationStack {
            formContent
        }
    }
    
    private var formContent: some View {
        Form {
            accountsSection
            dataManagementSection
        }
        .navigationTitle("Manage Accounts")
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
        }
        .modifier(AlertModifiers(
            showingClearBillsAlert: $showingClearBillsAlert,
            showingClearIncomeAlert: $showingClearIncomeAlert,
            showingClearTransactionsAlert: $showingClearTransactionsAlert,
            showingClearAllDataAlert: $showingClearAllDataAlert,
            showingClearSuccessAlert: $showingClearSuccessAlert,
            clearSuccessMessage: $clearSuccessMessage,
            billViewModel: billViewModel,
            paycheckViewModel: paycheckViewModel,
            accountViewModel: accountViewModel
        ))
        .sheet(isPresented: $showingAccountEditor) {
            AccountEditorSheet(account: accountToEdit) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage, startingBalanceUSD, startingBalanceBTCPrice in
                if let account = accountToEdit {
                    accountViewModel.updateAccount(account,
                                                   name: name,
                                                   type: type,
                                                   startingBalance: startingBalance,
                                                   isHidden: isHidden,
                                                   currency: currency,
                                                   btcDisplayFormat: btcDisplayFormat,
                                                   feePercentage: feePercentage,
                                                   startingBalanceUSD: startingBalanceUSD,
                                                   startingBalanceBTCPrice: startingBalanceBTCPrice)
                } else {
                    accountViewModel.addAccount(name: name,
                                                type: type,
                                                startingBalance: startingBalance,
                                                isHidden: isHidden,
                                                currency: currency,
                                                btcDisplayFormat: btcDisplayFormat,
                                                feePercentage: feePercentage,
                                                startingBalanceUSD: startingBalanceUSD,
                                                startingBalanceBTCPrice: startingBalanceBTCPrice)
                }
                accountViewModel.fetchAccounts()
            }
            .environmentObject(BitcoinPriceService.shared)
            .id(accountToEdit?.objectID) // Force recreation when account changes
        }
        .onAppear {
            accountViewModel.fetchAccounts()
        }
    }
    
    
    private var accountsSection: some View {
        Section {
            if accountViewModel.accounts.isEmpty {
                Text("Add accounts to track balances and link bills.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            ForEach(accountViewModel.accounts, id: \.objectID) { account in
                HStack {
                    Image(systemName: accountIcon(for: account.type ?? "other"))
                        .foregroundColor(.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name ?? "Account")
                            .font(.body)
                        Text(account.type?.capitalized ?? "Account")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        // Capture the account objectID to ensure we have the right account
                        let accountID = account.objectID
                        // Refresh the account from context to ensure we have latest data
                        if let context = account.managedObjectContext {
                            context.refresh(account, mergeChanges: true)
                            // Get the account again to ensure we have the latest version
                            if let refreshedAccount = context.object(with: accountID) as? Account {
                                accountToEdit = refreshedAccount
                            } else {
                                accountToEdit = account
                            }
                        } else {
                            accountToEdit = account
                        }
                        showingAccountEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
            }
            .onMove(perform: moveAccounts)
            .onDelete(perform: deleteAccounts)
            
            Button {
                accountToEdit = nil
                showingAccountEditor = true
            } label: {
                Label("Add Account", systemImage: "plus.circle")
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Accounts can be used for auto-pay bills and tracking balances.")
                .font(.footnote)
        }
    }
    
    private func accountIcon(for type: String) -> String {
        switch type.lowercased() {
        case "checking":
            return "building.columns"
        case "savings":
            return "banknote"
        case "credit":
            return "creditcard"
        case "cash":
            return "dollarsign.circle"
        case "investment":
            return "chart.line.uptrend.xyaxis"
        case "digital wallet":
            return "wallet.pass"
        default:
            return "building.columns"
        }
    }
    
    private func moveAccounts(from source: IndexSet, to destination: Int) {
        accountViewModel.reorderAccounts(from: source, to: destination)
    }
    
    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            accountViewModel.deleteAccount(accountViewModel.accounts[index])
        }
    }
    
    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showingClearBillsAlert = true
            } label: {
                Label("Clear All Bills", systemImage: "trash")
            }
            
            Button(role: .destructive) {
                showingClearIncomeAlert = true
            } label: {
                Label("Clear All Income", systemImage: "arrow.down.circle")
            }
            
            Button(role: .destructive) {
                showingClearTransactionsAlert = true
            } label: {
                Label("Clear All Transactions", systemImage: "list.bullet.rectangle")
            }
            
            Button(role: .destructive) {
                showingClearAllDataAlert = true
            } label: {
                Label("Clear All Data", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("Use these options to clear data. Clear All Data will remove bills, income, and transactions but keep your accounts.")
                .font(.footnote)
        }
    }
}

// MARK: - Alert Modifiers Helper
private struct AlertModifiers: ViewModifier {
    @Binding var showingClearBillsAlert: Bool
    @Binding var showingClearIncomeAlert: Bool
    @Binding var showingClearTransactionsAlert: Bool
    @Binding var showingClearAllDataAlert: Bool
    @Binding var showingClearSuccessAlert: Bool
    @Binding var clearSuccessMessage: String
    let billViewModel: BillViewModel
    let paycheckViewModel: PaycheckViewModel
    let accountViewModel: AccountViewModel
    
    func body(content: Content) -> some View {
        content
            .alert("Clear All Bills", isPresented: $showingClearBillsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    let result = billViewModel.clearAllBills()
                    clearSuccessMessage = result.message
                    showingClearSuccessAlert = true
                }
            } message: {
                Text("This will permanently delete all bills. This action cannot be undone.")
            }
            .alert("Clear All Income", isPresented: $showingClearIncomeAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    let result = paycheckViewModel.clearAllPaychecks()
                    clearSuccessMessage = result.message
                    showingClearSuccessAlert = true
                }
            } message: {
                Text("This will permanently delete all income entries. This action cannot be undone.")
            }
            .alert("Clear All Transactions", isPresented: $showingClearTransactionsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    let result = accountViewModel.clearAllLedgerEntries()
                    clearSuccessMessage = result.message
                    showingClearSuccessAlert = true
                }
            } message: {
                Text("This will permanently delete all transactions. Account balances will remain, but all transaction history will be lost. This action cannot be undone.")
            }
            .alert("Clear All Data", isPresented: $showingClearAllDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    let billsResult = billViewModel.clearAllBills()
                    let paychecksResult = paycheckViewModel.clearAllPaychecks()
                    let dataResult = accountViewModel.clearAllData(keepAccounts: true)
                    clearSuccessMessage = "\(billsResult.message). \(paychecksResult.message). \(dataResult.message)"
                    showingClearSuccessAlert = true
                }
            } message: {
                Text("This will permanently delete all bills, income, and transactions. Accounts will be kept but balances reset to $0. This action cannot be undone.")
            }
            .alert("Success", isPresented: $showingClearSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(clearSuccessMessage)
            }
    }
}