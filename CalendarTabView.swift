// MARK: - Day Detail Card
private struct DayDetailCard: View {
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
                        BillDueRow(occurrence: occurrence, currencyCode: currencyCode)
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
    
    init(selectedMonth: Binding<Date?> = .constant(nil)) {
        self._selectedMonth = selectedMonth
    }
    
    private let calendar = Calendar.current
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
    
    var body: some View {
        NavigationView {
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
        
        for bill in billViewModel.bills {
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
        
        for bill in billViewModel.bills {
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
        switch type {
        case "daily":
            return calendar.date(byAdding: .day, value: interval, to: date)
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case "monthly":
            return calendar.date(byAdding: .month, value: interval, to: date)
        case "quarterly":
            return calendar.date(byAdding: .month, value: 3 * interval, to: date)
        case "yearly":
            return calendar.date(byAdding: .year, value: interval, to: date)
        default:
            return nil
        }
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
                              currencyCode: currencyCode) { date in
                    selectDate(date)
                }
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

// MARK: - Day Drawer
private struct DayDetailDrawer: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let date: Date
    let bills: [BillOccurrence]
    let paychecks: [PaycheckOccurrence]
    let currencyCode: String
    let onAddBill: (() -> Void)?
    let onAddIncome: (() -> Void)?
    let onAddIncomeTransaction: (() -> Void)?
    let onEditBill: ((Bill) -> Void)?
    let onEditIncome: ((Paycheck) -> Void)?
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
            // Drag handle area - larger and more responsive
            VStack(spacing: 8) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                
                Text(headerFormatter.string(from: date))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 60)
            
            VStack(spacing: 16) {
                if onAddBill != nil || onAddIncome != nil {
                    HStack(spacing: 12) {
                        if let onAddBill {
                            Button(action: onAddBill) {
                                Label("Add Bill", systemImage: "plus.circle")
                            }
                        }
                        if let onAddIncome {
                            Button(action: onAddIncome) {
                                Label("Add Income", systemImage: "arrow.down.circle")
                            }
                        }
                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                }

                if bills.isEmpty && paychecks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No activity on this day")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                            VStack(alignment: .leading, spacing: 12) {
                        if !bills.isEmpty {
                                ForEach(bills) { occurrence in
                                    BillDueRow(occurrence: occurrence, currencyCode: currencyCode)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                        }
                        if !paychecks.isEmpty {
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
                                              onEdit: {
                                                  if let handler = onEditIncome {
                                                      handler(occurrence.paycheck)
                                                  }
                                              })
                                    .environmentObject(accountViewModel)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .offset(y: max(0, dragOffset))
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: dragOffset)
        .contentShape(Rectangle())
        .simultaneousGesture(
            dragGesture
        )
        .padding(.bottom, 18)
        .padding(.horizontal, 18)
        .background(.regularMaterial)
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)
    }
}

// MARK: - Insights UI
private struct CalendarInsight {
    let title: String
    let subtitle: String
    let amount: Decimal
    let tint: Color
}

private struct CalendarInsightGrid: View {
    let insights: [CalendarInsight]
    let currencyCode: String
    
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
    
    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: insights.count == 1 ? [GridItem(.flexible())] : columns, spacing: 12) {
                ForEach(Array(insights.enumerated()), id: \.offset) { item in
                    CalendarInsightCard(insight: item.element, currencyCode: currencyCode)
                }
            }
        }
    }
}

private struct CalendarInsightCard: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let insight: CalendarInsight
    let currencyCode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.title.uppercased())
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if bitcoinPriceService.showInBitcoin {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bitcoinPriceService.formatAsSats(insight.amount))
                        .font(.headline.weight(.semibold))
                    Text("$\(insight.amount, format: .number.precision(.fractionLength(2)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(insight.amount, format: .currency(code: currencyCode))
                    .font(.headline.weight(.semibold))
            }
            Text(insight.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(insight.tint.opacity(0.12))
        )
    }
}

// MARK: - Shared Models
private struct MonthStats {
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

private struct BillOccurrence: Identifiable {
    let id: String
    let bill: Bill
    let date: Date
    let isProjected: Bool
}

private struct BillDaySummary {
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

private struct DayOccurrences {
    var bills: [BillOccurrence] = []
    var paychecks: [PaycheckOccurrence] = []
}

private struct MonthBillList: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let dayOccurrences: [(date: Date, data: DayOccurrences)]
    let calendar: Calendar
    let selectedDate: Date
    let currencyCode: String
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
                if bitcoinPriceService.showInBitcoin {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bitcoinPriceService.formatAsSats(net))
                            .font(.subheadline.weight(.semibold))
                        Text("$\(net, format: .number.precision(.fractionLength(2)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(net >= 0 ? .green : .primary)
                } else {
                    Text(net, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(net >= 0 ? .green : .primary)
                }
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
                              })
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
                    BillDueRow(occurrence: occurrence, currencyCode: currencyCode)
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
private struct BillDueRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let occurrence: BillOccurrence
    let currencyCode: String
    
    var body: some View {
        let bill = occurrence.bill
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(bill.name ?? "Bill")
                        .font(.headline)
                    statusBadge
                }
                
                if let accountName = bill.account?.name, !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let paymentCard = bill.paymentCard, !paymentCard.isEmpty {
                    Label(paymentCard, systemImage: "creditcard.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let amountDecimal = bill.amount?.decimalValue {
                if bitcoinPriceService.showInBitcoin {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bitcoinPriceService.formatAsSats(amountDecimal))
                            .fontWeight(.semibold)
                        Text("$\(amountDecimal, format: .number.precision(.fractionLength(2)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(amountColor)
                } else {
                    Text(amountDecimal, format: .currency(code: currencyCode))
                        .fontWeight(.semibold)
                        .foregroundColor(amountColor)
                }
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

private struct PaycheckRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let occurrence: PaycheckOccurrence
    let currencyCode: String
    let onAddToAccount: () -> Void
    var onEdit: (() -> Void)? = nil
    
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
        
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(paycheck.name ?? "Income")
                        .font(.headline)
                    statusBadge(isPending: isPending)
                }
                if let accountName = paycheck.account?.name, !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let notes = paycheck.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if let amountDecimal = paycheck.amount?.decimalValue {
                    if bitcoinPriceService.showInBitcoin {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(bitcoinPriceService.formatAsSats(amountDecimal))
                                .fontWeight(.semibold)
                            Text("$\(amountDecimal, format: .number.precision(.fractionLength(2)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.green)
                    } else {
                        Text(amountDecimal, format: .currency(code: currencyCode))
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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


