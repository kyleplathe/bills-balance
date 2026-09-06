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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
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
            calendarNavigationContent
        }
        .sheet(isPresented: $showingBillEditor) {
            billEditorSheet
        }
        .sheet(isPresented: $showingPaycheckEditor) {
            paycheckEditorSheet
        }
        .alert("Delete Bill", isPresented: $showingDeleteBillAlert, presenting: billToDelete, actions: deleteBillAlertButtons, message: deleteBillAlertMessage)
        .alert("Delete Income", isPresented: $showingDeletePaycheckAlert, presenting: paycheckToDelete, actions: deletePaycheckAlertButtons, message: deletePaycheckAlertMessage)
        .onAppear(perform: initializeVisibleMonth)
        .onChange(of: selectedMonth, handleSelectedMonthChange)
    }
    
    private var calendarNavigationContent: some View {
        GeometryReader { proxy in
            content(for: proxy.size)
                .onAppear(perform: updateLandscapeFromSizeClass)
                .onChange(of: verticalSizeClass, handleVerticalSizeClassChange)
                .onChange(of: proxy.size) { _, _ in
                    updateLandscapeFromSizeClass()
                }
        }
        .navigationTitle(isLandscape ? "" : "Calendar")
        .navigationBarTitleDisplayMode(isLandscape ? .inline : .large)
        .toolbar { calendarToolbar }
    }
    
    @ToolbarContentBuilder
    private var calendarToolbar: some ToolbarContent {
        if isLandscape {
            landscapeMonthToolbarItem
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            addItemMenu
        }
    }
    
    @ToolbarContentBuilder
    private var landscapeMonthToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                landscapeMonthTitle
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                landscapeMonthTitle
            }
        }
    }
    
    private var landscapeMonthTitle: some View {
        HStack(spacing: 6) {
            landscapeMonthChevron(systemName: "chevron.left") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(-1)
                }
            }
            .accessibilityLabel("Previous month")
            
            Button(action: jumpToToday) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(monthFormatter.string(from: currentMonth))
            .accessibilityHint("Jumps to today")
            
            landscapeMonthChevron(systemName: "chevron.right") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(1)
                }
            }
            .accessibilityLabel("Next month")
        }
        .fixedSize()
    }
    
    private func landscapeMonthChevron(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var addItemMenu: some View {
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
    
    private var billEditorSheet: some View {
        AddEditBillView(bill: billToEdit, defaultDate: selectedDate)
            .environmentObject(billViewModel)
            .environmentObject(accountViewModel)
    }
    
    private var paycheckEditorSheet: some View {
        PaycheckEditorSheet(
            paycheck: paycheckToEdit,
            defaultDate: selectedDate,
            occurrenceDate: paycheckOccurrenceDate
        )
        .environmentObject(paycheckViewModel)
        .environmentObject(accountViewModel)
    }
    
    @ViewBuilder
    private func deleteBillAlertButtons(_ bill: Bill) -> some View {
        Button("Cancel", role: .cancel) {
            billToDelete = nil
        }
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
    }
    
    private func deleteBillAlertMessage(_ bill: Bill) -> Text {
        if let recurrenceType = bill.recurrenceType, recurrenceType != "none" {
            Text("Do you want to delete just this bill, or delete this bill and all future bills in the series?")
        } else {
            Text("Are you sure you want to delete \"\(bill.name ?? "this bill")\"? This action cannot be undone.")
        }
    }
    
    @ViewBuilder
    private func deletePaycheckAlertButtons(_ paycheck: Paycheck) -> some View {
        Button("Cancel", role: .cancel) {
            paycheckToDelete = nil
        }
        if let recurrenceType = paycheck.recurrenceType, recurrenceType != "none" {
            Button("This Income Only", role: .destructive) {
                paycheckViewModel.deletePaycheck(paycheck)
                paycheckToDelete = nil
            }
            Button("Delete All Future Income", role: .destructive) {
                paycheckViewModel.deletePaycheck(paycheck)
                paycheckToDelete = nil
            }
        } else {
            Button("Delete", role: .destructive) {
                paycheckViewModel.deletePaycheck(paycheck)
                paycheckToDelete = nil
            }
        }
    }
    
    private func deletePaycheckAlertMessage(_ paycheck: Paycheck) -> Text {
        if let recurrenceType = paycheck.recurrenceType, recurrenceType != "none" {
            Text("Deleting this income will remove all future occurrences. This action cannot be undone.")
        } else {
            Text("Are you sure you want to delete \"\(paycheck.name ?? "this income")\"? This action cannot be undone.")
        }
    }
    
    private func initializeVisibleMonth() {
        let today = Date()
        currentMonth = startOfMonth(for: today)
        selectedDate = calendar.startOfDay(for: today)
        showDayDrawer = false
        
        if selectedMonth == nil {
            selectedMonth = currentMonth
        } else {
            currentMonth = startOfMonth(for: selectedMonth ?? today)
        }
    }
    
    private func handleSelectedMonthChange(_ oldValue: Date?, _ newValue: Date?) {
        if let newValue, !calendar.isDate(newValue, equalTo: currentMonth, toGranularity: .month) {
            currentMonth = startOfMonth(for: newValue)
        }
    }
    
    private func updateLandscapeFromSizeClass() {
        isLandscape = verticalSizeClass == .compact
    }
    
    private func handleVerticalSizeClassChange(_ oldValue: UserInterfaceSizeClass?, _ newValue: UserInterfaceSizeClass?) {
        isLandscape = newValue == .compact
    }
    
    // MARK: - Header
    private var monthHeader: some View {
        HStack(spacing: 16) {
            monthChevronButton(systemName: "chevron.left") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(-1)
                }
            }
            .accessibilityLabel("Previous month")
            
            Button(action: jumpToToday) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(monthFormatter.string(from: currentMonth))
            .accessibilityHint("Jumps to today")
            
            monthChevronButton(systemName: "chevron.right") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(1)
                }
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 4)
    }
    
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 50 else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    changeMonth(horizontal < 0 ? 1 : -1)
                }
            }
    }
    
    private func monthChevronButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            monthChevronLabel(systemName: systemName, circleSize: 36, chevronSize: 15)
        }
        .buttonStyle(.plain)
    }
    
    private func monthChevronLabel(systemName: String, circleSize: CGFloat, chevronSize: CGFloat) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: chevronSize, weight: .semibold))
                    .foregroundStyle(.primary)
            )
            .frame(width: circleSize, height: circleSize)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    }
    
    private func jumpToToday() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            let today = Date()
            currentMonth = startOfMonth(for: today)
            selectedMonth = currentMonth
            selectDate(today)
        }
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
        if let insight = livingMeansInsight {
            Text(insight.text)
                .font(.caption)
                .foregroundStyle(insight.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
    
    private var livingMeansInsight: (text: String, color: Color)? {
        guard let meansData = livingMeansPercentage else { return nil }
        
        var absPercentage = abs(meansData.percentage)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &absPercentage, 1, .plain)
        
        if rounded == 0 {
            return ("You're breaking even this month", .secondary)
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let percentageString = formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0"
        
        if meansData.isBelow {
            return ("This month you're living \(percentageString)% below your means", .green)
        }
        return ("This month you're living \(percentageString)% above your means", .orange)
    }
    
    private var insights: [CalendarInsight] {
        let remainingBills = unpaidBills(for: currentMonth)
        let upcomingBills = upcomingSevenDayBills
        return [
            CalendarInsight(title: "Remaining",
                            billCount: remainingBills.count,
                            amount: totalAmount(of: remainingBills),
                            tint: .accentColor),
            CalendarInsight(title: "Next 7 days",
                            billCount: upcomingBills.count,
                            amount: totalAmount(of: upcomingBills),
                            tint: .orange)
        ]
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

    private func unpaidBills(for month: Date) -> [Bill] {
        billViewModel.fetchAllBillsForMonth(month).filter { !$0.isPaid }
    }
    
    private func totalAmount(of bills: [Bill]) -> Decimal {
        bills.reduce(.zero) { $0 + ($1.amount?.decimalValue ?? .zero) }
    }
    
    private func totalAmount(of occurrences: [BillOccurrence]) -> Decimal {
        occurrences.reduce(.zero) { $0 + ($1.bill.amount?.decimalValue ?? .zero) }
    }
    
    private var upcomingSevenDayBills: [BillOccurrence] {
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        let interval = DateInterval(start: start, end: end)
        return occurrences(in: interval).filter { !$0.bill.isPaid }
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
    private var dayDetailDrawer: some View {
        DayDetailDrawer(date: selectedDate,
                        bills: occurrences(for: selectedDate),
                        paychecks: incomeOccurrences(for: selectedDate),
                        currencyCode: currencyCode,
                        compact: isLandscape,
                        onAddBill: { presentBillEditor(nil) },
                        onAddIncome: { presentPaycheckEditor(nil) },
                        onAddIncomeTransaction: nil,
                        onEditBill: { presentBillEditor($0) },
                        onEditIncome: { paycheck in
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
        .padding(.horizontal, isLandscape ? 12 : 16)
        .padding(.bottom, isLandscape ? 8 : 12)
    }
    
    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        let useSplit = shouldUseSplitLayout(for: size)
        ZStack(alignment: .bottom) {
            if useSplit {
                splitLayout(size: size)
            } else {
                standardLayout(size: size)
            }
            
            if showDayDrawer, !isLandscape {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissDayDrawer()
                    }
                    .transition(.opacity)
            }
            
            if showDayDrawer {
                dayDetailDrawer
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    @ViewBuilder
    private func standardLayout(size: CGSize) -> some View {
        if isLandscape {
            landscapeCalendarLayout()
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
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
                .padding(.top, 8)
                .padding(.bottom, showDayDrawer ? 260 : 20)
            }
        }
    }
    
    private func landscapeCalendarLayout() -> some View {
        let margin: CGFloat = 10
        
        return MonthCalendarView(currentMonth: currentMonth,
                                 selectedDate: selectedDate,
                                 calendar: calendar,
                                 billsByDay: billsByDay,
                                 colorScheme: colorScheme,
                                 compact: true) { date in
            selectDate(date)
        }
        .aspectRatio(1.08, contentMode: .fit)
        .padding(margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .trailing)
        .contentShape(Rectangle())
        .simultaneousGesture(monthSwipeGesture)
        .accessibilityHint("Swipe left or right to change months")
        .accessibilityAction(named: "Previous month") {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                changeMonth(-1)
            }
        }
        .accessibilityAction(named: "Next month") {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                changeMonth(1)
            }
        }
        .accessibilityAction(named: "Jump to today", jumpToToday)
    }
    
    private func splitLayout(size: CGSize) -> some View {
        let calendarWidth = min(max(size.width * 0.45, 360), 520)
        return HStack(alignment: .top, spacing: 24) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) { // Reduced spacing for landscape
                    monthHeader
                    MonthCalendarView(currentMonth: currentMonth,
                                      selectedDate: selectedDate,
                                      calendar: calendar,
                                      billsByDay: billsByDay,
                                      colorScheme: colorScheme) { date in
                        selectDate(date)
                    }
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
    var compact: Bool = false
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
    
    private var monthWeeks: [[Date]] {
        stride(from: 0, to: monthDays.count, by: 7).map { start in
            Array(monthDays[start..<min(start + 7, monthDays.count)])
        }
    }
    
    var body: some View {
        let background: Color = colorScheme == .dark ? Color.black.opacity(0.9) : Color(.systemBackground)
        let border: Color = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        
        VStack(spacing: compact ? 8 : 12) {
            HStack {
                ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(compact ? .caption2.weight(.medium) : .caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            if compact {
                VStack(spacing: 3) {
                    ForEach(monthWeeks.indices, id: \.self) { weekIndex in
                        HStack(spacing: 3) {
                            ForEach(monthWeeks[weekIndex], id: \.self) { date in
                                dayCell(for: date)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(monthDays, id: \.self) { date in
                        dayCell(for: date)
                    }
                }
            }
        }
        .padding(.top, compact ? 12 : 18)
        .padding(.bottom, compact ? 10 : 8)
        .padding(.horizontal, compact ? 14 : 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(border)
                )
        )
    }
    
    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let summary = billsByDay[calendar.startOfDay(for: date)]
        return MonthCalendarDayCell(date: date,
                                    calendar: calendar,
                                    colorScheme: colorScheme,
                                    isCurrentMonth: isCurrentMonth,
                                    isToday: isToday,
                                    isSelected: isSelected,
                                    summary: summary,
                                    compact: compact) {
            onSelect(date)
        }
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
    var compact: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 6) {
                    Text(date, format: .dateTime.day())
                        .font(.system(size: compact ? 15 : 16, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(textColor)
                    
                if let summary, summary.total > 0 {
                    Circle()
                        .fill(summaryColor(summary))
                        .frame(width: compact ? 6 : 6, height: compact ? 6 : 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: compact ? 6 : 6, height: compact ? 6 : 6)
                }
            }
            .frame(maxWidth: compact ? .infinity : cellSize, maxHeight: compact ? .infinity : cellSize)
            .frame(width: compact ? nil : cellSize, height: compact ? nil : cellSize)
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
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .fill(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(compact ? 0.2 : 0.3), radius: compact ? 4 : 8, x: 0, y: compact ? 2 : 4)
        } else if isToday {
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .fill(Color.clear)
        }
    }
    
    private var cellSize: CGFloat {
        if compact {
            return isSelected ? 36 : 32
        }
        return isSelected ? 50 : 46
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

