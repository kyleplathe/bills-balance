//
//  AddEditBillView.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import SwiftUI

enum PaymentMethod: Hashable {
    case none
    case creditCard(String)
    case debtAccount(UUID)
    case addCard
    case addAccount

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
    @State private var paymentMethodBeforeAdd: PaymentMethod = .none
    @State private var showSeriesUpdatePrompt = false
    @State private var pendingAmount: Decimal?
    @State private var showValidationAlert = false
    @State private var validationMessage: String?
    @State private var showingAddCard = false
    @State private var newCardName: String = ""
    @State private var showingAccountEditor = false
    @State private var showDeleteScopeAlert = false
    @State private var trackInBitcoin = false
    @FocusState private var isAmountFocused: Bool

    init(bill: Bill? = nil, defaultDate: Date? = nil) {
        self.bill = bill
        self.defaultDate = defaultDate
        _dueDate = State(initialValue: defaultDate ?? Date())
    }

    private var parsedAmount: Decimal? {
        MoneyFormatting.parse(amount, kind: .usd)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedAmount ?? 0) > 0
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
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyAmountHeader(
                        text: $amount,
                        kind: .usd,
                        tone: .outflow,
                        isFocused: $isAmountFocused
                    )
                } footer: {
                    if let amountFooter {
                        Text(amountFooter)
                    }
                }

                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, newValue in
                            if category.isEmpty && !newValue.isEmpty {
                                let suggested = CategorySuggester.suggest(
                                    for: newValue,
                                    priorCategory: accountViewModel.suggestedCategory(forTitle: newValue)
                                )
                                if !suggested.isEmpty { category = suggested }
                            }
                        }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                    RecurrenceFields(recurrenceType: $recurrenceType, recurrenceInterval: $recurrenceInterval)
                    paymentMethodPicker
                }

                Section {
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                        .onChange(of: category) { _, newValue in
                            if newValue.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let suggested = CategorySuggester.suggest(
                                    for: name,
                                    priorCategory: accountViewModel.suggestedCategory(forTitle: name)
                                )
                                if !suggested.isEmpty { category = suggested }
                            }
                        }
                    Toggle("Auto-Pay", isOn: $autoPay)
                    if accountViewModel.hasActiveBitcoinDigitalWallet {
                        Toggle("Track in Bitcoin", isOn: $trackInBitcoin)
                    }
                    NotesField(text: $notes)
                }
            }
            .navigationTitle(bill == nil ? "Add Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    canSave: canSave,
                    showDelete: bill != nil,
                    onClose: { dismiss() },
                    onSave: saveBill,
                    onDelete: {
                        if let bill, (bill.recurrenceType ?? "none") != "none" {
                            showDeleteScopeAlert = true
                        } else {
                            deleteBill(scope: .thisBillOnly)
                        }
                    }
                )
            }
            .onAppear {
                accountViewModel.fetchAccounts()
                loadBillData()
                if bill == nil {
                    isAmountFocused = true
                }
            }
            .confirmationDialog("Apply changes to the entire series?", isPresented: $showSeriesUpdatePrompt, titleVisibility: .visible) {
                confirmationDialogContent
            }
            .alert("Auto-Pay",
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
            .onChange(of: paymentMethod) { _, newValue in
                handlePaymentPickerChange(newValue)
            }
            .sheet(isPresented: $showingAddCard) {
                AddCardSheet(cardName: $newCardName) {
                    let trimmed = newCardName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    cardManager.addCard(trimmed)
                    paymentMethod = .creditCard(trimmed)
                    paymentMethodBeforeAdd = paymentMethod
                    newCardName = ""
                    showingAddCard = false
                } onCancel: {
                    newCardName = ""
                    showingAddCard = false
                    paymentMethod = paymentMethodBeforeAdd
                }
            }
            .sheet(isPresented: $showingAccountEditor) {
                AccountEditorSheet(account: nil) { name, type, startingBalance, isHidden, currency, btcDisplayFormat, feePercentage, startingBalanceUSD, startingBalanceBTCPrice in
                    accountViewModel.addAccount(name: name,
                                                type: type,
                                                startingBalance: startingBalance,
                                                isHidden: isHidden,
                                                currency: currency,
                                                btcDisplayFormat: btcDisplayFormat,
                                                feePercentage: feePercentage,
                                                startingBalanceUSD: startingBalanceUSD,
                                                startingBalanceBTCPrice: startingBalanceBTCPrice)
                    accountViewModel.fetchAccounts()
                    if let created = accountViewModel.accounts.first(where: { $0.name == name }), let id = created.id {
                        paymentMethod = .debtAccount(id)
                        paymentMethodBeforeAdd = paymentMethod
                    }
                }
                .environmentObject(BitcoinPriceService.shared)
            }
        }
    }

    @ViewBuilder
    private var paymentMethodPicker: some View {
        Picker("Payment Method", selection: paymentMethodBinding) {
            Text("None").tag(PaymentMethod.none)

            if !cardManager.cards.isEmpty {
                Section("Credit Cards") {
                    ForEach(cardManager.cards, id: \.self) { card in
                        Text(card).tag(PaymentMethod.creditCard(card))
                    }
                }
            }

            if !accountViewModel.accounts.isEmpty {
                Section("Accounts") {
                    ForEach(accountViewModel.accounts, id: \.id) { account in
                        if let accountId = account.id {
                            Text(account.name ?? "Account").tag(PaymentMethod.debtAccount(accountId))
                        }
                    }
                }
            }

            if let extra = selectedCardName,
               !cardManager.cards.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) {
                Text(extra).tag(PaymentMethod.creditCard(extra))
            }

            Text("Add Card…").tag(PaymentMethod.addCard)
            Text("Add Account…").tag(PaymentMethod.addAccount)
        }
        .pickerStyle(.menu)
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
        if let newValue {
            paymentMethod = .debtAccount(newValue)
            paymentMethodBeforeAdd = paymentMethod
        }
    }

    private func handlePaymentPickerChange(_ newValue: PaymentMethod) {
        switch newValue {
        case .addCard:
            paymentMethod = paymentMethodBeforeAdd
            newCardName = ""
            showingAddCard = true
        case .addAccount:
            paymentMethod = paymentMethodBeforeAdd
            showingAccountEditor = true
        default:
            paymentMethodBeforeAdd = newValue
        }
    }

    private func loadBillData() {
        guard let bill else { return }

        name = bill.name ?? ""
        if let amountValue = bill.amount?.decimalValue {
            amount = MoneyFormatting.format(amountValue, kind: .usd)
        } else {
            amount = ""
        }
        if let billDueDate = bill.dueDate {
            dueDate = billDueDate
        }
        notes = bill.notes ?? ""
        recurrenceType = bill.recurrenceType ?? "none"
        recurrenceInterval = max(Int(bill.recurrenceInterval), 1)

        switch recurrenceType {
        case "daily":
            recurrenceInterval = min(max(recurrenceInterval, 1), 365)
        case "weekly":
            recurrenceInterval = min(max(recurrenceInterval, 1), 52)
        case "monthly", "quarterly", "semiannually", "yearly":
            recurrenceInterval = 1
        default:
            break
        }

        autoPay = bill.autoPay
        trackInBitcoin = bill.trackInBitcoinFlag
        paymentMethod = PaymentMethod.from(bill: bill)
        paymentMethodBeforeAdd = paymentMethod
        selectedAccountID = bill.account?.id
        selectedCardName = bill.paymentCard

        if let existingCategory = bill.category, !existingCategory.isEmpty {
            category = existingCategory
        } else {
            let suggested = CategorySuggester.suggest(
                for: name,
                priorCategory: accountViewModel.suggestedCategory(forTitle: name)
            )
            category = suggested
        }
    }

    private func saveBill() {
        guard let amountDecimal = parsedAmount, amountDecimal > 0 else { return }

        let (cardName, account) = extractPaymentMethod()

        if autoPay, account == nil, cardName?.isEmpty ?? true {
            validationMessage = "Link an account or card before enabling Auto-Pay."
            showValidationAlert = true
            HapticManager.shared.errorOccurred()
            return
        }

        if let bill {
            if (bill.recurrenceType ?? "none") != "none" {
                pendingAmount = amountDecimal
                showSeriesUpdatePrompt = true
            } else {
                performUpdate(amountDecimal: amountDecimal, applyToSeries: false)
            }
        } else {
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
                category: category.isEmpty ? nil : category,
                trackInBitcoin: trackInBitcoin
            )
            HapticManager.shared.buttonTapped()
            dismiss()
        }
    }

    private func extractPaymentMethod() -> (cardName: String?, account: Account?) {
        switch paymentMethod {
        case .none, .addCard, .addAccount:
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
        guard let bill else {
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
        guard let bill else { return }

        let (cardName, account) = extractPaymentMethod()

        if autoPay, account == nil, cardName?.isEmpty ?? true {
            validationMessage = "Link an account or card before enabling Auto-Pay."
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
            category: category.isEmpty ? nil : category,
            trackInBitcoin: trackInBitcoin
        )

        pendingAmount = nil
        HapticManager.shared.buttonTapped()
        dismiss()
    }
}

private extension AddEditBillView {
    var paymentMethodBinding: Binding<PaymentMethod> {
        Binding<PaymentMethod> {
            paymentMethod
        } set: { newValue in
            paymentMethod = newValue
            switch newValue {
            case .none, .addCard, .addAccount:
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
}

private struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var cardName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Card name", text: $cardName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .formEntryChrome()
            .toolbar {
                FormSheetToolbar(
                    saveTitle: "Add",
                    canSave: !cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onClose: {
                        onCancel()
                        dismiss()
                    },
                    onSave: {
                        onSave()
                        dismiss()
                    }
                )
            }
            .onAppear { isNameFocused = true }
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
    AddEditBillView()
        .environmentObject(billVM)
        .environmentObject(accountVM)
        .environmentObject(notif)
}
