//
//  ManualTransactionEntrySheet.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI

struct ManualTransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    let account: Account
    
    @State private var title: String = ""
    @State private var amountString: String = ""
    @State private var isCredit: Bool = false
    @State private var category: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date()
    @State private var isCleared: Bool = false
    @State private var showValidationAlert = false
    @State private var validationMessage: String = ""
    
    private var isBTCAccount: Bool {
        account.currencyCode == "BTC"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)
                    
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    
                    Picker("", selection: $isCredit) {
                        Text("Add (+)").tag(true)
                        Text("Subtract (-)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    
                    Toggle("Cleared", isOn: $isCleared)
                }
                
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Validation Error", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private func saveTransaction() {
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
        
        // Determine the sign based on isCredit
        let signedAmount = isCredit ? amount : -amount
        
        // Create transaction entry
        let finalCategory = category.isEmpty ? nil : category
        
        if isBTCAccount {
            // For BTC accounts, store USD amount
            // BTC amount will be calculated when reconciled
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: nil,
                usdAmount: signedAmount,
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: finalCategory
            )
        } else {
            // For USD accounts, store USD amount
            accountViewModel.addManualEntry(
                to: account,
                title: title,
                btcAmount: nil,
                usdAmount: signedAmount,
                btcPriceAtTransaction: nil,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                isReconciled: isCleared,
                category: finalCategory
            )
        }
        
        accountViewModel.saveContext()
        accountViewModel.refreshLedgerEntries()
        accountViewModel.fetchAccounts()
        
        dismiss()
    }
}
