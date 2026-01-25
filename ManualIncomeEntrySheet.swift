//
//  ManualIncomeEntrySheet.swift
//  BillsAndBalance
//
//  Created on 1/2/25.
//

import SwiftUI

struct ManualIncomeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let date: Date
    
    @State private var selectedAccount: Account?
    @State private var title: String = ""
    @State private var amountString: String = ""
    @State private var notes: String = ""
    @State private var showValidationAlert = false
    @State private var validationMessage: String = ""
    
    private var currencyCode: String {
        selectedAccount?.currencyCode ?? "USD"
    }
    
    private var isBTCAccount: Bool {
        currencyCode == "BTC"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accountViewModel.accounts.filter { !($0.isHidden) }, id: \.objectID) { account in
                            Text(account.name ?? "Account").tag(account as Account?)
                        }
                    }
                } header: {
                    Text("Account")
                }
                
                Section {
                    TextField("Title", text: $title)
                        .placeholder(when: title.isEmpty) {
                            Text("Income Description")
                        }
                } header: {
                    Text("Description")
                }
                
                Section {
                    if isBTCAccount {
                        TextField("USD Amount", text: $amountString)
                            .keyboardType(.decimalPad)
                    } else {
                        TextField("Amount", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text(isBTCAccount ? "USD Amount" : "Amount")
                } footer: {
                    if isBTCAccount {
                        Text("For BTC accounts, enter the USD amount. The BTC value will be calculated using the current price when you reconcile.")
                    }
                }
                
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Add Pending Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveIncome()
                    }
                    .disabled(selectedAccount == nil || title.isEmpty || amountString.isEmpty)
                }
            }
            .alert("Validation Error", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .onAppear {
                if selectedAccount == nil && !accountViewModel.accounts.isEmpty {
                    selectedAccount = accountViewModel.accounts.first { !$0.isHidden }
                }
            }
        }
    }
    
    private func saveIncome() {
        guard let account = selectedAccount else {
            validationMessage = "Please select an account"
            showValidationAlert = true
            return
        }
        
        guard !title.isEmpty else {
            validationMessage = "Please enter a title"
            showValidationAlert = true
            return
        }
        
        let cleaned = amountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty,
              let amount = Decimal(string: cleaned),
              amount > 0 else {
            validationMessage = "Please enter a valid amount"
            showValidationAlert = true
            return
        }
        
        // Create pending income transaction (not reconciled)
        accountViewModel.addManualEntry(
            to: account,
            title: title,
            btcAmount: nil,
            usdAmount: amount,
            btcPriceAtTransaction: nil,
            date: date,
            notes: notes.isEmpty ? nil : notes,
            isReconciled: false,
            category: "Income"
        )
        
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        
        HapticManager.shared.success()
        dismiss()
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

