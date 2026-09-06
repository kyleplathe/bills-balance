import SwiftUI

struct PaycheckEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    
    let paycheck: Paycheck?
    let occurrenceDate: Date? // Optional: if editing a specific occurrence
    
    @State private var name: String
    @State private var amount: String
    @State private var firstDepositDate: Date
    @State private var recurrenceType: String
    @State private var recurrenceInterval: Int
    @State private var autoReconcile: Bool
    @State private var notes: String
    @State private var selectedAccountID: UUID?
    @State private var showUpdateScopeAlert = false
    @State private var pendingSaveData: (name: String, amount: Decimal, account: Account)?
    @State private var showDeleteScopeAlert = false
    @FocusState private var isAmountFocused: Bool

    enum DeleteScope {
        case thisOccurrenceOnly
        case allFutureOccurrences
    }

    private var parsedAmount: Decimal? {
        MoneyFormatting.parse(amount, kind: .usd)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedAmount ?? 0) > 0
            && accountViewModel.account(with: selectedAccountID) != nil
    }

    private var amountFooter: String? {
        if amount.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter an amount"
        }
        if parsedAmount == nil || (parsedAmount ?? 0) <= 0 {
            return "Enter a valid amount"
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a name"
        }
        if accountViewModel.account(with: selectedAccountID) == nil {
            return "Select an account"
        }
        return nil
    }
    
    init(paycheck: Paycheck? = nil, defaultDate: Date? = nil, occurrenceDate: Date? = nil) {
        self.paycheck = paycheck
        self.occurrenceDate = occurrenceDate
        _name = State(initialValue: paycheck?.name ?? "")
        if let amountValue = paycheck?.amount?.decimalValue, amountValue != 0 {
            _amount = State(initialValue: MoneyFormatting.format(amountValue, kind: .usd))
        } else {
            _amount = State(initialValue: "")
        }
        let initialDate = occurrenceDate ?? paycheck?.firstDepositDate ?? defaultDate ?? Date()
        _firstDepositDate = State(initialValue: initialDate)
        _recurrenceType = State(initialValue: paycheck?.recurrenceType ?? "none")
        let loadedInterval = max(Int(paycheck?.recurrenceInterval ?? 1), 1)
        // Set fixed intervals for non-weekly types (matching bills behavior)
        let initialInterval: Int
        if let existingType = paycheck?.recurrenceType {
            switch existingType {
            case "daily":
                // Keep loaded interval, but clamp to valid range (1-365)
                initialInterval = min(max(loadedInterval, 1), 365)
            case "weekly":
                // Keep loaded interval, but clamp to valid range (1-52)
                initialInterval = min(max(loadedInterval, 1), 52)
            case "monthly", "quarterly", "semiannually", "yearly":
                initialInterval = 1
            default:
                initialInterval = 1
            }
        } else {
            initialInterval = 1
        }
        _recurrenceInterval = State(initialValue: initialInterval)
        _autoReconcile = State(initialValue: paycheck?.autoReconcile ?? true)
        _notes = State(initialValue: paycheck?.notes ?? "")
        _selectedAccountID = State(initialValue: paycheck?.account?.id)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyAmountHeader(
                        text: $amount,
                        kind: .usd,
                        tone: .inflow,
                        isFocused: $isAmountFocused
                    )
                } footer: {
                    if let amountFooter {
                        Text(amountFooter)
                    }
                }

                Section {
                    TextField("Name", text: $name)
                    DatePicker("First Deposit", selection: $firstDepositDate, displayedComponents: .date)
                    if accountViewModel.accounts.isEmpty {
                        Text("Add an account in the Balance tab first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Account", selection: Binding(get: {
                            selectedAccountID ?? accountViewModel.selectedAccount?.id
                        }, set: { newValue in
                            selectedAccountID = newValue
                        })) {
                            Text("None").tag(UUID?.none)
                            ForEach(accountViewModel.accounts, id: \.id) { account in
                                Text(account.name ?? "Account").tag(account.id)
                            }
                        }
                    }
                    RecurrenceFields(
                        recurrenceType: $recurrenceType,
                        recurrenceInterval: $recurrenceInterval,
                        noneLabel: "One-time"
                    )
                }

                Section {
                    Toggle("Auto-Reconcile", isOn: $autoReconcile)
                    NotesField(text: $notes)
                }
            }
            .navigationTitle(paycheck == nil ? "New Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    canSave: canSave,
                    showDelete: paycheck != nil,
                    onClose: { dismiss() },
                    onSave: savePaycheck,
                    onDelete: { showDeleteScopeAlert = true }
                )
            }
            .onAppear {
                accountViewModel.fetchAccounts()
                if selectedAccountID == nil {
                    selectedAccountID = accountViewModel.selectedAccount?.id
                }
                if paycheck == nil {
                    isAmountFocused = true
                }
            }
            .alert("Update Scope", isPresented: $showUpdateScopeAlert) {
                if occurrenceDate != nil {
                    // Editing a specific occurrence
                    Button("This Occurrence Only", role: .none) {
                        if let data = pendingSaveData {
                            updateThisOccurrenceOnly(name: data.name, amount: data.amount, account: data.account)
                        }
                    }
                    Button("This and Future Occurrences", role: .none) {
                        if let data = pendingSaveData {
                            updateAllOccurrences(name: data.name, amount: data.amount, account: data.account)
                        }
                    }
                } else {
                    // Editing the template
                    Button("This Income Only", role: .none) {
                        if let data = pendingSaveData {
                            updateThisPaycheckOnly(name: data.name, amount: data.amount, account: data.account)
                        }
                    }
                    Button("This and Future Income", role: .none) {
                        if let data = pendingSaveData {
                            updateAllOccurrences(name: data.name, amount: data.amount, account: data.account)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingSaveData = nil
                }
            } message: {
                if occurrenceDate != nil {
                    Text("Do you want to update just this occurrence's transaction, or update the income template for all future occurrences?")
                } else {
                    Text("Do you want to update just this income, or update the template for all future income?")
                }
            }
            .alert("Delete Scope", isPresented: $showDeleteScopeAlert) {
                if occurrenceDate != nil {
                    // Deleting a specific occurrence
                    Button("This Occurrence Only", role: .destructive) {
                        deletePaycheck(scope: .thisOccurrenceOnly)
                    }
                    Button("This and Future Occurrences", role: .destructive) {
                        deletePaycheck(scope: .allFutureOccurrences)
                    }
                } else {
                    // Deleting the template
                    Button("This Income Only", role: .destructive) {
                        deletePaycheck(scope: .thisOccurrenceOnly)
                    }
                    Button("This and Future Income", role: .destructive) {
                        deletePaycheck(scope: .allFutureOccurrences)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if occurrenceDate != nil {
                    Text("Do you want to delete just this occurrence's transaction, or delete all future occurrences?")
                } else {
                    Text("Do you want to delete just this income, or delete the template and all future income?")
                }
            }
        }
    }

    private func savePaycheck() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let amountDecimal = parsedAmount, amountDecimal > 0 else { return }
        guard let account = accountViewModel.account(with: selectedAccountID) else { return }
        
        // If editing an existing paycheck, always ask for scope
        if paycheck != nil {
            // If editing a specific occurrence, ask if they want to update just that occurrence or all future
            if occurrenceDate != nil {
                pendingSaveData = (trimmedName, amountDecimal, account)
                showUpdateScopeAlert = true
                return
            } else {
                // If editing the template, ask if they want to update all future occurrences
                // (for non-recurring paychecks, this is just a normal update)
                if recurrenceType != "none" {
                    pendingSaveData = (trimmedName, amountDecimal, account)
                    showUpdateScopeAlert = true
                    return
                }
            }
        }
        
        // Otherwise, proceed with normal save
        let recurrence = recurrenceType == "none" ? "none" : recurrenceType
        if let paycheck {
            paycheckViewModel.updatePaycheck(paycheck,
                                             name: trimmedName,
                                             amount: amountDecimal,
                                             firstDepositDate: firstDepositDate,
                                             recurrenceType: recurrence,
                                             recurrenceInterval: recurrence == "none" ? 0 : recurrenceInterval,
                                             autoReconcile: autoReconcile,
                                             notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                             account: account)
        } else {
            paycheckViewModel.addPaycheck(name: trimmedName,
                                          amount: amountDecimal,
                                          firstDepositDate: firstDepositDate,
                                          recurrenceType: recurrence,
                                          recurrenceInterval: recurrence == "none" ? 0 : recurrenceInterval,
                                          autoReconcile: autoReconcile,
                                          notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                          account: account)
        }
        dismiss()
    }
    
    private func updateThisOccurrenceOnly(name: String, amount: Decimal, account: Account) {
        guard let paycheck = paycheck, let occurrenceDate = occurrenceDate else {
            dismiss()
            return
        }
        
        // Find and update the ledger entry for this specific occurrence
        accountViewModel.updatePaycheckOccurrenceTransaction(
            paycheck: paycheck,
            occurrenceDate: occurrenceDate,
            name: name,
            amount: amount,
            account: account
        )
        
        dismiss()
    }
    
    private func updateThisPaycheckOnly(name: String, amount: Decimal, account: Account) {
        guard let paycheck = paycheck else {
            dismiss()
            return
        }
        
        // Update only this income template without affecting future occurrences
        // This is essentially the same as updateAllOccurrences for non-recurring income
        // but for recurring ones, we'd need to create a new template
        // For now, we'll just update the template (same behavior as before)
        let recurrence = recurrenceType == "none" ? "none" : recurrenceType
        paycheckViewModel.updatePaycheck(paycheck,
                                         name: name,
                                         amount: amount,
                                         firstDepositDate: firstDepositDate,
                                         recurrenceType: recurrence,
                                         recurrenceInterval: recurrence == "none" ? 0 : recurrenceInterval,
                                         autoReconcile: autoReconcile,
                                         notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                         account: account)
        
        dismiss()
    }
    
    private func updateAllOccurrences(name: String, amount: Decimal, account: Account) {
        guard let paycheck = paycheck else {
            dismiss()
            return
        }
        
        let recurrence = recurrenceType == "none" ? "none" : recurrenceType
        paycheckViewModel.updatePaycheck(paycheck,
                                         name: name,
                                         amount: amount,
                                         firstDepositDate: firstDepositDate,
                                         recurrenceType: recurrence,
                                         recurrenceInterval: recurrence == "none" ? 0 : recurrenceInterval,
                                         autoReconcile: autoReconcile,
                                         notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                         account: account)
        
        dismiss()
    }
    
    private func deletePaycheck(scope: DeleteScope) {
        guard let paycheck = paycheck else {
            dismiss()
            return
        }
        
        switch scope {
        case .thisOccurrenceOnly:
            if let occurrenceDate = occurrenceDate {
                // Delete only this occurrence's transaction
                accountViewModel.deletePaycheckOccurrenceTransaction(
                    paycheck: paycheck,
                    occurrenceDate: occurrenceDate
                )
            } else {
                // Delete only this income template (but keep future occurrences if they exist)
                // For now, this is the same as deleting the whole thing
                // In the future, we might want to create a new template for remaining occurrences
                paycheckViewModel.deletePaycheck(paycheck)
            }
        case .allFutureOccurrences:
            if let occurrenceDate = occurrenceDate {
                // Delete this occurrence and all future occurrences
                // Delete the transaction for this occurrence
                accountViewModel.deletePaycheckOccurrenceTransaction(
                    paycheck: paycheck,
                    occurrenceDate: occurrenceDate
                )
                // Also delete the template to prevent future occurrences
                paycheckViewModel.deletePaycheck(paycheck)
            } else {
                // Delete the entire income template and all future occurrences
                paycheckViewModel.deletePaycheck(paycheck)
            }
        }
        
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
