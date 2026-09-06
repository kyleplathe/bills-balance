//
//  CalendarDayDrawer.swift
//  BillsAndBalance
//

import SwiftUI

// MARK: - Day Detail Card
struct DayDetailCard: View {
    let selectedDate: Date
    let occurrences: [BillOccurrence]
    let currencyCode: String
    let colorScheme: ColorScheme
    
    private var headerFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
    
    var body: some View {
        let background: Color = colorScheme == .dark ? Color.black.opacity(0.85) : Color(.systemBackground)
        let border: Color = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        
        VStack(alignment: .leading, spacing: 16) {
            Text(headerFormatter.string(from: selectedDate))
                .font(.headline)
            
            if occurrences.isEmpty {
                Label("No bills due on this day", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(occurrences) { occurrence in
                        BillDueRow(occurrence: occurrence, 
                                 currencyCode: currencyCode,
                                 onEdit: nil, // DayDetailCard doesn't have callbacks
                                 onDelete: nil)
                        if occurrence.id != occurrences.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(border)
                )
        )
    }
}

// MARK: - Day Drawer
struct DayDetailDrawer: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let date: Date
    let bills: [BillOccurrence]
    let paychecks: [PaycheckOccurrence]
    let currencyCode: String
    var compact: Bool = false
    let onAddBill: (() -> Void)?
    let onAddIncome: (() -> Void)?
    let onAddIncomeTransaction: (() -> Void)?
    let onEditBill: ((Bill) -> Void)?
    let onEditIncome: ((Paycheck) -> Void)?
    let onDeleteBill: ((Bill) -> Void)?
    let onDeleteIncome: ((Paycheck) -> Void)?
    let onClose: () -> Void
    @State private var dragOffset: CGFloat = 0
    
    private var headerFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let translation = value.translation.height
                let horizontalTranslation = abs(value.translation.width)
                
                // Only respond to downward drags that are primarily vertical
                // This allows taps and horizontal scrolls to work normally
                if translation > 0 && translation > horizontalTranslation * 1.5 {
                    // Apply resistance - the further you drag, the more resistance
                    let resistance: CGFloat = 1.0 - min(translation / 1000, 0.5)
                    dragOffset = translation * resistance
                } else {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                let translation = value.translation.height
                let horizontalTranslation = abs(value.translation.width)
                let velocity = value.predictedEndTranslation.height - value.translation.height
                
                // Only dismiss if it was a primarily vertical downward drag
                if translation > 0 && translation > horizontalTranslation * 1.5 {
                    // Lower thresholds for easier dismissal
                    // Close if dragged down more than 60px or with sufficient downward velocity
                    if translation > 60 || velocity > 300 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                            onClose()
                        }
                    } else {
                        // Spring back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
                } else {
                    // Reset if it wasn't a valid vertical drag
                    dragOffset = 0
                }
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            drawerHeader
                .contentShape(Rectangle())
                .gesture(dragGesture)
            
            VStack(spacing: compact ? 8 : 16) {
                if !compact {
                    addActionsRow
                }

                if bills.isEmpty && paychecks.isEmpty {
                    emptyDayState
                } else {
                    VStack(alignment: .leading, spacing: compact ? 6 : 12) {
                        ForEach(bills) { occurrence in
                            drawerBillRow(occurrence)
                        }
                        ForEach(paychecks) { occurrence in
                            drawerPaycheckRow(occurrence)
                        }
                    }
                }
            }
            .padding(.top, compact ? 4 : 8)
        }
        .offset(y: max(0, dragOffset))
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: dragOffset)
        .padding(.bottom, compact ? 10 : 18)
        .padding(.horizontal, compact ? 12 : 18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 20 : 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: compact ? 20 : 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)
    }
    
    private var drawerHeader: some View {
        VStack(spacing: compact ? 4 : 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, compact ? 8 : 12)
            
            HStack(spacing: 8) {
                Text(headerFormatter.string(from: date))
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
                
                if compact {
                    addActionsRow
                }
            }
        }
        .frame(minHeight: compact ? 44 : 60)
        .padding(.bottom, compact ? 2 : 0)
    }
    
    @ViewBuilder
    private var addActionsRow: some View {
        if onAddBill != nil || onAddIncome != nil {
            HStack(spacing: compact ? 8 : 12) {
                if let onAddBill {
                    Button(action: onAddBill) {
                        if compact {
                            Image(systemName: "plus.circle")
                        } else {
                            Label("Add Bill", systemImage: "plus.circle")
                        }
                    }
                    .accessibilityLabel("Add Bill")
                }
                if let onAddIncome {
                    Button(action: onAddIncome) {
                        if compact {
                            Image(systemName: "arrow.down.circle")
                        } else {
                            Label("Add Income", systemImage: "arrow.down.circle")
                        }
                    }
                    .accessibilityLabel("Add Income")
                }
                if !compact {
                    Spacer()
                }
            }
            .font(compact ? .body.weight(.semibold) : .caption.weight(.semibold))
            .foregroundColor(.accentColor)
        }
    }
    
    private var emptyDayState: some View {
        VStack(spacing: compact ? 4 : 8) {
            if !compact {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
            Text("No activity on this day")
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 4 : 0)
    }
    
    private var rowPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            : EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    }
    
    private var rowCorner: CGFloat { compact ? 12 : 16 }
    
    private func drawerBillRow(_ occurrence: BillOccurrence) -> some View {
        BillDueRow(occurrence: occurrence,
                   currencyCode: currencyCode,
                   compact: compact,
                   onEdit: { onEditBill?(occurrence.bill) },
                   onDelete: { onDeleteBill?(occurrence.bill) })
            .padding(rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: rowCorner, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onEditBill?(occurrence.bill)
            }
            .onLongPressGesture {
                onEditBill?(occurrence.bill)
            }
    }
    
    private func drawerPaycheckRow(_ occurrence: PaycheckOccurrence) -> some View {
        PaycheckRow(occurrence: occurrence,
                    currencyCode: currencyCode,
                    compact: compact,
                    onAddToAccount: addPaycheckToAccount(occurrence),
                    onEdit: { onEditIncome?(occurrence.paycheck) },
                    onDelete: { onDeleteIncome?(occurrence.paycheck) })
            .environmentObject(accountViewModel)
            .padding(rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: rowCorner, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
    }
    
    private func addPaycheckToAccount(_ occurrence: PaycheckOccurrence) -> () -> Void {
        {
            guard let account = occurrence.paycheck.account,
                  let amountValue = occurrence.paycheck.amount?.decimalValue,
                  amountValue > 0 else { return }
            
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: occurrence.date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
            
            let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
            let existingPending = entries.contains { entry in
                guard let entryDate = entry.date,
                      entryDate >= startOfDay,
                      entryDate < endOfDay,
                      entry.category == "Income",
                      !entry.isReconciledFlag else { return false }
                let titleMatches = entry.title == occurrence.paycheck.name
                let amountMatches = abs((entry.usdAmountDecimal - amountValue)) < 0.01
                return titleMatches || amountMatches
            }
            
            if existingPending {
                HapticManager.shared.billDeleted()
                return
            }
            
            let positiveAmount = max(abs(amountValue), amountValue)
            let previousSelectedAccount = accountViewModel.selectedAccount
            accountViewModel.selectedAccount = account
            _ = accountViewModel.recordLedgerEntry(
                for: occurrence.paycheck,
                amount: positiveAmount,
                date: occurrence.date,
                title: occurrence.paycheck.name ?? "Income",
                notes: occurrence.paycheck.notes
            )
            accountViewModel.selectedAccount = previousSelectedAccount
            accountViewModel.refreshData()
            HapticManager.shared.success()
        }
    }
}

