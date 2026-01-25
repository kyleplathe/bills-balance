import SwiftUI
import CoreData

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BillListView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @State private var showingAddBill = false
    @State private var selectedBill: Bill?
    @State private var showingExportImport = false
    @State private var showingDeleteAlert = false
    @State private var billToDelete: Bill?
    @State private var visibleMonth: Date = Date()
    @State private var showingFutureBills = false
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshTrigger: Bool = false

    @StateObject private var exportManager: BillExportManager

    init() {
        let context = PersistenceController.shared.container.viewContext
        self._exportManager = StateObject(wrappedValue: BillExportManager(context: context))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                collapsibleHeaderView
                billListView
            }
            // iPad optimization
            .navigationViewStyle(StackNavigationViewStyle())
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            HapticManager.shared.buttonTapped()
                            showingAddBill = true
                        }) {
                            Label("Add Bill", systemImage: "plus")
                        }
                        
                        if !billViewModel.bills.isEmpty && !billViewModel.isRunningInSimulator() {
                            Button(action: {
                                HapticManager.shared.exportImportOperation()
                                showingExportImport = true
                            }) {
                                Label("Export/Import", systemImage: "square.and.arrow.up")
                            }
                        }
                        
                        Button(action: {
                            HapticManager.shared.buttonTapped()
                            onboardingManager.startTour()
                        }) {
                            Label("Help & Tour", systemImage: "questionmark.circle")
                        }

                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                AddEditBillView()
                    .environmentObject(billViewModel)
            }
            .sheet(item: $selectedBill) { bill in
                AddEditBillView(bill: bill)
                    .environmentObject(billViewModel)
                    .id(bill.objectID)
            }
            .sheet(isPresented: $showingExportImport) {
                ExportImportView(exportManager: exportManager, billViewModel: billViewModel)
            }



            .onAppear {
                let calendar = Calendar.current
                let now = Date()
                let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
                visibleMonth = currentMonth
            }
            .alert("Delete Bill", isPresented: $showingDeleteAlert) {
                Button("This Bill Only", role: .destructive) {
                    if let bill = billToDelete {
                        billViewModel.deleteBill(bill)
                    }
                    billToDelete = nil
                }
                Button("All Future Bills", role: .destructive) {
                    if let bill = billToDelete {
                        billViewModel.deleteRecurringBillAndFuture(bill)
                    }
                    billToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    billToDelete = nil
                }
            } message: {
                if let bill = billToDelete, let recurrence = bill.recurrence, !recurrence.isEmpty {
                    Text("Do you want to delete this bill only, or all future occurrences of this recurring bill?")
                } else {
                    Text("Are you sure you want to delete this bill? This action cannot be undone.")
                }
            }
        }
    }

    // MARK: - View Components
    private var collapsibleHeaderView: some View {
        VStack(spacing: 6) {
            // Title
            Text("This Month")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            // Remaining Balance
            Text("Remaining Balance")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Dollar Amount
            Text("$\(currentMonthUnpaidTotal, specifier: "%.2f")")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Stats
            HStack(spacing: 20) {
                Text("\(currentMonthUnpaidCount) unpaid")
                    .font(.body)
                    .foregroundColor(.secondary)
                if currentMonthOverdueCount > 0 {
                    Text("\(currentMonthOverdueCount) overdue")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
    }

    private var billListView: some View {
        List {
            currentAndNextMonthsSection
            monthlyAverageSection
        }
        .listStyle(PlainListStyle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
            }
        )
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = -value
        }
        .refreshable {
            billViewModel.fetchBills()
            // Clear cache when refreshing
            cachedGroupedBills = [:]
            cachedFutureBills = [:]
            cachedSortedMonthKeys = []
            cachedVisibleMonthKeys = []
            lastCacheUpdate = Date.distantPast
        }
    }
    
    // MARK: - Optimized View Components
    
    private var currentAndNextMonthsSection: some View {
        ForEach(visibleMonthKeys, id: \.self) { monthDate in
            Section {
                ForEach((groupedBills[monthDate] ?? []).sorted { (bill1: Bill, bill2: Bill) in
                    let date1 = bill1.dueDate ?? .distantFuture
                    let date2 = bill2.dueDate ?? .distantFuture
                    return date1 < date2
                }) { bill in
                    BillRowView(bill: bill)
                        .opacity(isFutureMonth(monthDate) ? 0.8 : 1.0)
                        .contentShape(Rectangle())
                        .onLongPressGesture {
                            HapticManager.shared.longPressDetected()
                            selectedBill = bill
                        }
                        .animation(.easeInOut(duration: 0.2), value: bill.isPaid)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                HapticManager.shared.buttonTapped()
                                billToDelete = bill
                                showingDeleteAlert = true
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("Edit") {
                                HapticManager.shared.buttonTapped()
                                selectedBill = bill
                            }
                            .tint(.blue)
                            
                            if !bill.isPaid {
                                Button("Mark Paid") {
                                    HapticManager.shared.buttonTapped()
                                    billViewModel.togglePaidStatus(for: bill)
                                    // Force immediate UI refresh to update counts
                                    DispatchQueue.main.async {
                                        billViewModel.fetchBills()
                                        refreshTrigger.toggle()
                                    }
                                }
                                .tint(.green)
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                HapticManager.shared.buttonTapped()
                                selectedBill = bill
                            }
                            
                            if !bill.isPaid {
                                Button("Mark Paid") {
                                    HapticManager.shared.buttonTapped()
                                    billViewModel.togglePaidStatus(for: bill)
                                    // Force immediate UI refresh to update counts
                                    DispatchQueue.main.async {
                                        billViewModel.fetchBills()
                                        refreshTrigger.toggle()
                                    }
                                }
                            }
                            
                            Button("Delete", role: .destructive) {
                                HapticManager.shared.buttonTapped()
                                billToDelete = bill
                                showingDeleteAlert = true
                            }
                        }
                }
            } header: {
                SectionHeaderView(monthDate: monthDate, bills: groupedBills[monthDate] ?? [])
                    .opacity(isFutureMonth(monthDate) ? 0.7 : 1.0)
                    .id("\(monthDate)-\(groupedBills[monthDate]?.count ?? 0)")
            }
        }
    }
    
    @ViewBuilder
    private var futureBillsSection: some View {
        if hasFutureBills {
            Section {
                if showingFutureBills {
                    let futureBills = getFutureBills()
                    ForEach(Array(futureBills.keys).sorted(), id: \.self) { monthDate in
                        Section {
                            ForEach((futureBills[monthDate] ?? []).sorted { (bill1: Bill, bill2: Bill) in
                                let date1 = bill1.dueDate ?? .distantFuture
                                let date2 = bill2.dueDate ?? .distantFuture
                                return date1 < date2
                            }) { bill in
                                VirtualBillRowView(bill: bill, onEdit: {
                                    // Find the original recurring bill and edit it
                                    if let originalBill = findOriginalBill(for: bill) {
                                        selectedBill = originalBill
                                    }
                                })
                                .opacity(0.7)
                                .contentShape(Rectangle())
                                .animation(.easeInOut(duration: 0.2), value: bill.isPaid)
                            }
                        } header: {
                            SectionHeaderView(monthDate: monthDate, bills: futureBills[monthDate] ?? [])
                                .opacity(0.6)
                                .id("future-\(monthDate)-\(futureBills[monthDate]?.count ?? 0)")
                        }
                    }
                }
                            } header: {
                    FutureBillsHeaderView(
                        isExpanded: $showingFutureBills,
                        billCount: futureBillsSummary.count,
                        totalAmount: futureBillsSummary.total
                    )
                    .onChange(of: showingFutureBills) { _, newValue in
                        if !newValue {
                            // Clear cache when section is collapsed
                            cachedFutureBills = [:]
                        }
                    }
                }
        }
    }



    // MARK: - Helper Methods
    private func isFutureMonth(_ monthDate: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return monthDate > currentMonth
    }
    
    private func findOriginalBill(for virtualBill: Bill) -> Bill? {
        // Find the original recurring bill that generated this virtual bill
        return billViewModel.bills.first { bill in
            bill.name == virtualBill.name &&
            bill.recurrence == virtualBill.recurrence &&
            !(bill.recurrence?.isEmpty ?? true)
        }
    }

    // MARK: - Computed Properties (Optimized)
    private var currentMonthUnpaidTotal: Double {
        let _ = refreshTrigger // Force refresh when trigger changes
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return billViewModel.listViewBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            return calendar.isDate(dueDate, equalTo: currentMonth, toGranularity: .month) && !bill.isPaid
        }
        .reduce(0) { $0 + ($1.amount?.doubleValue ?? 0) }
    }
    private var currentMonthUnpaidCount: Int {
        let _ = refreshTrigger // Force refresh when trigger changes
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return billViewModel.listViewBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            return calendar.isDate(dueDate, equalTo: currentMonth, toGranularity: .month) && !bill.isPaid
        }.count
    }
    private var currentMonthOverdueCount: Int {
        let _ = refreshTrigger // Force refresh when trigger changes
        let now = Date()
        let overdueBills = billViewModel.listViewBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            // Only count unpaid bills that are overdue
            let isOverdue = dueDate < now
            return isOverdue && !bill.isPaid
        }
        
        // Debug logging
        if !overdueBills.isEmpty {
            print("Overdue bills found: \(overdueBills.count)")
            for bill in overdueBills {
                print("  - \(bill.name ?? "Unknown"): due \(bill.dueDate?.formatted() ?? "No date"), paid: \(bill.isPaid)")
            }
        }
        
        return overdueBills.count
    }

    // Cache state
    @State private var cachedGroupedBills: [Date: [Bill]] = [:]
    @State private var cachedFutureBills: [Date: [Bill]] = [:]
    @State private var lastCacheUpdate: Date = Date.distantPast
    
    private var groupedBills: [Date: [Bill]] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        // Cache for 5 seconds to avoid excessive recomputation
        if Date().timeIntervalSince(lastCacheUpdate) < 5 {
            return cachedGroupedBills
        }
        
        // Get filtered bills for list view (excludes old paid auto-pay bills)
        let actualBills = billViewModel.listViewBills
        
        let filteredBills = actualBills.filter { bill in
            // Always include unpaid bills
            if !bill.isPaid {
                return true
            }
            // Include paid bills that were paid recently (within 2 days)
            if let paidDate = bill.paidDate {
                let daysSincePaid = calendar.dateComponents([.day], from: paidDate, to: now).day ?? 0
                return daysSincePaid <= 2
            }
            // Include any other bills (shouldn't happen but safety net)
            return true
        }
        
        let grouped = Dictionary(grouping: filteredBills) { (bill: Bill) in
            guard let dueDate = bill.dueDate else { return Date.distantFuture }
            
            // If bill is overdue (paid or unpaid), group it with current month
            if dueDate < now {
                let comps = calendar.dateComponents([.year, .month], from: currentMonth)
                let groupDate = calendar.date(from: comps) ?? Date.distantFuture
                return groupDate
            }
            
            // Otherwise group by original due date
            let comps = calendar.dateComponents([.year, .month], from: dueDate)
            let groupDate = calendar.date(from: comps) ?? Date.distantFuture
            return groupDate
        }
        
        // Update cache asynchronously to avoid state modification during view update
        DispatchQueue.main.async {
            self.cachedGroupedBills = grouped
            self.lastCacheUpdate = Date()
        }
        
        return grouped
    }
    
    // Lazy-loaded future bills - only generated when needed
    private func getFutureBills() -> [Date: [Bill]] {
        if !showingFutureBills {
            return [:]
        }
        
        // Use cached future bills if available
        if !cachedFutureBills.isEmpty {
            return cachedFutureBills
        }
        
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        var futureBills: [Date: [Bill]] = [:]
        
        // Generate virtual bills for future months (next 3 months)
        for monthOffset in 3...5 {
            if let futureMonth = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth) {
                let virtualBills = billViewModel.generateVirtualBillsForMonth(futureMonth)
                if !virtualBills.isEmpty {
                    futureBills[futureMonth] = virtualBills
                }
            }
        }
        
        // Cache the future bills asynchronously
        DispatchQueue.main.async {
            self.cachedFutureBills = futureBills
        }
        
        return futureBills
    }
    @State private var cachedSortedMonthKeys: [Date] = []
    @State private var cachedVisibleMonthKeys: [Date] = []
    
    private var sortedMonthKeys: [Date] {
        // Use cached value if available
        if !cachedSortedMonthKeys.isEmpty {
            return cachedSortedMonthKeys
        }
        
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var keys = groupedBills.keys.sorted()
        if let currentIndex = keys.firstIndex(where: { (date: Date) in
            calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        }) {
            let currentKey = keys.remove(at: currentIndex)
            keys.insert(currentKey, at: 0)
        }
        
        // Cache asynchronously
        DispatchQueue.main.async {
            self.cachedSortedMonthKeys = keys
        }
        
        return keys
    }
    
    private var visibleMonthKeys: [Date] {
        // Use cached value if available
        if !cachedVisibleMonthKeys.isEmpty {
            return cachedVisibleMonthKeys
        }
        
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        // Get next 2 months after current
        let nextMonth1 = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        let nextMonth2 = calendar.date(byAdding: .month, value: 2, to: currentMonth) ?? currentMonth
        
        let visible = sortedMonthKeys.filter { monthDate in
            calendar.isDate(monthDate, equalTo: currentMonth, toGranularity: .month) ||
            calendar.isDate(monthDate, equalTo: nextMonth1, toGranularity: .month) ||
            calendar.isDate(monthDate, equalTo: nextMonth2, toGranularity: .month)
        }
        
        // Cache asynchronously
        DispatchQueue.main.async {
            self.cachedVisibleMonthKeys = visible
        }
        
        return visible
    }
    
    private var futureMonthKeys: [Date] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let nextMonth3 = calendar.date(byAdding: .month, value: 3, to: currentMonth) ?? currentMonth
        
        return sortedMonthKeys.filter { monthDate in
            monthDate >= nextMonth3
        }
    }
    
    private var hasFutureBills: Bool {
        return !futureMonthKeys.isEmpty
    }
    
    private var futureBillsSummary: (count: Int, total: Double) {
        // Simple estimation based on recurring bills
        let recurringBills = billViewModel.listViewBills.filter { !($0.recurrence?.isEmpty ?? true) }
        let estimatedCount = recurringBills.count * 3 // Rough estimate: 3 months worth
        let estimatedTotal = recurringBills.reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) } * 3
        
        return (estimatedCount, estimatedTotal)
    }
    
    // MARK: - Smart Future Bills Calculations
    private var next30DaysTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        
        return billViewModel.listViewBills
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                return dueDate >= now && dueDate <= thirtyDaysFromNow && !bill.isPaid
            }
            .reduce(0) { total, bill in
                total + (bill.amount?.doubleValue ?? 0)
            }
    }
    
    private var next30DaysCount: Int {
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        
        return billViewModel.listViewBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            return dueDate >= now && dueDate <= thirtyDaysFromNow && !bill.isPaid
        }.count
    }
    
    private var next3MonthsTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        let threeMonthsFromNow = calendar.date(byAdding: .month, value: 3, to: now) ?? now
        
        return billViewModel.listViewBills
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                // Only include recurring bills for monthly average calculation
                let isRecurring = !(bill.recurrence?.isEmpty ?? true)
                return dueDate >= now && dueDate <= threeMonthsFromNow && !bill.isPaid && isRecurring
            }
            .reduce(0) { total, bill in
                total + (bill.amount?.doubleValue ?? 0)
            }
    }
    
    private var next3MonthsCount: Int {
        let calendar = Calendar.current
        let now = Date()
        let threeMonthsFromNow = calendar.date(byAdding: .month, value: 3, to: now) ?? now
        
        return billViewModel.listViewBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            // Only include recurring bills for monthly average calculation
            let isRecurring = !(bill.recurrence?.isEmpty ?? true)
            return dueDate >= now && dueDate <= threeMonthsFromNow && !bill.isPaid && isRecurring
        }.count
    }
    
    private var monthlyAverage: Double {
        let total = next3MonthsTotal
        return total > 0 ? total / 3.0 : 0
    }
    

    
    // MARK: - Monthly Average Section
    private var monthlyAverageSection: some View {
        Section {
            HStack {
                VStack(alignment: .center, spacing: 4) {
                    Text("Monthly Average")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("From recurring bills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                VStack(alignment: .center, spacing: 4) {
                    Text("~$\(monthlyAverage, specifier: "%.0f")/month")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Bill Row View (Clean Design)
struct BillRowView: View {
    let bill: Bill
    @EnvironmentObject private var billViewModel: BillViewModel
    
    private func isOverdue() -> Bool {
        guard let dueDate = bill.dueDate else { return false }
        return dueDate < Date() && !bill.isPaid
    }
    
    private func isPaidEarly() -> Bool {
        guard let dueDate = bill.dueDate else { return false }
        return bill.isPaid && dueDate > Date()
    }
    
    private func formatRecurrence(_ recurrence: String) -> String {
        if recurrence.hasPrefix("custom:") {
            let components = recurrence.components(separatedBy: ":")
            if components.count >= 3 {
                let value = components[1]
                let unit = components[2]
                
                return "\(value) \(unit)"
            }
        }
        
        // Make recurrence more user-friendly
        switch recurrence.lowercased() {
        case "weekly":
            return "Weekly"
        case "monthly":
            return "Monthly"
        case "yearly":
            return "Yearly"
        case "bi-yearly":
            return "6 months"
        case "quarterly":
            return "3 months"
        case "semi-annually":
            return "6 months"
        default:
            return recurrence.capitalized
        }
    }
    
    private func daysUntilDue() -> Int {
        guard let dueDate = bill.dueDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }
    
    private func formatDateWithoutYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func needsMoreSpace() -> Bool {
        let days = daysUntilDue()
        // Increase spacing when days indicator is longer
        return abs(days) >= 10 || (days < 0 && abs(days) >= 5)
    }
    
    private func getSpacing() -> CGFloat {
        let days = daysUntilDue()
        if abs(days) >= 10 || (days < 0 && abs(days) >= 5) {
            return 6
        } else if abs(days) >= 5 {
            return 4
        } else {
            return 2
        }
    }
    

    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Business expense indicator
            if bill.isBusinessExpense {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple)
                    .frame(width: 4, height: 16)
            }
            
            // Main content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(bill.name ?? "Unknown Bill")
                        .font(.system(.title3, design: .default))
                        .fontWeight(.medium)
                        .strikethrough(bill.isPaid)
                        .foregroundColor(bill.isPaid ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    
                    if bill.isPaid {
                        Text("PAID")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    } else if isOverdue() {
                        Text("OVERDUE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    if bill.isAutoPay {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .offset(x: bill.isPaid ? 8 : 0)
                            .animation(.easeInOut(duration: 0.3), value: bill.isPaid)
                    }
                    
                    if bill.isBusinessExpense {
                        Image(systemName: "briefcase.fill")
                            .font(.subheadline)
                            .foregroundColor(.purple)
                            .offset(x: bill.isPaid ? 8 : 0)
                            .animation(.easeInOut(duration: 0.3), value: bill.isPaid)
                    }
                    
                    Spacer()
                }
                
                // Due date and status info
                if let dueDate = bill.dueDate {
                    HStack(spacing: 6) {
                        Text(formatDateWithoutYear(dueDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        // Days indicator - only show for unpaid bills
                        if !bill.isPaid {
                            let days = daysUntilDue()
                            if days != 0 {
                                if days > 0 {
                                    Text("• \(days) day\(days == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Text("• \(abs(days)) day\(abs(days) == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }
                        
                        // Recurrence
                        if let recurrence = bill.recurrence, !recurrence.isEmpty {
                            Text("• \(formatRecurrence(recurrence))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Amount and action
            VStack(alignment: .trailing, spacing: 6) {
                Text("$\(bill.amount?.stringValue ?? "0")")
                    .font(.system(.title3, design: .default))
                    .fontWeight(.semibold)
                    .foregroundColor(bill.isPaid ? .green : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Button(action: {
                    billViewModel.togglePaidStatus(for: bill)
                }) {
                    Image(systemName: bill.isPaid ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(bill.isPaid ? .green : .gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        if isPaidEarly() {
            return .green
        } else if bill.isPaid {
            return .gray
        } else if isOverdue() {
            return .red
        } else {
            return .blue
        }
    }
    
    private var borderColor: Color {
        if isPaidEarly() {
            return .green.opacity(0.3)
        } else if bill.isPaid {
            return .gray.opacity(0.2)
        } else if isOverdue() {
            return .red.opacity(0.3)
        } else {
            return .gray.opacity(0.2)
        }
    }
}

// MARK: - Virtual Bill Row View (for future bills)
struct VirtualBillRowView: View {
    let bill: Bill
    let onEdit: () -> Void
    
    private func daysUntilDue() -> Int {
        guard let dueDate = bill.dueDate else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        return calendar.dateComponents([.day], from: now, to: dueDate).day ?? 0
    }
    
    private func isWithinThreeMonths() -> Bool {
        guard let dueDate = bill.dueDate else { return false }
        let calendar = Calendar.current
        let threeMonthsFromNow = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        return dueDate <= threeMonthsFromNow
    }
    
    private func formatRecurrence(_ recurrence: String) -> String {
        if recurrence.hasPrefix("custom:") {
            let components = recurrence.components(separatedBy: ":")
            if components.count >= 3 {
                let value = components[1]
                let unit = components[2]
                return "\(value) \(unit)"
            }
        }
        
        switch recurrence.lowercased() {
        case "weekly":
            return "Weekly"
        case "biweekly":
            return "Bi-weekly"
        case "monthly":
            return "Monthly"
        case "quarterly":
            return "Quarterly"
        case "yearly":
            return "Yearly"
        default:
            return recurrence
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left side - Bill info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bill.name ?? "Unknown Bill")
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    // Future bill indicator
                    Text(isWithinThreeMonths() ? "(Active)" : "(Future)")
                        .font(.caption)
                        .foregroundColor(isWithinThreeMonths() ? .orange : .secondary)
                        .fontWeight(isWithinThreeMonths() ? .medium : .regular)
                }
                
                HStack(spacing: 8) {
                    // Due date
                    if let dueDate = bill.dueDate {
                        Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.subheadline)
                            .foregroundColor(isWithinThreeMonths() ? .orange : .blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    // Days indicator
                    let days = daysUntilDue()
                    if days != 0 {
                        if days > 0 {
                            Text("• \(days) day\(days == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(isWithinThreeMonths() ? .orange : .blue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text("• \(abs(days)) day\(abs(days) == 1 ? "" : "s")")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    
                    // Recurrence
                    if let recurrence = bill.recurrence, !recurrence.isEmpty {
                        Text("• \(formatRecurrence(recurrence))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Right side - Amount and edit button
            VStack(alignment: .trailing, spacing: 6) {
                Text("$\(bill.amount?.stringValue ?? "0")")
                    .font(.system(.title3, design: .default))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(isWithinThreeMonths() ? .orange : .blue)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isWithinThreeMonths() ? Color.orange.opacity(0.1) : Color(.systemGray6).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isWithinThreeMonths() ? Color.orange.opacity(0.3) : Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Section Header View (Clean Design)
struct SectionHeaderView: View {
    let monthDate: Date
    let bills: [Bill]
    
    private func hasOverdueBills() -> Bool {
        let overdueBills = bills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            return dueDate < Date() && !bill.isPaid
        }
        let hasOverdue = !overdueBills.isEmpty
        print("Section \(monthDate.formatted(.dateTime.month(.abbreviated).year())): \(overdueBills.count) overdue bills, hasOverdue: \(hasOverdue)")
        return hasOverdue
    }
    
    private func isCurrentMonth() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.isDate(monthDate, equalTo: currentMonth, toGranularity: .month)
    }
    
    private func totalAmount() -> Double {
        return bills.reduce(0) { $0 + ($1.amount?.doubleValue ?? 0) }
    }
    

    
    private func unpaidBills() -> [Bill] {
        return bills.filter { !$0.isPaid }
    }
    
    private func unpaidTotal() -> Double {
        return bills.filter { !$0.isPaid }.reduce(0) { $0 + ($1.amount?.doubleValue ?? 0) }
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(monthDate.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.system(.subheadline, design: .default))
                    .fontWeight(.medium)
                    .foregroundColor(hasOverdueBills() ? .red : .secondary)
                    .animation(.easeInOut(duration: 0.3), value: hasOverdueBills())
                // For current month, do NOT show 'Remaining Balance' or dollar amount
                if !isCurrentMonth() {
                    Text("•")
                        .font(.system(.subheadline, design: .default))
                        .foregroundColor(.secondary)
                    Text("$\(unpaidTotal(), specifier: "%.2f")")
                        .font(.system(.subheadline, design: .default))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // Bill count on the right
            if !unpaidBills().isEmpty {
                let count = unpaidBills().count
                Text("\(count) \(isCurrentMonth() ? "unpaid" : count == 1 ? "bill" : "bills")")
                    .font(.system(.subheadline, design: .default))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}



// MARK: - Future Bills Header View
struct FutureBillsHeaderView: View {
    @Binding var isExpanded: Bool
    let billCount: Int
    let totalAmount: Double
    
    var body: some View {
        Button(action: {
            HapticManager.shared.futureBillsExpanded()
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Future Bills")
                            .font(.system(.subheadline, design: .default))
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(.subheadline, design: .default))
                            .foregroundColor(.secondary)
                        
                        Text("+3 months")
                            .font(.system(.subheadline, design: .default))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(billCount) bills • $\(totalAmount, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    BillListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(NotificationManager())
        .environmentObject(BillViewModel(context: PersistenceController.preview.container.viewContext, notificationManager: NotificationManager()))
} 
