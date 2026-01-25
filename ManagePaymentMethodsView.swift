//
//  ManagePaymentMethodsView.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import SwiftUI
import CoreData

struct ManagePaymentMethodsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardManager: CreditCardManager
    @EnvironmentObject private var accountViewModel: AccountViewModel
    
    @State private var newCardName: String = ""
    @State private var editingCard: String?
    @State private var editedName: String = ""
    @State private var showingAccountEditor = false
    @State private var accountToEdit: Account?
    
    var body: some View {
        NavigationStack {
            Form {
                creditCardsSection
                accountsSection
            }
            .navigationTitle("Payment Methods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showingAccountEditor) {
                AccountEditorSheet(account: accountToEdit) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage in
                    if let account = accountToEdit {
                        accountViewModel.updateAccount(account,
                                                       name: name,
                                                       type: type,
                                                       startingBalance: startingBalance,
                                                       isHidden: isHidden,
                                                       currency: currency,
                                                       btcDisplayFormat: btcDisplayFormat,
                                                       feePercentage: feePercentage)
                    } else {
                        accountViewModel.addAccount(name: name,
                                                    type: type,
                                                    startingBalance: startingBalance,
                                                    isHidden: isHidden,
                                                    currency: currency,
                                                    btcDisplayFormat: btcDisplayFormat,
                                                    feePercentage: feePercentage)
                    }
                    accountViewModel.fetchAccounts()
                }
                .environmentObject(BitcoinPriceService.shared)
            }
            .sheet(item: Binding(
                get: { editingCard.map { CardIdentifier(name: $0) } },
                set: { editingCard = $0?.name }
            )) { _ in
                CreditCardEditorSheet(cardName: editingCard ?? "", editedName: $editedName) {
                    if let card = editingCard {
                        cardManager.renameCard(from: card, to: editedName)
                    }
                    editingCard = nil
                    editedName = ""
                } onCancel: {
                    editingCard = nil
                    editedName = ""
                }
            }
            .onAppear {
                accountViewModel.fetchAccounts()
            }
        }
    }
    
    private var creditCardsSection: some View {
        Section {
            if cardManager.cards.isEmpty {
                Text("Add credit cards to track which card you use for each bill.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            ForEach(cardManager.cards, id: \.self) { card in
                HStack {
                    Image(systemName: "creditcard")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text(card)
                    Spacer()
                    Button {
                        editingCard = card
                        editedName = card
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
            }
            .onMove(perform: moveCards)
            .onDelete(perform: deleteCards)
            
            HStack {
                TextField("Card name", text: $newCardName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button("Add") {
                    addCard()
                }
                .disabled(newCardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Credit Cards")
        }
    }
    
    private var accountsSection: some View {
        Section {
            if accountViewModel.accounts.isEmpty {
                Text("Add accounts to link bills and track balances.")
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
                        accountToEdit = account
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
    
    private func addCard() {
        cardManager.addCard(newCardName)
        newCardName = ""
    }
    
    private func moveCards(from source: IndexSet, to destination: Int) {
        cardManager.reorderCards(from: source, to: destination)
    }
    
    private func deleteCards(at offsets: IndexSet) {
        cardManager.removeCards(at: offsets)
    }
    
    private func moveAccounts(from source: IndexSet, to destination: Int) {
        accountViewModel.reorderAccounts(from: source, to: destination)
    }
    
    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            accountViewModel.deleteAccount(accountViewModel.accounts[index])
        }
    }
}

// MARK: - Card Identifier (for sheet binding)
private struct CardIdentifier: Identifiable {
    let id: String
    let name: String
    
    init(name: String) {
        self.name = name
        self.id = name
    }
}

// MARK: - Credit Card Editor Sheet
private struct CreditCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let cardName: String
    @Binding var editedName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Credit Card Name") {
                    TextField("Card name", text: $editedName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Credit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    let controller = PersistenceController.preview
    let accountVM = AccountViewModel(context: controller.container.viewContext)
    return ManagePaymentMethodsView()
        .environmentObject(CreditCardManager())
        .environmentObject(accountVM)
}