// MARK: - Insights UI
struct CalendarInsight {
    let title: String
    let billCount: Int
    let amount: Decimal
    let tint: Color
    
    var billCountLabel: String {
        billCount == 1 ? "1 bill" : "\(billCount) bills"
    }
}

struct CalendarInsightGrid: View {
    let insights: [CalendarInsight]
    let currencyCode: String
    
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }
    
    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: insights.count == 1 ? [GridItem(.flexible())] : columns, spacing: 8) {
                ForEach(Array(insights.enumerated()), id: \.offset) { item in
                    CalendarInsightCard(insight: item.element, currencyCode: currencyCode)
                }
            }
        }
    }
}

struct CalendarInsightCard: View {
    let insight: CalendarInsight
    let currencyCode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(insight.title.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(insight.billCountLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(insight.amount, format: .currency(code: currencyCode))
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(insight.tint.opacity(0.12))
        )
    }
}

// MARK: - Shared Models
struct MonthStats {
    var unpaid: Int = 0
    var paid: Int = 0
    var projected: Int = 0
    var unpaidTotal: Decimal = .zero
    var paidTotal: Decimal = .zero
    var projectedTotal: Decimal = .zero
    
    var totalDue: Decimal {
        unpaidTotal + projectedTotal
    }
    
    var remaining: Decimal {
        unpaidTotal
    }
}

struct BillOccurrence: Identifiable {
    let id: String
    let bill: Bill
    let date: Date
    let isProjected: Bool
}

