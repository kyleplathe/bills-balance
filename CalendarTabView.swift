//
//  CalendarTabView.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import SwiftUI

struct CalendarTabView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var paycheckViewModel: PaycheckViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Binding var selectedMonth: Date?
    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var showDayDrawer: Bool = false
    @State private var showingBillEditor = false
    @State private var billToEdit: Bill?
    @State private var showingPaycheckEditor = false
    @State private var paycheckToEdit: Paycheck?
    @State private var paycheckOccurrenceDate: Date?
    @State private var isLandscape: Bool = false
    @State private var showPaidBillsInLandscape: Bool = false
    @State private var billToDelete: Bill?
    @State private var paycheckToDelete: Paycheck?
    @State private var showingDeleteBillAlert = false
    @State private var showingDeletePaycheckAlert = false
    
    init(selectedMonth: Binding<Date?> = .constant(nil)) {
        self._selectedMonth = selectedMonth
    }
    
    private let calendar = Calendar.current
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                content(for: proxy.size)
                    .onAppear {
                        isLandscape = proxy.size.width > proxy.size.height
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        isLandscape = newSize.width > newSize.height
                    }
            }
            .navigationTitle(isLandscape ? "" : "Calendar")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Add Bill") { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                presentBillEditor(nil)
                            }
                        }
                        Button("Add Income") { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                presentPaycheckEditor(nil)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                    }
                    .transaction { transaction in
                        transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
                    }
                }
            }
        }
        .sheet(isPresented: $showingBillEditor) {
            AddEditBillView(bill: billToEdit, defaultDate: selectedDate)
                .environmentObject(billViewModel)
                .environmentObject(accountViewModel)
        }
        .sheet(isPresented: $showingPaycheckEditor) {
            PaycheckEditorSheet(paycheck: paycheckToEdit, 
                              defaultDate: selectedDate,
                              occurrenceDate: paycheckOccurrenceDate)
                .environmentObject(paycheckViewModel)
                .environmentObject(accountViewModel)
        }
        .alert("Delete Bill", isPresented: $showingDeleteBillAlert, presenting: billToDelete) { bill in
            Button("Cancel", role: .cancel) {
                billToDelete = nil
            }
            // Check if bill is recurring
            if let recurrenceType = bill.recurrenceType, recurrenceType != "none" {
                Button("This Bill Only", role: .destructive) {
                    billViewModel.deleteBill(bill)
                    billToDelete = nil
                }
                Button("This and Future Bills", role: .destructive) {
                    billViewModel.deleteRecurringBillAndFuture(bill)
                    billToDelete = nil
                }
            } else {
                Button("Delete", role: .destructive) {
                    billViewModel.deleteBill(bill)
                    billToDelete = nil
                }
            }
        } message: { bill in
            if let recurrenceType = bill.recurrenceType, recurrenceType != "none" {
                Text("Do you want to delete just this bill, or delete this bill and all future bills in the series?")
            } else {
                Text("Are you sure you want to delete \"\(bill.name ?? "this bill")\"? This action cannot be undone.")
            }
        }
        .alert("Delete Income", isPresented: $showingDeletePaycheckAlert, presenting: paycheckToDelete) { paycheck in
            Button("Cancel", role: .cancel) {
                paycheckToDelete = nil
            }
            // Check if paycheck is recurring
            if let recurrenceType = paycheck.recurrenceType, recurrenceType != "none" {
                Button("This Income Only", role: .destructive) {
                    // For recurring income, deleting the template removes all future occurrences
                    // This is the same as "all future" since paychecks are templates
                    paycheckViewModel.deletePaycheck(paycheck)
                    paycheckToDelete = nil
                }
                Button("Delete All Future Income", role: .destructive) {
                    // Delete the template which removes all future occurrences
                    paycheckViewModel.deletePaycheck(paycheck)
                    paycheckToDelete = nil
                }
            } else {
                Button("Delete", role: .destructive) {
                    paycheckViewModel.deletePaycheck(paycheck)
                    paycheckToDelete = nil
                }
            }
        } message: { paycheck in
            if let recurrenceType = paycheck.recurrenceType, recurrenceType != "none" {
                Text("Deleting this income will remove all future occurrences. This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \"\(paycheck.name ?? "this income")\"? This action cannot be undone.")
            }
        }
        .onAppear {
            let today = Date()
            currentMonth = startOfMonth(for: today)
            selectedDate = calendar.startOfDay(for: today)
            showDayDrawer = false
            
            // Initialize shared month selection
            if selectedMonth == nil {
                selectedMonth = currentMonth
            } else {
                // Sync currentMonth with selectedMonth if provided
                currentMonth = startOfMonth(for: selectedMonth ?? today)
            }
        }
        .onChange(of: selectedMonth) { oldValue, newValue in
            if let newValue = newValue, !calendar.isDate(newValue, equalTo: currentMonth, toGranularity: .month) {
                currentMonth = startOfMonth(for: newValue)
            }
        }
    }
    
    // MARK: - Header
    private var monthHeader: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(-1)
                }
            } label: {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary))
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: horizontalSizeClass == .regular && isLandscape ? .leading : .center, spacing: 4) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(.title2.weight(.semibold))
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        let today = Date()
                        currentMonth = startOfMonth(for: today)
                        selectDate(today)
                    }
                } label: {
                    Label("Today", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.18))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: horizontalSizeClass == .regular && isLandscape ? .leading : .center)
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(1)
                }
            } label: {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary))
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
    
    private func changeMonth(_ offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth) else { return }
        currentMonth = startOfMonth(for: newMonth)
        let anchorDate = calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) ? selectedDate : currentMonth
        selectDate(anchorDate, showDrawer: false)
        
        // Update shared month selection for landscape mode
        selectedMonth = currentMonth
    }
    
    // MARK: - Insights
    private var insightSection: some View {
        CalendarInsightGrid(insights: insights, currencyCode: currencyCode)
    }
    
    // MARK: - Living Means View
    @ViewBuilder
    private var livingMeansView: some View {
        if let meansData = livingMeansPercentage {
            Text(livingMeansText(for: meansData))
                .font(.subheadline)
                .foregroundColor(meansData.isBelow ? .green : .orange)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private func livingMeansText(for meansData: (percentage: Decimal, isBelow: Bool)) -> String {
        let percentage = abs(meansData.percentage)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        
        let percentageString = formatter.string(from: NSDecimalNumber(decimal: percentage)) ?? "0"
        return meansData.isBelow 
            ? "You are living \(percentageString)% below your means"
            : "You are living \(percentageString)% above your means"
    }
    
    private var insights: [CalendarInsight] {
        var items: [CalendarInsight] = []
        let currentStats = monthStats(for: currentMonth)
        if currentStats.remaining > 0 {
            items.append(CalendarInsight(title: "Remaining",
                                         subtitle: monthFormatter.string(from: currentMonth),
                                         amount: currentStats.remaining,
                                         tint: .accentColor))
        }
        let incomeTotal = incomeStats(for: currentMonth)
        if incomeTotal > 0 {
            items.append(CalendarInsight(title: "Income",
                                         subtitle: monthFormatter.string(from: currentMonth),
                                         amount: incomeTotal,
                                         tint: .green))
        }
        let upcoming = upcomingSevenDayOutflow
        if upcoming > 0 {
            items.append(CalendarInsight(title: "Next 7 days",
                                         subtitle: "Projected outflow",
                                         amount: upcoming,
                                         tint: .orange))
        }
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            let nextStats = monthStats(for: nextMonth)
            if nextStats.totalDue > 0 {
                items.append(CalendarInsight(title: monthFormatter.string(from: nextMonth),
                                             subtitle: "Projected bills",
                                             amount: nextStats.totalDue,
                                             tint: Color.blue))
            }
            let nextIncome = incomeStats(for: nextMonth)
            if nextIncome > 0 {
                items.append(CalendarInsight(title: "\(monthFormatter.string(from: nextMonth)) Income",
                                             subtitle: "Projected",
                                             amount: nextIncome,
                                             tint: Color.green.opacity(0.8)))
            }
        }
        return Array(items.prefix(4))
    }
    
    private var monthOccurrences: [BillOccurrence] {
        guard let interval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        return occurrences(in: interval)
    }
    
    private var monthPaycheckOccurrences: [PaycheckOccurrence] {
        guard let interval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        return paycheckViewModel.occurrences(in: interval)
    }
    
    private var billsByDay: [Date: BillDaySummary] {
        var summaries: [Date: BillDaySummary] = [:]
        for occurrence in monthOccurrences {
            let key = calendar.startOfDay(for: occurrence.date)
            var summary = summaries[key] ?? BillDaySummary()
            if occurrence.isProjected {
                summary.projected += 1
                summary.projectedTotal += occurrence.bill.amount?.decimalValue ?? .zero
            } else if occurrence.bill.isPaid {
                summary.actualPaid += 1
                summary.actualPaidTotal += occurrence.bill.amount?.decimalValue ?? .zero
            } else {
                summary.actualUnpaid += 1
                summary.actualUnpaidTotal += occurrence.bill.amount?.decimalValue ?? .zero
            }
            summaries[key] = summary
        }
        for occurrence in monthPaycheckOccurrences {
            let key = calendar.startOfDay(for: occurrence.date)
            var summary = summaries[key] ?? BillDaySummary()
            summary.incomeCount += 1
            summary.incomeTotal += occurrence.paycheck.amount?.decimalValue ?? .zero
            summaries[key] = summary
        }
        return summaries
    }
    
    private var occurrencesByDay: [Date: DayOccurrences] {
        var result: [Date: DayOccurrences] = [:]
        for occurrence in monthOccurrences {
            let key = calendar.startOfDay(for: occurrence.date)
            var day = result[key] ?? DayOccurrences()
            day.bills.append(occurrence)
            result[key] = day
        }
        for occurrence in monthPaycheckOccurrences {
            let key = calendar.startOfDay(for: occurrence.date)
            var day = result[key] ?? DayOccurrences()
            day.paychecks.append(occurrence)
            result[key] = day
        }
        return result
    }
    
    private var currentMonthDayOccurrences: [(date: Date, data: DayOccurrences)] {
        let allOccurrences = occurrencesByDay
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
        
        // In landscape, filter out paid bills unless toggle is on
        if isLandscape && !showPaidBillsInLandscape {
            return allOccurrences
                .map { (date, data) in
                    let filteredBills = data.bills.filter { !$0.bill.isPaid }
                    var filteredData = data
                    filteredData.bills = filteredBills
                    return (date, filteredData)
                }
                .filter { !$0.data.bills.isEmpty || !$0.data.paychecks.isEmpty } // Remove days with no bills or income
        }
        
        return allOccurrences
    }

    private var upcomingSevenDayOutflow: Decimal {
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return .zero }
        let interval = DateInterval(start: start, end: end)
        return occurrences(in: interval).reduce(Decimal.zero) { partial, occurrence in
            if occurrence.bill.isPaid { return partial }
            return partial + (occurrence.bill.amount?.decimalValue ?? .zero)
        }
    }
    
    // MARK: - Selection & Drawer
    private func selectDate(_ date: Date, showDrawer: Bool = true) {
        selectedDate = calendar.startOfDay(for: date)
        if showDrawer {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showDayDrawer = true
            }
        }
    }
    
    private func dismissDayDrawer() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showDayDrawer = false
        }
    }
    
    private func presentBillEditor(_ bill: Bill?) {
        billToEdit = bill
        showingBillEditor = true
        showDayDrawer = false
    }
    
    private func presentPaycheckEditor(_ paycheck: Paycheck?, occurrenceDate: Date? = nil) {
        paycheckToEdit = paycheck
        paycheckOccurrenceDate = occurrenceDate
        showingPaycheckEditor = true
        showDayDrawer = false
    }
    
    private func occurrences(for date: Date) -> [BillOccurrence] {
        let key = calendar.startOfDay(for: date)
        return occurrencesByDay[key]?.bills ?? []
    }

    private func incomeOccurrences(for date: Date) -> [PaycheckOccurrence] {
        let key = calendar.startOfDay(for: date)
        return occurrencesByDay[key]?.paychecks ?? []
    }
    
    // MARK: - Data helpers
    private func monthStats(for month: Date) -> MonthStats {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return MonthStats() }
        return occurrences(in: interval).reduce(into: MonthStats()) { stats, occurrence in
            let amount = occurrence.bill.amount?.decimalValue ?? .zero
            if occurrence.isProjected {
                stats.projected += 1
                stats.projectedTotal += amount
            } else if occurrence.bill.isPaid {
                stats.paid += 1
                stats.paidTotal += amount
            } else {
                stats.unpaid += 1
                stats.unpaidTotal += amount
            }
            }
    }
    
    private func occurrences(in interval: DateInterval) -> [BillOccurrence] {
        let projectionStart = startOfMonth(for: Date())
        let projectionLimit = calendar.date(byAdding: .month, value: 4, to: projectionStart) ?? interval.end
        let allowProjection = interval.start < projectionLimit
        
        var occurrences: [BillOccurrence] = []
        var existingIdentifiers: Set<String> = []
        var actualDatesBySeries: [UUID: Set<Date>] = [:]
        
        let sourceBills = billViewModel.allBills()
        for bill in sourceBills {
            guard let dueDate = bill.dueDate else { continue }
            let day = calendar.startOfDay(for: dueDate)
            let identifier = occurrenceIdentifier(for: bill, on: dueDate)
            
            if interval.contains(dueDate) {
                occurrences.append(BillOccurrence(id: identifier, bill: bill, date: dueDate, isProjected: false))
                existingIdentifiers.insert(identifier)
            }
            
            if let seriesKey = seriesKey(for: bill) {
                actualDatesBySeries[seriesKey, default: []].insert(day)
            }
        }
        
        guard allowProjection else {
            return occurrences.sorted { $0.date < $1.date }
        }
        
        for bill in sourceBills {
            guard
                let recurrenceType = bill.recurrenceType,
                recurrenceType != "none",
                let dueDate = bill.dueDate
            else { continue }
            
            let intervalValue = max(Int(bill.recurrenceInterval), 1)
            let seriesKey = seriesKey(for: bill)
            
            var nextDate = dueDate
            
            while nextDate < interval.start {
                guard let candidate = nextRecurrenceDate(from: nextDate, type: recurrenceType, interval: intervalValue) else { break }
                if candidate == nextDate { break }
                nextDate = candidate
                if nextDate >= projectionLimit { break }
            }
            
            while nextDate < interval.end, nextDate < projectionLimit {
                if nextDate >= interval.start {
                    let day = calendar.startOfDay(for: nextDate)
                    let identifier = occurrenceIdentifier(for: bill, on: nextDate)
                    let hasActual = seriesKey.flatMap { actualDatesBySeries[$0]?.contains(day) } ?? false
                    if !hasActual && !existingIdentifiers.contains(identifier) {
                        occurrences.append(BillOccurrence(id: identifier, bill: bill, date: nextDate, isProjected: true))
                        existingIdentifiers.insert(identifier)
                    }
                }
                guard let candidate = nextRecurrenceDate(from: nextDate, type: recurrenceType, interval: intervalValue) else { break }
                if candidate == nextDate { break }
                nextDate = candidate
            }
        }
        
        return occurrences.sorted { $0.date < $1.date }
    }
    
    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func occurrenceIdentifier(for bill: Bill, on date: Date) -> String {
        let base = bill.objectID.uriRepresentation().absoluteString
        let day = calendar.startOfDay(for: date).timeIntervalSince1970
        return "\(base)#\(day)"
    }
    
    private func seriesKey(for bill: Bill) -> UUID? {
        if let seriesId = bill.seriesId {
            return seriesId
        }
        return bill.id
    }
    
    private func nextRecurrenceDate(from date: Date, type: String, interval: Int) -> Date? {
        let next = RecurrenceCalculator.nextDate(from: date, type: type, interval: interval, calendar: calendar)
        return next == date ? nil : next
    }

    private func incomeStats(for month: Date) -> Decimal {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return .zero }
        return paycheckViewModel.occurrences(in: interval).reduce(Decimal.zero) { partial, occurrence in
            partial + (occurrence.paycheck.amount?.decimalValue ?? .zero)
        }
    }
    
    private var livingMeansPercentage: (percentage: Decimal, isBelow: Bool)? {
        let income = incomeStats(for: currentMonth)
        let stats = monthStats(for: currentMonth)
        let expenses = stats.unpaidTotal + stats.paidTotal + stats.projectedTotal
        
        guard income > 0 else { return nil }
        
        let difference = income - expenses
        let percentage = (difference / income) * 100
        
        return (percentage, difference >= 0)
    }
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }
    
    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        let useSplit = shouldUseSplitLayout(for: size)
        ZStack(alignment: .bottom) {
            if useSplit {
                splitLayout(size: size)
            } else {
                standardLayout
            }
            if showDayDrawer {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissDayDrawer()
                    }
                    .transition(.opacity)
                
                DayDetailDrawer(date: selectedDate,
                                bills: occurrences(for: selectedDate),
                                paychecks: incomeOccurrences(for: selectedDate),
                                currencyCode: currencyCode,
                                onAddBill: { presentBillEditor(nil) },
                                onAddIncome: { presentPaycheckEditor(nil) },
                                onAddIncomeTransaction: nil,
                                onEditBill: { presentBillEditor($0) },
                                onEditIncome: { paycheck in
                                    // Find the occurrence date for this paycheck
                                    let occurrenceDate = incomeOccurrences(for: selectedDate)
                                        .first(where: { $0.paycheck == paycheck })?.date
                                    presentPaycheckEditor(paycheck, occurrenceDate: occurrenceDate)
                                },
                                onDeleteBill: { bill in
                                    billToDelete = bill
                                    showingDeleteBillAlert = true
                                },
                                onDeleteIncome: { paycheck in
                                    paycheckToDelete = paycheck
                                    showingDeletePaycheckAlert = true
                                }) {
                    dismissDayDrawer()
                }
                .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    private var standardLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                monthHeader
                insightSection
                MonthCalendarView(currentMonth: currentMonth,
                                  selectedDate: selectedDate,
                                  calendar: calendar,
                                  billsByDay: billsByDay,
                                  colorScheme: colorScheme) { date in
                    selectDate(date)
                }
                livingMeansView
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, showDayDrawer ? 260 : 20)
        }
    }
    
    private func splitLayout(size: CGSize) -> some View {
let calendarWidth = min(max(size.width * 0.45, 360), 520)
        return HStack(alignment: .top, spacing: 24) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) { // Reduced spacing for landscape
                    monthHeader
                    insightSection
                    MonthCalendarView(currentMonth: currentMonth,
                                      selectedDate: selectedDate,
                                      calendar: calendar,
                                      billsByDay: billsByDay,
                                      colorScheme: colorScheme) { date in
                        selectDate(date)
                    }
                    livingMeansView
                }
                .padding(.top, 4) // Minimal top padding for landscape
                .padding(.bottom, 4) // Match top padding
                .padding(.trailing, 12)
            }
            .frame(width: calendarWidth)
            
            Divider()
                .padding(.vertical, 12)
            
            VStack(alignment: .leading, spacing: 0) {
                // Toggle button for paid bills in landscape
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showPaidBillsInLandscape.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showPaidBillsInLandscape ? "checkmark.square.fill" : "square")
                                .font(.caption)
                            Text(showPaidBillsInLandscape ? "Hide Paid Bills" : "Show Paid Bills")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                
                MonthBillList(dayOccurrences: currentMonthDayOccurrences,
                              calendar: calendar,
                              selectedDate: selectedDate,
                              currencyCode: currencyCode,
                              onEditBill: { presentBillEditor($0) },
                              onEditIncome: { paycheck in
                                  paycheckToEdit = paycheck
                                  paycheckOccurrenceDate = nil
                                  showingPaycheckEditor = true
                              },
                              onDeleteBill: { bill in
                                  billToDelete = bill
                                  showingDeleteBillAlert = true
                              },
                              onDeleteIncome: { paycheck in
                                  paycheckToDelete = paycheck
                                  showingDeletePaycheckAlert = true
                              },
                              onSelect: { date in
                                  selectDate(date)
                              })
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, 8) // Reduced top padding for landscape
        .padding(.horizontal, 20)
        .padding(.bottom, showDayDrawer ? 260 : 40)
    }
    
    private func shouldUseSplitLayout(for size: CGSize) -> Bool {
        horizontalSizeClass == .regular && size.width > size.height && size.width > 780
    }
}

