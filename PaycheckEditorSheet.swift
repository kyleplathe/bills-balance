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
    @State private var showValidationAlert = false
    @State private var validationMessage: String?
    @State private var showUpdateScopeAlert = false
    @State private var pendingSaveData: (name: String, amount: Decimal, account: Account)?
    @State private var showDeleteScopeAlert = false
    
    enum DeleteScope {
        case thisOccurrenceOnly
        case allFutureOccurrences
    }
    
    let recurrenceOptions = ["none", "daily", "weekly", "monthly", "quarterly", "semiannually", "yearly"]
    
    init(paycheck: Paycheck? = nil, defaultDate: Date? = nil, occurrenceDate: Date? = nil) {
        self.paycheck = paycheck
        self.occurrenceDate = occurrenceDate
        _name = State(initialValue: paycheck?.name ?? "")
        if let amountValue = paycheck?.amount?.decimalValue {
            _amount = State(initialValue: NSDecimalNumber(decimal: amountValue).stringValue)
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
                    TextField("Income Name", text: $name)
                    
                    HStack {
                        Text("$")
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    DatePicker("First Deposit", selection: $firstDepositDate, displayedComponents: .date)
                    
                    if accountViewModel.accounts.isEmpty {
                        Text("Add an account in the Balance tab first.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
                    
                    Toggle("Auto-Reconcile", isOn: $autoReconcile)
                    
                    Picker("Repeat", selection: $recurrenceType) {
                        ForEach(recurrenceOptions, id: \.self) { option in
                            Text(recurrenceDisplayName(for: option)).tag(option)
                        }
                    }
                    .onChange(of: recurrenceType) { oldType, newType in
                        guard oldType != newType else { return }
                        switch newType {
                        case "none": break
                        case "daily":
                            if recurrenceInterval < 1 { recurrenceInterval = 1 }
                            else if recurrenceInterval > 365 { recurrenceInterval = 365 }
                        case "weekly":
                            if recurrenceInterval < 1 { recurrenceInterval = 1 }
                            else if recurrenceInterval > 52 { recurrenceInterval = 52 }
                        case "monthly", "quarterly", "semiannually", "yearly":
                            recurrenceInterval = 1
                        default: recurrenceInterval = 1
                        }
                    }
                    
                    // Show interval selector for daily and weekly
                    if recurrenceType == "daily" || recurrenceType == "weekly" {
                        let maxInterval = recurrenceType == "daily" ? 365 : 52
                        let unit = recurrenceType == "daily" ? (recurrenceInterval == 1 ? "day" : "days") : (recurrenceInterval == 1 ? "week" : "weeks")
                        
                        HStack {
                            Text("Every")
                                .foregroundColor(.secondary)
                            Stepper(value: $recurrenceInterval, in: 1...maxInterval) {
                                HStack {
                                Text("\(recurrenceInterval)")
                                        .fontWeight(.medium)
                                    Text(unit)
                                .foregroundColor(.secondary)
                                }
                        }
                    }
                }
                
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle(paycheck == nil ? "New Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { 
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dismiss()
                        }
                    }
                    .transaction { transaction in
                        transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Show delete button only when editing an existing income
                    if paycheck != nil {
                        Button(role: .destructive) {
                            // Ask about scope before deleting
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDeleteScopeAlert = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .transaction { transaction in
                            transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                        }
                    }
                    Button("Save") { savePaycheck() }
                        .fontWeight(.semibold)
                        .transaction { transaction in
                            transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                        }
                }
            }
            .alert("Validation Error", isPresented: $showValidationAlert, presenting: validationMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
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
            .onAppear {
                accountViewModel.fetchAccounts()
                if selectedAccountID == nil {
                    selectedAccountID = accountViewModel.selectedAccount?.id
                }
            }
        }
    }
    
    private func recurrenceDisplayName(for option: String) -> String {
        switch option {
        case "none":
            return "One-time"
        case "daily":
            return "Daily"
        case "weekly":
            return "Weekly"
        case "monthly":
            return "Monthly"
        case "quarterly":
            return "Quarterly"
        case "semiannually":
            return "Semi-annually"
        case "yearly":
            return "Yearly"
        default:
            return option.capitalized
        }
    }
    
    private var intervalUnitLabel: String {
        guard recurrenceType != "none" else { return "" }
        
        var unit: String
        switch recurrenceType {
        case "daily":
            unit = recurrenceInterval == 1 ? "day" : "days"
        case "weekly":
            unit = recurrenceInterval == 1 ? "week" : "weeks"
        case "monthly":
            unit = recurrenceInterval == 1 ? "month" : "months"
        case "quarterly":
            unit = recurrenceInterval == 1 ? "quarter" : "quarters"
        case "semiannually":
            unit = recurrenceInterval == 1 ? "half year" : "half years"
        case "yearly":
            unit = recurrenceInterval == 1 ? "year" : "years"
        default:
            unit = recurrenceType
        }
        return unit
    }
    

    private func savePaycheck() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Name cannot be empty."
            showValidationAlert = true
            return
        }
        let sanitizedAmount = amount
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        guard let amountDecimal = Decimal(string: sanitizedAmount), amountDecimal > 0 else {
            validationMessage = "Enter a valid amount."
            showValidationAlert = true
            return
        }
        guard let account = accountViewModel.account(with: selectedAccountID) else {
            validationMessage = "Select an account for this income."
            showValidationAlert = true
            return
        }
        
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