struct BillDaySummary {
    var actualUnpaid: Int = 0
    var actualUnpaidTotal: Decimal = .zero
    var actualPaid: Int = 0
    var actualPaidTotal: Decimal = .zero
    var projected: Int = 0
    var projectedTotal: Decimal = .zero
    var incomeCount: Int = 0
    var incomeTotal: Decimal = .zero
    
    var total: Int {
        actualUnpaid + actualPaid + projected + incomeCount
    }
}

struct DayOccurrences {
    var bills: [BillOccurrence] = []
    var paychecks: [PaycheckOccurrence] = []
}

struct MonthBillList: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let dayOccurrences: [(date: Date, data: DayOccurrences)]
    let calendar: Calendar
    let selectedDate: Date
    let currencyCode: String
    let onEditBill: ((Bill) -> Void)?
    let onEditIncome: ((Paycheck) -> Void)?
    let onDeleteBill: ((Bill) -> Void)?
    let onDeleteIncome: ((Paycheck) -> Void)?
    let onSelect: (Date) -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                if dayOccurrences.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No bills or income this month")
                            .font(.headline)
                        Text("Add a bill or paycheck to see it here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .padding(.top, 40)
                } else {
                    ForEach(dayOccurrences, id: \.date) { entry in
                        daySection(for: entry)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
        }
    }
    
    @ViewBuilder
    private func daySection(for entry: (date: Date, data: DayOccurrences)) -> some View {
        let date = entry.date
        let data = entry.data
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let net = totalAmount(for: data)
        
        VStack(alignment: .leading, spacing: 12) {
            dayHeader(date: date, net: net)
            paycheckSection(paychecks: data.paychecks)
            billSection(bills: data.bills)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(date) }
        .onLongPressGesture { onSelect(date) }
    }
    
    @ViewBuilder
    private func dayHeader(date: Date, net: Decimal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.headline)
            }
            Spacer()
            if net != .zero {
                Text(net, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(net >= 0 ? .green : .primary)
            }
        }
    }
    
    @ViewBuilder
    private func paycheckSection(paychecks: [PaycheckOccurrence]) -> some View {
        if !paychecks.isEmpty {
            VStack(spacing: 10) {
                ForEach(paychecks) { occurrence in
                    PaycheckRow(occurrence: occurrence, 
                              currencyCode: currencyCode,
                              onAddToAccount: {
                                  // Create pending transaction in account
                                  guard let account = occurrence.paycheck.account,
                                        let amountValue = occurrence.paycheck.amount?.decimalValue,
                                        amountValue > 0 else { return }
                                  
                                  // Check if already has pending transaction for this date
                                  let calendar = Calendar.current
                                  let startOfDay = calendar.startOfDay(for: occurrence.date)
                                  guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
                                  
                                  let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
                                  let existingPending = entries.contains { entry in
                                      guard let entryDate = entry.date,
                                            entryDate >= startOfDay,
                                            entryDate < endOfDay,
                                            entry.category == "Income",
                                            !entry.isReconciledFlag else { return false }
                                      let titleMatches = entry.title == occurrence.paycheck.name
                                      let amountMatches = abs((entry.usdAmountDecimal - amountValue)) < 0.01
                                      return titleMatches || amountMatches
                                  }
                                  
                                  // Don't create duplicate pending transactions
                                  if existingPending {
                                      HapticManager.shared.billDeleted()
                                      return
                                  }
                                  
                                                  // Ensure amount is positive for income (credit)
                                                  let positiveAmount = max(abs(amountValue), amountValue)
                                                  
                                                  // Save current selected account to restore it
                                                  let previousSelectedAccount = accountViewModel.selectedAccount
                                                  
                                                  // Temporarily select the account to ensure refresh happens
                                                  accountViewModel.selectedAccount = account
                                                  
                                  // Create the pending transaction
                                  _ = accountViewModel.recordLedgerEntry(
                                      for: occurrence.paycheck,
                                      amount: positiveAmount, // Positive amount = credit (addition)
                                      date: occurrence.date,
                                      title: occurrence.paycheck.name ?? "Income",
                                      notes: occurrence.paycheck.notes
                                  )
                                  
                                  // Restore previous selection
                                  accountViewModel.selectedAccount = previousSelectedAccount
                                  
                                  // Refresh all data to ensure UI updates
                                  accountViewModel.refreshData()
                                  
                                  // Enhanced feedback: haptic, sound, and visual confirmation
                                  HapticManager.shared.success()
                              },
                              onEdit: onEditIncome != nil ? { onEditIncome?(occurrence.paycheck) } : nil,
                              onDelete: onDeleteIncome != nil ? { onDeleteIncome?(occurrence.paycheck) } : nil)
                        .environmentObject(accountViewModel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private func billSection(bills: [BillOccurrence]) -> some View {
        if !bills.isEmpty {
            VStack(spacing: 10) {
                ForEach(bills) { occurrence in
                    BillDueRow(occurrence: occurrence, 
                             currencyCode: currencyCode,
                             onEdit: { onEditBill?(occurrence.bill) },
                             onDelete: { onDeleteBill?(occurrence.bill) })
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
    }
    
    private func totalAmount(for data: DayOccurrences) -> Decimal {
        let billsTotal = data.bills.reduce(Decimal.zero) { $0 + ($1.bill.amount?.decimalValue ?? .zero) }
        let incomeTotal = data.paychecks.reduce(Decimal.zero) { $0 + ($1.paycheck.amount?.decimalValue ?? .zero) }
        return incomeTotal - billsTotal
    }
}

// MARK: - Bill Row
struct BillDueRow: View {
    let occurrence: BillOccurrence
    let currencyCode: String
    var compact: Bool = false
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        let bill = occurrence.bill
        HStack {
            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                HStack(spacing: 8) {
                    Text(bill.name ?? "Bill")
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                    statusBadge
                }
                
                if let accountName = bill.account?.name, !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !compact, let paymentCard = bill.paymentCard, !paymentCard.isEmpty {
                    Label(paymentCard, systemImage: "creditcard.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let amountDecimal = bill.amount?.decimalValue {
                Text(amountDecimal, format: .currency(code: currencyCode))
                    .fontWeight(.semibold)
                    .foregroundColor(amountColor)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if occurrence.isProjected {
            Text("Upcoming")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
        } else if occurrence.bill.isPaid {
            Text("Paid")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        }
    }
    
    private var amountColor: Color {
        if occurrence.isProjected {
            return .accentColor
        }
        return occurrence.bill.isPaid ? .green : .primary
    }
}

struct PaycheckRow: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let occurrence: PaycheckOccurrence
    let currencyCode: String
    var compact: Bool = false
    let onAddToAccount: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var isAnimating = false
    
    private var hasPendingTransaction: Bool {
        guard let account = occurrence.paycheck.account,
              let amount = occurrence.paycheck.amount?.decimalValue else { return false }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: occurrence.date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        
        let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
        return entries.contains { entry in
            guard let entryDate = entry.date,
                  entryDate >= startOfDay,
                  entryDate < endOfDay,
                  entry.category == "Income",
                  !entry.isReconciledFlag else { return false }
            
            // Check if it matches this paycheck (by title or amount)
            let titleMatches = entry.title == occurrence.paycheck.name
            let amountMatches = abs((entry.usdAmountDecimal - amount)) < 0.01
            return titleMatches || amountMatches
        }
    }
    
    var body: some View {
        let paycheck = occurrence.paycheck
        let isProjected = occurrence.isProjected
        let isPending = hasPendingTransaction
        
        HStack(spacing: compact ? 8 : 12) {
            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                HStack(spacing: 8) {
                    Text(paycheck.name ?? "Income")
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                    statusBadge(isPending: isPending)
                }
                if let accountName = paycheck.account?.name, !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !compact, let notes = paycheck.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if let amountDecimal = paycheck.amount?.decimalValue {
                    Text(amountDecimal, format: .currency(code: currencyCode))
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                // Action button - simple arrow button for all states
                if paycheck.account != nil {
                    if isPending {
                        // Already pending - show checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    } else {
                        // Show arrow button - tap to mark as pending or add to account
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isAnimating = true
                        }
                        onAddToAccount()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                isAnimating = false
                            }
                        }
                    }) {
                        Image(systemName: isAnimating ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundColor(isAnimating ? .green : .accentColor)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                    }
                    .buttonStyle(.plain)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
            
            if !isPending {
            Button {
                onAddToAccount()
            } label: {
                    Label(isProjected ? "Mark as Pending" : "Add to Account", systemImage: isProjected ? "clock" : "arrow.right.circle")
            }
            .tint(.green)
            }
        }
    }
    
    private func statusBadge(isPending: Bool) -> some View {
        Group {
            if isPending {
                Text("Pending")
                    .foregroundColor(.orange)
            } else if occurrence.isProjected {
                Text("Projected")
                    .foregroundColor(.green)
            } else {
                Text("Processed")
                    .foregroundColor(.green)
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isPending ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
        .clipShape(Capsule())
    }
}


