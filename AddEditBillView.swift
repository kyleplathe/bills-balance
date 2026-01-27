//
//  AddEditBillView.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import SwiftUI

// MARK: - Payment Method Enum
enum PaymentMethod: Hashable {
    case none
    case creditCard(String)
    case debtAccount(UUID)
    
    static func from(bill: Bill) -> PaymentMethod {
        if let cardName = bill.paymentCard, !cardName.isEmpty {
            return .creditCard(cardName)
        } else if let accountId = bill.account?.id {
            return .debtAccount(accountId)
        } else {
            return .none
        }
    }
}

struct AddEditBillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var cardManager: CreditCardManager
    @EnvironmentObject private var categoryManager: CategoryManager
    
    let bill: Bill?
    private let defaultDate: Date?
    
    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var dueDate: Date
    @State private var notes: String = ""
    @State private var recurrenceType: String = "none"
    @State private var recurrenceInterval: Int = 1
    @State private var autoPay: Bool = false
    @State private var category: String = ""
    @State private var selectedAccountID: UUID?
    @State private var selectedCardName: String?
    @State private var paymentMethod: PaymentMethod = .none
    @State private var showSeriesUpdatePrompt = false
    @State private var pendingAmount: Decimal?
    @State private var showValidationAlert = false
    @State private var validationMessage: String?
    @State private var newCardName: String = ""
    @State private var editingCard: String?
    @State private var editedCardName: String = ""
    @State private var showingAccountEditor = false
    @State private var accountToEdit: Account?
    @State private var showDeleteScopeAlert = false
    
    let recurrenceOptions = ["none", "daily", "weekly", "monthly", "quarterly", "semiannually", "yearly"]
    
    init(bill: Bill? = nil, defaultDate: Date? = nil) {
        self.bill = bill
        self.defaultDate = defaultDate
        _dueDate = State(initialValue: defaultDate ?? Date())
    }
    
    var body: some View {
        NavigationView {
            formContent
                .navigationTitle(bill == nil ? "Add Bill" : "Edit Bill")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                .onAppear {
                    accountViewModel.fetchAccounts()
                    loadBillData()
                }
                .confirmationDialog("Apply changes to the entire series?", isPresented: $showSeriesUpdatePrompt, titleVisibility: .visible) {
                    confirmationDialogContent
                }
                .alert("Validation Error",
                       isPresented: $showValidationAlert,
                       presenting: validationMessage) { _ in
                    Button("OK", role: .cancel) { }
                } message: { message in
                    Text(message)
                }
                .alert("Delete Scope", isPresented: $showDeleteScopeAlert) {
                    Button("This Bill Only", role: .destructive) {
                        deleteBill(scope: .thisBillOnly)
                    }
                    Button("This and Future Bills", role: .destructive) {
                        deleteBill(scope: .allFutureBills)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Do you want to delete just this bill, or delete this bill and all future bills in the series?")
                }
                .onChange(of: accountViewModel.selectedAccount?.id) { _, newValue in
                    handleAccountSelectionChange(newValue)
                }
                .onReceive(cardManager.$cards) { cards in
                    handleCardsChange(cards)
                }
                .sheet(item: Binding(
                    get: { editingCard.map { CardIdentifier(name: $0) } },
                    set: { editingCard = $0?.name }
                )) { _ in
                    CreditCardEditorSheet(cardName: editingCard ?? "", editedName: $editedCardName) {
                        if let card = editingCard {
                            cardManager.renameCard(from: card, to: editedCardName)
                        }
                        editingCard = nil
                        editedCardName = ""
                    } onCancel: {
                        editingCard = nil
                        editedCardName = ""
                    }
                }
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
                }
        }
    }
    
    private var formContent: some View {
        Form {
            mainSection
            notesSection
        }
    }
    
    private var mainSection: some View {
        Section {
            TextField("Bill Name", text: $name)
                .onChange(of: name) { _, newValue in
                    // Auto-categorize only if category is empty (don't override user's choice)
                    if category.isEmpty && !newValue.isEmpty {
                        let suggested = CategorySuggester.suggest(for: newValue)
                        if !suggested.isEmpty { category = suggested }
                    }
                }
            
            HStack {
                Text("$")
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
            }
            
            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
            
            CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                .environmentObject(categoryManager)
                .onChange(of: category) { _, newValue in
                    // Re-suggest when user clears category (None) and name is non-empty
                    if newValue.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let suggested = CategorySuggester.suggest(for: name)
                        if !suggested.isEmpty { category = suggested }
                    }
                }
            
            Picker("Repeat", selection: $recurrenceType) {
                ForEach(recurrenceOptions, id: \.self) { option in
                    Text(recurrenceDisplayName(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)
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
            
            if cardManager.cards.isEmpty && accountViewModel.accounts.isEmpty {
                emptyPaymentMethodsView
            } else {
                paymentMethodPicker
            }
            
            Toggle("Auto-Pay", isOn: $autoPay)
            
            // Inline credit card management
            creditCardsManagementSection
            
            // Inline account management
            accountsManagementSection
        }
    }
    
    private var emptyPaymentMethodsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add credit cards or accounts to track payment methods.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var creditCardsManagementSection: some View {
        DisclosureGroup("Manage Cards") {
            if cardManager.cards.isEmpty {
                Text("No credit cards added yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(cardManager.cards, id: \.self) { card in
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text(card)
                        Spacer()
                        Button {
                            editingCard = card
                            editedCardName = card
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                }
                .onDelete(perform: deleteCards)
            }
            
            HStack {
                TextField("Card name", text: $newCardName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button("Add") {
                    addCard()
                }
                .disabled(newCardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private func addCard() {
        cardManager.addCard(newCardName)
        newCardName = ""
    }
    
    private func deleteCards(at offsets: IndexSet) {
        cardManager.removeCards(at: offsets)
    }
    
    @ViewBuilder
    private var accountsManagementSection: some View {
        DisclosureGroup("Manage Accounts") {
            if accountViewModel.accounts.isEmpty {
                Text("No accounts added yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
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
            }
            
            Button {
                accountToEdit = nil
                showingAccountEditor = true
            } label: {
                Label("Add Account", systemImage: "plus.circle")
            }
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
    
    private var paymentMethodPicker: some View {
        Picker("Payment Method", selection: paymentMethodBinding) {
            Text("None").tag(PaymentMethod.none)
            
            if !cardManager.cards.isEmpty {
                Section("Credit Cards") {
                    creditCardOptions
                }
            }
            
            if !accountViewModel.accounts.isEmpty {
                Section("Accounts") {
                    debtAccountOptions
                }
            }
            
            legacyCardOption
        }
        .pickerStyle(.menu)
    }
    
    @ViewBuilder
    private var creditCardOptions: some View {
        if !cardManager.cards.isEmpty {
            ForEach(cardManager.cards, id: \.self) { card in
                HStack {
                    Image(systemName: "creditcard")
                    Text(card)
                }
                .tag(PaymentMethod.creditCard(card))
            }
        }
    }
    
    @ViewBuilder
    private var debtAccountOptions: some View {
        if !accountViewModel.accounts.isEmpty {
            ForEach(accountViewModel.accounts, id: \.id) { account in
                if let accountId = account.id {
                    HStack {
                        Image(systemName: "building.columns")
                        Text(account.name ?? "Debt Account")
                    }
                    .tag(PaymentMethod.debtAccount(accountId))
                }
            }
        }
    }
    
    @ViewBuilder
    private var legacyCardOption: some View {
        if let extra = selectedCardName,
           !cardManager.cards.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) {
            HStack {
                Image(systemName: "creditcard")
                Text(extra)
            }
            .tag(PaymentMethod.creditCard(extra))
        }
    }
    
    
    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
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
                // Show delete button only when editing an existing bill
                if bill != nil {
                    Button(role: .destructive) {
                        // Check if this is a recurring bill
                        if let bill = bill, (bill.recurrenceType ?? "none") != "none" {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDeleteScopeAlert = true
                            }
                        } else {
                            // Non-recurring bill - just delete it
                            deleteBill(scope: .thisBillOnly)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .transaction { transaction in
                        transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                    }
                }
                Button("Save") {
                    saveBill()
                }
                .fontWeight(.semibold)
                .disabled(name.isEmpty || amount.isEmpty)
                .transaction { transaction in
                    transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                }
            }
        }
    }
    
    private var confirmationDialogContent: some View {
        Group {
            Button("This bill only") {
                guard let amountDecimal = pendingAmount else { return }
                performUpdate(amountDecimal: amountDecimal, applyToSeries: false)
            }
            Button("This and future bills") {
                guard let amountDecimal = pendingAmount else { return }
                performUpdate(amountDecimal: amountDecimal, applyToSeries: true)
            }
            Button("Cancel", role: .cancel) {
                pendingAmount = nil
            }
        }
    }
    
    private func handleAccountSelectionChange(_ newValue: UUID?) {
        guard bill == nil, paymentMethod == .none else { return }
        if let newValue = newValue {
            paymentMethod = .debtAccount(newValue)
        }
    }
    
    private func handleCardsChange(_ cards: [String]) {
        if case .creditCard(let currentCard) = paymentMethod {
            if cards.isEmpty {
                paymentMethod = .none
            } else if !cards.contains(where: { $0.caseInsensitiveCompare(currentCard) == .orderedSame }) {
                // Card was deleted, but keep it in paymentMethod for legacy support
            }
        }
    }
    
    // MARK: - Load Bill Data
    private func loadBillData() {
        guard let bill = bill else { return }
        
        name = bill.name ?? ""
        amount = bill.amount?.stringValue ?? ""
        if let billDueDate = bill.dueDate {
            dueDate = billDueDate
        }
        notes = bill.notes ?? ""
        recurrenceType = bill.recurrenceType ?? "none"
        recurrenceInterval = Int(bill.recurrenceInterval)
        
        // Set fixed intervals for non-weekly/daily types
        if recurrenceType != "none" {
            switch recurrenceType {
            case "daily":
                // Keep loaded interval, but clamp to valid range (1-365)
                if recurrenceInterval < 1 {
                    recurrenceInterval = 1
                } else if recurrenceInterval > 365 {
                    recurrenceInterval = 365
                }
            case "weekly":
                // Keep loaded interval, but clamp to valid range (1-52)
                if recurrenceInterval < 1 {
                    recurrenceInterval = 1
                } else if recurrenceInterval > 52 {
                    recurrenceInterval = 52
                }
            case "monthly", "quarterly", "semiannually", "yearly":
                // Set fixed interval of 1 for these types
                recurrenceInterval = 1
            default:
                recurrenceInterval = 1
            }
        }
        
        autoPay = bill.autoPay
        paymentMethod = PaymentMethod.from(bill: bill)
        selectedAccountID = bill.account?.id
        selectedCardName = bill.paymentCard
        
        // Set category, or auto-categorize if empty
        if let existingCategory = bill.category, !existingCategory.isEmpty {
            category = existingCategory
        } else {
            let suggested = CategorySuggester.suggest(for: name)
            category = suggested.isEmpty ? "" : suggested
        }
    }
    
    // MARK: - Save Bill
    private func saveBill() {
        guard let amountDecimal = Decimal(string: amount) else {
            HapticManager.shared.errorOccurred()
            return
        }
        
        // Extract payment method details
        let (cardName, account) = extractPaymentMethod()
        
        if autoPay, account == nil, cardName?.isEmpty ?? true {
            validationMessage = "Link a debt account to this bill before enabling Auto-Pay."
            showValidationAlert = true
            HapticManager.shared.errorOccurred()
            return
        }
        
        if let bill = bill {
            if (bill.recurrenceType ?? "none") != "none" {
                pendingAmount = amountDecimal
                showSeriesUpdatePrompt = true
            } else {
                performUpdate(amountDecimal: amountDecimal, applyToSeries: false)
            }
        } else {
            // Add new bill
            _ = billViewModel.addBill(
                name: name,
                amount: amountDecimal,
                dueDate: dueDate,
                notes: notes,
                recurrenceType: recurrenceType,
                recurrenceInterval: recurrenceInterval,
                autoPay: autoPay,
                paymentCard: cardName,
                account: account,
                category: category.isEmpty ? nil : category
            )
            
            HapticManager.shared.buttonTapped()
            dismiss()
        }
    }
    
    private func extractPaymentMethod() -> (cardName: String?, account: Account?) {
        switch paymentMethod {
        case .none:
            return (nil, nil)
        case .creditCard(let cardName):
            return (cardName, nil)
        case .debtAccount(let accountId):
            return (nil, accountViewModel.account(with: accountId))
        }
    }
    
    enum DeleteScope {
        case thisBillOnly
        case allFutureBills
    }
    
    private func deleteBill(scope: DeleteScope) {
        guard let bill = bill else {
            dismiss()
            return
        }
        
        switch scope {
        case .thisBillOnly:
            billViewModel.deleteBill(bill)
        case .allFutureBills:
            billViewModel.deleteRecurringBillAndFuture(bill)
        }
        
        HapticManager.shared.billDeleted()
        dismiss()
    }
    
    private func performUpdate(amountDecimal: Decimal, applyToSeries: Bool) {
        guard let bill = bill else { return }
        
        // Extract payment method details
        let (cardName, account) = extractPaymentMethod()
        
        if autoPay, account == nil, cardName?.isEmpty ?? true {
            validationMessage = "Link a debt account to this bill before enabling Auto-Pay."
            showValidationAlert = true
            HapticManager.shared.errorOccurred()
            return
        }
        
        billViewModel.updateBill(
            bill,
            name: name,
            amount: amountDecimal,
            dueDate: dueDate,
            notes: notes,
            recurrenceType: recurrenceType,
            recurrenceInterval: recurrenceInterval,
            autoPay: autoPay,
            paymentCard: cardName,
            account: account,
            applyToSeries: applyToSeries,
            category: category.isEmpty ? nil : category
        )
        
        pendingAmount = nil
        HapticManager.shared.buttonTapped()
        dismiss()
    }
}

// MARK: - Payment Method Binding
private extension AddEditBillView {
    var paymentMethodBinding: Binding<PaymentMethod> {
        Binding<PaymentMethod> {
            paymentMethod
        } set: { newValue in
            paymentMethod = newValue
            // Update individual state variables for backward compatibility
            switch newValue {
            case .none:
                selectedCardName = nil
                selectedAccountID = nil
            case .creditCard(let cardName):
                selectedCardName = cardName
                selectedAccountID = nil
            case .debtAccount(let accountId):
                selectedCardName = nil
                selectedAccountID = accountId
            }
        }
    }
    
    var selectedAccountObject: Account? {
        accountViewModel.account(with: selectedAccountID)
    }
    
    // MARK: - Recurrence Helpers
    func recurrenceDisplayName(for option: String) -> String {
        switch option {
        case "none":
            return "Never"
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
    
    // Maximum recurrence interval based on recurrence type
    private var maxRecurrenceInterval: Int {
        maxRecurrenceIntervalForType(recurrenceType)
    }
    
    // Helper function to get max interval for a specific recurrence type
    private func maxRecurrenceIntervalForType(_ type: String) -> Int {
        switch type {
        case "daily":
            return 365 // Up to 365 days (1 year)
        case "weekly":
            return 52 // Up to 52 weeks (1 year)
        case "monthly":
            return 24 // Up to 24 months (2 years)
        case "quarterly":
            return 8 // Up to 8 quarters (2 years)
        case "semiannually":
            return 4 // Up to 4 half-years (2 years)
        case "yearly":
            return 10 // Up to 10 years
        default:
            return 12 // Default fallback
        }
    }
    
    var intervalUnitLabel: String {
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
    let notif = NotificationManager()
    let accountVM = AccountViewModel(context: controller.container.viewContext)
    let billVM = BillViewModel(context: controller.container.viewContext,
                               notificationManager: notif,
                               accountViewModel: accountVM)
    return AddEditBillView()
        .environmentObject(billVM)
        .environmentObject(accountVM)
        .environmentObject(notif)
}