// MARK: - Month Calendar Grid
private struct MonthCalendarView: View {
    let currentMonth: Date
    let selectedDate: Date
    let calendar: Calendar
    let billsByDay: [Date: BillDaySummary]
    let colorScheme: ColorScheme
    let onSelect: (Date) -> Void
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: 7)
    }
    
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
    
    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        let startOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var days: [Date] = []
        if let leadingStart = calendar.date(byAdding: .day, value: -leadingPadding, to: startOfMonth) {
            for offset in 0..<42 {
                if let day = calendar.date(byAdding: .day, value: offset, to: leadingStart) {
                    days.append(day)
                }
            }
        }
        return days
    }
    
    var body: some View {
        let background: Color = colorScheme == .dark ? Color.black.opacity(0.9) : Color(.systemBackground)
        let border: Color = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        
        VStack(spacing: 12) {
            HStack {
                ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(monthDays, id: \.self) { date in
                    let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
                    let isToday = calendar.isDateInToday(date)
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let summary = billsByDay[calendar.startOfDay(for: date)]
                    MonthCalendarDayCell(date: date,
                                         calendar: calendar,
                                         colorScheme: colorScheme,
                            isCurrentMonth: isCurrentMonth,
                            isToday: isToday,
                            isSelected: isSelected,
                                         summary: summary) {
                        onSelect(date)
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .padding(.horizontal, 16)
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

private struct MonthCalendarDayCell: View {
    let date: Date
    let calendar: Calendar
    let colorScheme: ColorScheme
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let summary: BillDaySummary?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                    Text(date, format: .dateTime.day())
                        .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(textColor)
                    
                if let summary, summary.total > 0 {
                    Circle()
                        .fill(summaryColor(summary))
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .background(backgroundShape)
        }
        .buttonStyle(.plain)
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        }
        if isCurrentMonth {
            return isToday ? .accentColor : .primary
        } else {
            return .secondary.opacity(0.4)
        }
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
        } else if isToday {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clear)
        }
    }
    
    private var cellSize: CGFloat {
        isSelected ? 50 : 46
    }
    
    private func summaryColor(_ summary: BillDaySummary) -> Color {
        if summary.actualUnpaid > 0 {
            return .accentColor
        }
        if summary.projected > 0 {
            return Color.accentColor.opacity(0.6)
        }
        if summary.incomeCount > 0 {
            return .green
        }
        if summary.actualPaid > 0 {
            return .green.opacity(0.7)
        }
        return .clear
    }
}

