//
//  ManageAccountsView.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct ManageAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var appLockManager: AppLockManager

    @State private var showingAccountEditor = false
    @State private var accountToEdit: Account?
    @State private var showingClearBillsAlert = false
    @State private var showingClearIncomeAlert = false
    @State private var showingClearTransactionsAlert = false
    @State private var showingClearAllDataAlert = false
    @State private var showingClearSuccessAlert = false
    @State private var clearSuccessMessage = ""
    @State private var showingImportPicker = false
    @State private var showClearImportedAlert = false
    @State private var showClearImportedSuccessAlert = false
    @State private var clearedImportCount = 0
    @State private var exportShareItem: ShareFileItem?
    @State private var exportErrorMessage: String?
    @State private var showExportErrorAlert = false
    @State private var importErrorMessage: String?
    @State private var showImportErrorAlert = false
    @State private var showImportSuccessAlert = false
    @State private var importedAccountCount = 0
    @State private var isImportParsing = false
    @State private var lockAuthError: String?
    @State private var showingPrivacyPolicy = false

    var body: some View {
        NavigationStack {
            formContent
        }
    }

    private var formContent: some View {
        Form {
            accountsSection
            backupSection
            privacySection
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
            .id(accountToEdit?.objectID)
        }
        .sheet(item: $exportShareItem) { item in
            ActivityShareSheet(activityItems: [item.url]) {
                try? FileManager.default.removeItem(at: item.url)
                exportShareItem = nil
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json, .plainText, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleBackupImport(result)
        }
        .overlay {
            if isImportParsing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Reading file…")
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .alert("Export Error", isPresented: $showExportErrorAlert, presenting: exportErrorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .alert("Import Error", isPresented: $showImportErrorAlert, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .alert("Import Successful", isPresented: $showImportSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Imported \(importedAccountCount) account\(importedAccountCount == 1 ? "" : "s"). Matching accounts were updated in place.")
        }
        .alert("Clear Imported Data", isPresented: $showClearImportedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Imported", role: .destructive) {
                clearedImportCount = accountViewModel.clearImportedEntries()
                showClearImportedSuccessAlert = true
            }
        } message: {
            Text("Imported transactions will be deleted and starting balances will be restored to before those imports (the Keep current balance adjustment is undone). This cannot be undone.")
        }
        .alert("Imported Data Cleared", isPresented: $showClearImportedSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(clearedImportCount == 0
                 ? "No imported transactions were found."
                 : "Removed \(clearedImportCount) imported transaction\(clearedImportCount == 1 ? "" : "s") and restored starting balances.")
        }
        .alert("Unable to Enable Lock", isPresented: Binding(
            get: { lockAuthError != nil },
            set: { if !$0 { lockAuthError = nil } }
        )) {
            Button("OK", role: .cancel) { lockAuthError = nil }
        } message: {
            Text(lockAuthError ?? "")
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
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
                        let accountID = account.objectID
                        if let context = account.managedObjectContext {
                            context.refresh(account, mergeChanges: true)
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

    private var backupSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
            }
            .disabled(accountViewModel.accounts.isEmpty)

            Button {
                showingImportPicker = true
            } label: {
                Label("Import Backup", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showClearImportedAlert = true
            } label: {
                Label("Clear Imported Data", systemImage: "trash")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Save to Files or iCloud Drive. Your data stays on this device until you export.")
                .font(.footnote)
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: lockBinding) {
                Label("Require Face ID", systemImage: "faceid")
            }
            Button {
                showingPrivacyPolicy = true
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: AppLegal.supportURL) {
                Label("Support", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Lock the app when you leave. Face ID or your device passcode unlocks it. This does not move data off the device.")
                .font(.footnote)
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { appLockManager.requireFaceID },
            set: { newValue in
                Task {
                    if let message = await appLockManager.setRequireFaceID(newValue) {
                        lockAuthError = message
                    }
                }
            }
        )
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

    private func exportBackup() {
        do {
            let url = try AccountExportService.writeExportFile(accounts: accountViewModel.accounts)
            exportShareItem = ShareFileItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportErrorAlert = true
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportParsing = true
            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AccountExportError.decodeFailed
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    let count = try accountViewModel.importAccounts(from: data)
                    await MainActor.run {
                        isImportParsing = false
                        importedAccountCount = count
                        showImportSuccessAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isImportParsing = false
                        importErrorMessage = error.localizedDescription
                        showImportErrorAlert = true
                    }
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportErrorAlert = true
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
