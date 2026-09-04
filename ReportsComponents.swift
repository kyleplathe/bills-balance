//
//  ReportsComponents.swift
//  BillsAndBalance
//

import SwiftUI
import Charts
import CoreData

struct LedgerEntrySheetItem: Identifiable {
    let id: NSManagedObjectID
    let entry: LedgerEntry

    init(_ entry: LedgerEntry) {
        self.id = entry.objectID
        self.entry = entry
    }
}

enum WalletBarData {
    case week([(day: Date, expenses: Decimal)])
    case month([Decimal], month: Date)
    case year([(month: Date, income: Decimal, expenses: Decimal, fees: Decimal)])
}

enum ActivityMoneyFormat {
    static func string(usd: Decimal, bitcoin: BitcoinPriceService, fractionDigits: Int = 2) -> String {
        if bitcoin.showInBitcoin {
            let formatted = bitcoin.formatAsSats(usd)
            return formatted.hasPrefix("₿") ? formatted : "₿ \(formatted)"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        return f.string(from: usd as NSDecimalNumber) ?? "$0.00"
    }
}

/// Skinny rounded-rect bar. Filled bars mask a chart-height spectrum so color is tied to Y.
/// When `showsTrack` is true, a gray full-height slot sits behind the value fill.
struct WalletActivityBar: View {
    let width: CGFloat
    let barHeight: CGFloat
    let chartHeight: CGFloat
    var isPlaceholder: Bool = false
    var appeared: Bool = true
    var delay: Double = 0
    var showsTrack: Bool = false

    var body: some View {
        let radius = min(2, width / 2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let displayedHeight = appeared ? barHeight : min(6, barHeight)
        let displayedTrackHeight = appeared ? chartHeight : min(6, chartHeight)

        ZStack(alignment: .bottom) {
            if showsTrack || isPlaceholder {
                shape
                    .fill(Color.secondary.opacity(0.18))
                    .frame(
                        width: width,
                        height: showsTrack ? displayedTrackHeight : displayedHeight
                    )
            }

            if !isPlaceholder {
                Rectangle()
                    .fill(CategoryStyle.appleCardSpectrum)
                    .frame(width: width, height: chartHeight)
                    .mask(alignment: .bottom) {
                        shape.frame(width: width, height: displayedHeight)
                    }
            }
        }
        .frame(width: width, height: chartHeight, alignment: .bottom)
        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay), value: appeared)
    }
}

struct WalletTotalSpendingAppleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let expenses: Decimal
    let previousPeriodExpenses: Decimal?
    let periodType: ReportsViewModel.WalletPeriod
    let appeared: Bool
    var isCurrentPeriodInProgress: Bool = false
    var anchorDate: Date? = nil

    private var comparisonText: String? {
        guard let previous = previousPeriodExpenses, previous > 0 else { return nil }
        let difference = expenses - previous
        let absDifference = abs(difference)
        let periodName: String = {
            switch periodType {
            case .week: return "last week"
            case .month: return "last month"
            case .year: return "last year"
            }
        }()
        let periodNoun: String = {
            switch periodType {
            case .week: return "week"
            case .month: return "month"
            case .year: return "year"
            }
        }()
        let diffString = ActivityMoneyFormat.string(usd: absDifference, bitcoin: bitcoinPriceService)

        if abs(difference) < 0.01 {
            if isCurrentPeriodInProgress {
                return "So far, you’ve spent about the same as \(periodName) at this time."
            }
            return "You spent about the same as the previous \(periodNoun)."
        }

        let direction = difference > 0 ? "more" : "less"
        if isCurrentPeriodInProgress {
            return "So far, you’ve spent \(diffString) \(direction) than \(periodName) at this time."
        }
        return "You spent \(diffString) \(direction) than the previous \(periodNoun)."
    }

    private var arrowIcon: String? {
        guard let previous = previousPeriodExpenses, previous > 0 else { return nil }
        let difference = expenses - previous
        if abs(difference) < 0.01 { return "arrow.right" }
        return difference > 0 ? "arrow.up" : "arrow.down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total Spending")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 8) {
                    Text(ActivityMoneyFormat.string(usd: expenses, bitcoin: bitcoinPriceService))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let arrowIcon {
                        Image(systemName: arrowIcon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Color.primary))
                    }
                }
                if let comparisonText {
                    Text(comparisonText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WalletStackedCategoryBarChart(
                period: periodType,
                appeared: appeared,
                showEveryNthLabel: nil,
                anchorDate: anchorDate
            )
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(activitySnapshotChrome)
    }

    private var activitySnapshotChrome: some View {
        let backgroundColor: Color = colorScheme == .dark
            ? Color.black.opacity(0.82)
            : Color(.secondarySystemBackground)
        let borderColor: Color = colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor)
            )
    }
}

// MARK: - Stacked Category Bar Chart

struct WalletStackedCategoryBarChart: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let period: ReportsViewModel.WalletPeriod
    let appeared: Bool
    let showEveryNthLabel: Int?
    var anchorDate: Date? = nil

    private var categoryBreakdown: [(period: String, categories: [(name: String, amount: Decimal)])] {
        reportsViewModel.categoryBreakdownByPeriod(period: period, date: anchorDate)
    }

    private var maxValue: Double {
        let values = categoryBreakdown.map { period in
            period.categories.reduce(Decimal(0)) { $0 + $1.amount }
        }.map { ($0 as NSDecimalNumber).doubleValue }
        return max(values.max() ?? 0, 1)
    }

    private var yAxisValues: [Double] {
        let maxVal = maxValue > 0 ? maxValue : 100
        let step = max(maxVal / 4.0, 25.0)
        let top = maxValue > 0 ? maxVal : 100
        return [0, step, step * 2, step * 3, top]
    }

    private func formatAmount(_ value: Double) -> String {
        let decimal = Decimal(value)
        if bitcoinPriceService.showInBitcoin {
            return ActivityMoneyFormat.string(usd: decimal, bitcoin: bitcoinPriceService, fractionDigits: 0)
        }
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        }
        return ActivityMoneyFormat.string(usd: decimal, bitcoin: bitcoinPriceService, fractionDigits: 0)
    }

    private func shouldShowLabel(at index: Int) -> Bool {
        guard let nth = showEveryNthLabel else { return true }
        return index % nth == 0
    }

    private func barHeight(for periodData: (period: String, categories: [(name: String, amount: Decimal)]), chartHeight: CGFloat) -> CGFloat {
        let total = periodData.categories.reduce(Decimal(0)) { $0 + $1.amount }
        let value = (total as NSDecimalNumber).doubleValue
        guard value > 0 else { return 6 }
        return max(8, chartHeight * CGFloat(value / maxValue))
    }

    private func xAxisLabel(for periodData: (period: String, categories: [(name: String, amount: Decimal)])) -> String {
        switch period {
        case .year:
            return String(periodData.period.prefix(1))
        case .week, .month:
            return periodData.period
        }
    }

    var body: some View {
        let chartHeight: CGFloat = 180
        let yAxisWidth: CGFloat = 36
        let barWidth: CGFloat = categoryBreakdown.count > 8 ? 10 : 14
        let columnSpacing: CGFloat = categoryBreakdown.count > 8 ? 4 : 6
        let ticks = yAxisValues

        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(Array(ticks.reversed().enumerated()), id: \.offset) { index, _ in
                            if index > 0 { Spacer(minLength: 0) }
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 0.5)
                        }
                    }

                    HStack(alignment: .bottom, spacing: columnSpacing) {
                        ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { index, periodData in
                            let total = periodData.categories.reduce(Decimal(0)) { $0 + $1.amount }
                            WalletActivityBar(
                                width: barWidth,
                                barHeight: barHeight(for: periodData, chartHeight: chartHeight),
                                chartHeight: chartHeight,
                                isPlaceholder: total <= 0,
                                appeared: appeared,
                                delay: Double(index) * 0.03
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: chartHeight)

                HStack(spacing: columnSpacing) {
                    ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { index, periodData in
                        Text(xAxisLabel(for: periodData))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .opacity(shouldShowLabel(at: index) ? 1 : 0)
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(ticks.reversed().enumerated()), id: \.offset) { index, tick in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(formatAmount(tick))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: yAxisWidth, height: chartHeight, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// MARK: - Compact Stacked Category Bar Chart (for Balance page chip card)

struct CompactWalletStackedCategoryBarChart: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let period: ReportsViewModel.WalletPeriod
    let appeared: Bool
    var date: Date? = nil

    private var categoryBreakdown: [(period: String, categories: [(name: String, amount: Decimal)])] {
        reportsViewModel.categoryBreakdownByPeriod(period: period, date: date)
    }

    private var maxValue: Double {
        let values = categoryBreakdown.map { period in
            period.categories.reduce(Decimal(0)) { $0 + $1.amount }
        }.map { ($0 as NSDecimalNumber).doubleValue }
        return max(values.max() ?? 0, 1)
    }

    private func actualValue(for periodData: (period: String, categories: [(name: String, amount: Decimal)])) -> Double {
        let totalAmount = periodData.categories.reduce(Decimal(0)) { $0 + $1.amount }
        return (totalAmount as NSDecimalNumber).doubleValue
    }

    private let chartHeight: CGFloat = 36
    /// Fixed skinny width so Week / Month / Year bars match visually.
    private let barWidth: CGFloat = 7

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(categoryBreakdown.enumerated()), id: \.offset) { index, periodData in
                if index > 0 {
                    Spacer(minLength: 4)
                }

                let value = actualValue(for: periodData)
                let hasValue = value > 0
                let height = hasValue ? max(8, chartHeight * CGFloat(value / maxValue)) : 0

                WalletActivityBar(
                    width: barWidth,
                    barHeight: height,
                    chartHeight: chartHeight,
                    isPlaceholder: !hasValue,
                    appeared: appeared,
                    delay: Double(index) * 0.04,
                    showsTrack: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: chartHeight, alignment: .bottom)
    }
}

struct WalletAppleBarChart: View {
    let labels: [String]
    let values: [Decimal]
    let showEveryNthLabel: Int? // For year view, show every Nth label (e.g., 3 = every 3rd month)
    let comparisonText: String?
    let comparisonColor: Color
    let appeared: Bool
    
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()
    
    private var maxValue: Double {
        values.map { ($0 as NSDecimalNumber).doubleValue }.max() ?? 0
    }
    
    private func formatAmount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        } else {
            return formatter.string(from: NSNumber(value: value)) ?? "$0"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    BarMark(
                        x: .value("Period", label),
                        y: .value("Amount", (values[i] as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(CategoryStyle.appleCardSpectrum)
                    .cornerRadius(6, style: .continuous)
                }
            }
            .chartXAxis {
                if let nth = showEveryNthLabel {
                    // For year view, use explicit values to show only every Nth label
                    let labelIndices = (0..<labels.count).filter { $0 % nth == 0 }
                    AxisMarks(values: .automatic) { value in
                        if let stringValue = value.as(String.self),
                           let index = labels.firstIndex(of: stringValue),
                           labelIndices.contains(index) {
                            AxisValueLabel()
                                .font(.caption2)
                        }
                        // Don't show label for other positions
                    }
                } else {
                    // For week/month, show all labels
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
            }
            .chartYAxis {
                // When there's no data, use sensible default values
                let maxVal = maxValue > 0 ? max(maxValue, 100) : 100
                let quarter = maxVal / 4.0
                // Ensure quarter is at least 25 for readability when there's no data
                let adjustedQuarter = max(quarter, 25.0)
                let adjustedMax = maxValue > 0 ? maxVal : 100
                // Create 4 main values (quarters) and 4 midpoints
                let mainValues: [Double] = [0, adjustedQuarter, adjustedQuarter * 2, adjustedQuarter * 3, adjustedMax]
                let midpointValues: [Double] = [adjustedQuarter * 0.5, adjustedQuarter * 1.5, adjustedQuarter * 2.5, adjustedQuarter * 3.5]
                let allValues = (mainValues + midpointValues).sorted()
                
                AxisMarks(position: .trailing, values: allValues) { value in
                    if let doubleValue = value.as(Double.self) {
                        // Check if this is a main quarter value
                        let isMainValue = mainValues.contains { abs($0 - doubleValue) < 0.01 }
                        
                        if isMainValue {
                            // Show label and solid line for main quarter values
                            AxisValueLabel {
                                Text(formatAmount(doubleValue))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.secondary.opacity(0.3))
                        } else {
                            // Show dashed line for midpoints, no label
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(.secondary.opacity(0.2))
                        }
                    }
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            if let compText = comparisonText {
                Text(compText)
                    .font(.caption)
                    .foregroundStyle(comparisonColor)
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
    }
}

struct WalletIncomeFeesRows: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let income: Decimal
    let creditCardSpending: Decimal
    let appeared: Bool
    let onIncomeTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WalletSummaryRow(
                icon: "arrow.down.circle.fill",
                iconColor: .green,
                title: "Income",
                amount: income,
                appeared: appeared,
                onTap: onIncomeTap
            )
            if creditCardSpending > 0 {
                Divider()
                    .padding(.leading, 52)
                CreditCardSpendingRow(
                    icon: "creditcard.fill",
                    iconColor: .blue,
                    title: "Credit Card Spending",
                    amount: creditCardSpending,
                    appeared: appeared
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.06))
                )
        )
    }
}

struct WalletSummaryRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let icon: String
    let iconColor: Color
    let title: String
    let amount: Decimal
    let appeared: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.15)))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(ActivityMoneyFormat.string(usd: amount, bitcoin: bitcoinPriceService))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credit Card Spending Row (with tap to toggle)

struct CreditCardSpendingRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let icon: String
    let iconColor: Color
    let title: String
    let amount: Decimal
    let appeared: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.15)))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(ActivityMoneyFormat.string(usd: amount, bitcoin: bitcoinPriceService))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(appeared ? 1 : 0)
    }
}

struct WalletCategorySection: View {
    let items: [(name: String, amount: Decimal)]
    let appeared: Bool
    @Binding var expandedCategories: Set<String>
    let onCategoryTap: (String) -> Void
    let onTransactionTap: (LedgerEntry) -> Void
    let period: ReportsViewModel.WalletPeriod
    var anchorDate: Date? = nil
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    // Sort by amount; keep the top 8 categories, then flip order when sorting low to high.
    private var sortedItems: [(name: String, amount: Decimal)] {
        let top = Array(items.sorted { $0.amount > $1.amount }.prefix(8))
        return reportsViewModel.categorySortDescending ? top : top.reversed()
    }
    @State private var showingPieChart = false
    @State private var pieChartScale: CGFloat = 1.0
    @State private var pieChartRotation: Double = 0
    @State private var pieChartOpacity: Double = 1.0
    @State private var categoryListOffset: CGFloat = 0
    @State private var categoryListOpacity: Double = 1.0
    @State private var legendOffset: CGFloat = 0
    @State private var legendOpacity: Double = 1.0
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()
    
    private var totalSpending: Decimal {
        sortedItems.reduce(0) { $0 + $1.amount }
    }

    private func colorForCategory(_ name: String) -> Color {
        CategoryStyle.color(for: name)
    }

    private var itemColors: [Color] {
        sortedItems.prefix(8).map { CategoryStyle.color(for: $0.name) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Category")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            reportsViewModel.setCategorySortDescending(!reportsViewModel.categorySortDescending)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        reportsViewModel.categorySortDescending
                            ? "Sorted high to low"
                            : "Sorted low to high"
                    )
                    .accessibilityHint("Toggle category sort order")
                    Button {
                        if showingPieChart {
                            // Closing animation - reverse of opening
                            // First, animate legend out (down)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                legendOffset = 200
                                legendOpacity = 0
                            }
                            // Then animate pie chart out (scale down, rotate, fade)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    pieChartScale = 0.1
                                    pieChartRotation = -360
                                    pieChartOpacity = 0
                                }
                            }
                            // Then animate category list back in (up from bottom)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingPieChart = false
                                // Reset pie chart state for next opening
                                pieChartScale = 1.0
                                pieChartRotation = 0
                                pieChartOpacity = 1.0
                                legendOffset = 0
                                legendOpacity = 1.0
                                // Animate category list back up from bottom
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    categoryListOffset = 0
                                    categoryListOpacity = 1.0
                                }
                            }
                        } else {
                            // Opening animation
                            // First, animate category list out (down)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                categoryListOffset = 200
                                categoryListOpacity = 0
                            }
                            // Then show pie chart and animate it in from its final position
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showingPieChart = true
                                // Start from small scale and rotated
                                pieChartScale = 0.1
                                pieChartRotation = 360
                                pieChartOpacity = 0
                                legendOffset = 200
                                legendOpacity = 0
                                // Animate pie chart to final position (scale 1, rotation 0)
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    pieChartScale = 1.0
                                    pieChartRotation = 0
                                    pieChartOpacity = 1.0
                                }
                                // Animate legend in (up from bottom) with slight delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        legendOffset = 0
                                        legendOpacity = 1.0
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: showingPieChart ? "xmark.circle.fill" : "chart.pie.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.bounce, value: showingPieChart)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                
                if showingPieChart {
                    VStack(spacing: 12) {
                        // Pie chart with its own animations
                        CategoryPieChart(
                            items: sortedItems,
                            colors: itemColors,
                            appeared: appeared
                        )
                        .scaleEffect(pieChartScale)
                        .rotationEffect(.degrees(pieChartRotation))
                        .opacity(pieChartOpacity)
                        
                        // Legend with separate animations
                        CategoryPieChartLegend(
                            items: sortedItems,
                            colors: itemColors,
                            legendOffset: legendOffset,
                            legendOpacity: legendOpacity
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedItems.prefix(8).enumerated()), id: \.offset) { i, item in
                            let isExpanded = expandedCategories.contains(item.name)
                            let transactions = reportsViewModel.transactionsForCategory(item.name, period: period, date: anchorDate)
                            
                            VStack(spacing: 0) {
                                // Category row - tappable to expand/collapse
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if expandedCategories.contains(item.name) {
                                            expandedCategories.remove(item.name)
                                        } else {
                                            expandedCategories.insert(item.name)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: CategoryStyle.icon(for: item.name))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(colorForCategory(item.name))
                                            .frame(width: 32, height: 32)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(colorForCategory(item.name).opacity(0.15)))
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(ActivityMoneyFormat.string(usd: item.amount, bitcoin: bitcoinPriceService))
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                        }
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .opacity(appeared ? 1 : 0)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                // Expanded transactions
                                if isExpanded {
                                    VStack(spacing: 0) {
                                        if !transactions.isEmpty {
                                            ForEach(transactions, id: \.objectID) { entry in
                                                CategoryTransactionRow(
                                                    entry: entry,
                                                    category: item.name,
                                                    onEdit: {
                                                        onTransactionTap(entry)
                                                    },
                                                    onDelete: {},
                                                    showsSwipeActions: false
                                                )
                                                .padding(.leading, 52)
                                                .padding(.vertical, 8)

                                                if entry != transactions.last {
                                                    Divider()
                                                        .padding(.leading, 52)
                                                }
                                            }
                                        } else {
                                            Text("No transactions")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 52)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            
                            if i < sortedItems.count - 1 {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .offset(y: categoryListOffset)
                    .opacity(categoryListOpacity)
                }
            }
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.06))
                    )
            )
    }
}

struct CategoryPieChart: View {
    let items: [(name: String, amount: Decimal)]
    let colors: [Color] // Keep for pie chart segments
    let appeared: Bool
    @State private var segmentAppeared: [Bool] = []
    
    private var totalAmount: Decimal {
        items.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        Chart {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { i, item in
                let isVisible = i < segmentAppeared.count && segmentAppeared[i]
                SectorMark(
                    angle: .value("Amount", isVisible ? item.amount : 0),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(colors[i % colors.count])
                .opacity(isVisible ? 1 : 0)
            }
        }
        .frame(height: 200)
        .onAppear {
            let itemCount = min(8, items.count)
            segmentAppeared = Array(repeating: false, count: itemCount)
            
            // Animate each segment with a staggered delay
            for i in 0..<itemCount {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1 + Double(i) * 0.08)) {
                    segmentAppeared[i] = true
                }
            }
        }
        .onDisappear {
            segmentAppeared = []
        }
    }
}

struct CategoryPieChartLegend: View {
    let items: [(name: String, amount: Decimal)]
    let colors: [Color]
    let legendOffset: CGFloat
    let legendOpacity: Double
    @State private var segmentAppeared: [Bool] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { i, item in
                let isVisible = i < segmentAppeared.count && segmentAppeared[i]
                HStack(spacing: 8) {
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: 12, height: 12)
                    Text(item.name)
                        .font(.caption)
                    Spacer()
                }
                .opacity(isVisible ? legendOpacity : 0)
                .offset(x: isVisible ? 0 : -20, y: legendOffset)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            let itemCount = min(8, items.count)
            segmentAppeared = Array(repeating: false, count: itemCount)
            
            // Animate each legend item with a staggered delay
            for i in 0..<itemCount {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1 + Double(i) * 0.08)) {
                    segmentAppeared[i] = true
                }
            }
        }
        .onDisappear {
            segmentAppeared = []
        }
    }
}

struct WalletCategoryRow: View {
    let icon: String
    let color: Color
    let name: String
    let amount: Decimal
    let previousAmount: Decimal
    let formatter: NumberFormatter
    let appeared: Bool
    let onTap: () -> Void
    
    private var trendIndicator: (icon: String, color: Color)? {
        guard previousAmount > 0 else { return nil }
        let change = amount - previousAmount
        let percentChange = abs(change / previousAmount)
        
        // Only show if change is significant (>5%)
        guard percentChange > 0.05 else { return nil }
        
        if change > 0 {
            return ("arrow.up", .red)
        } else {
            return ("arrow.down", .green)
        }
    }
    
    private var trendText: String? {
        guard previousAmount > 0 else { return nil }
        let change = amount - previousAmount
        let percentChange = abs(change / previousAmount)
        
        guard percentChange > 0.05 else { return nil }
        
        let percentValue = (percentChange * Decimal(100)) as NSDecimalNumber
        let percent = Int(percentValue.doubleValue.rounded())
        if change > 0 {
            return "+\(percent)%"
        } else {
            return "-\(percent)%"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.15)))
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatter.string(from: amount as NSDecimalNumber) ?? "$0")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let trend = trendIndicator {
                            Image(systemName: trend.icon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(trend.color)
                        }
                    }
                    if let trend = trendText, let indicator = trendIndicator {
                        Text(trend)
                            .font(.caption2)
                            .foregroundStyle(indicator.color.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Transactions View

struct CategoryTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var categoryManager: CategoryManager
    
    let category: String
    let period: ReportsViewModel.WalletPeriod
    
    @State private var entries: [LedgerEntry] = []
    @State private var ledgerEntryToEdit: LedgerEntry?
    @State private var ledgerEntryToDelete: LedgerEntry?
    @State private var showLedgerDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet",
                        description: Text("No transactions found for \(category) in this period.")
                    )
                } else {
                    ForEach(entries, id: \.objectID) { entry in
                        CategoryTransactionRow(
                            entry: entry,
                            category: category,
                            onEdit: {
                                ledgerEntryToEdit = entry
                            },
                            onDelete: {
                                ledgerEntryToDelete = entry
                                showLedgerDeleteAlert = true
                            }
                        )
                    }
                }
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(item: Binding(
                get: { ledgerEntryToEdit.map { LedgerEntrySheetItem($0) } },
                set: { ledgerEntryToEdit = $0?.entry }
            ), onDismiss: {
                loadEntries()
            }) { item in
                TransactionEditorSheet(entry: item.entry)
                    .environmentObject(accountViewModel)
                    .environmentObject(bitcoinPriceService)
                    .environmentObject(categoryManager)
            }
            .alert("Delete Entry", isPresented: $showLedgerDeleteAlert, presenting: ledgerEntryToDelete) { entry in
                Button("Delete", role: .destructive) {
                    accountViewModel.deleteLedgerEntry(entry)
                    loadEntries()
                }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("This will remove the ledger entry permanently.")
            }
            .onAppear {
                loadEntries()
            }
        }
    }
    
    private func loadEntries() {
        if category == "Income" {
            entries = reportsViewModel.fetchIncomeEntries(period: period)
        } else if category == "Digital Wallet Fees" {
            entries = reportsViewModel.fetchFeeEntries(period: period)
        } else {
            entries = reportsViewModel.fetchEntriesByCategory(category, period: period)
        }
    }
}

// Wrapper to access the private LedgerEntryEditorSheet
struct CategoryLedgerEntryEditorSheet: View {
    let entry: LedgerEntry
    let onSave: (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void
    
    var body: some View {
        // Use the same editor structure as BalanceView
        LedgerEntryEditorView(entry: entry, onSave: onSave)
    }
}

// Wrapper for TransactionEditorSheet (which is private in AccountDetailView)
struct TransactionEditorSheetWrapper: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let entry: LedgerEntry
    
    var body: some View {
        // Use the same editor structure as AccountDetailView
        LedgerEntryEditorView(entry: entry, onSave: { date, title, btcAmount, usdAmount, btcPrice, isCleared, notes, category in
            accountViewModel.updateLedgerEntry(
                entry,
                date: date,
                title: title,
                btcAmount: btcAmount,
                usdAmount: usdAmount,
                btcPrice: btcPrice,
                isReconciled: isCleared,
                notes: notes,
                category: category
            )
        })
    }
}

// Replicate the editor functionality here since LedgerEntryEditorSheet is private
struct LedgerEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var categoryManager: CategoryManager
    
    let entry: LedgerEntry
    let onSave: (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void
    
    @State private var date: Date
    @State private var title: String
    @State private var btcSatsAmountString: String = ""
    @State private var usdAmountString: String = ""
    @State private var btcPriceString: String = ""
    @State private var isCleared: Bool
    @State private var notes: String
    @State private var category: String
    
    init(entry: LedgerEntry, onSave: @escaping (Date, String, Decimal?, Decimal?, Decimal?, Bool, String?, String?) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _date = State(initialValue: entry.date ?? Date())
        _title = State(initialValue: entry.title ?? "")
        _isCleared = State(initialValue: entry.isReconciledFlag)
        _notes = State(initialValue: entry.notes ?? "")
        _category = State(initialValue: entry.category ?? "")
        
        if let btc = entry.btcAmountDecimal as NSDecimalNumber? {
            _btcSatsAmountString = State(initialValue: String(format: "%.0f", btc.doubleValue))
        }
        if let usd = entry.usdAmountDecimal as NSDecimalNumber? {
            _usdAmountString = State(initialValue: String(format: "%.2f", usd.doubleValue))
        }
        if let price = entry.btcPriceAtTransactionDecimal as NSDecimalNumber? {
            _btcPriceString = State(initialValue: String(format: "%.2f", price.doubleValue))
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        TextField("Title", text: $title)
                            .onChange(of: title) { _, newValue in
                                if category.isEmpty {
                                    let suggested = CategorySuggester.suggest(
                                        for: newValue,
                                        priorCategory: accountViewModel.suggestedCategory(forTitle: newValue, account: entry.account)
                                    )
                                    if !suggested.isEmpty {
                                        category = suggested
                                    }
                                }
                            }
                        if !title.isEmpty {
                            Button {
                                title = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                }
                
                if let account = entry.account, account.currencyCode == "BTC" {
                    Section("Bitcoin Amount") {
                        HStack {
                            TextField("Sats", text: $btcSatsAmountString)
                                .keyboardType(.numberPad)
                            if !btcSatsAmountString.isEmpty {
                                Button {
                                    btcSatsAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                    Section("USD Amount") {
                        HStack {
                            TextField("Amount", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                            if !usdAmountString.isEmpty {
                                Button {
                                    usdAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                    Section("BTC Price") {
                        HStack {
                            TextField("Price", text: $btcPriceString)
                                .keyboardType(.decimalPad)
                            if !btcPriceString.isEmpty {
                                Button {
                                    btcPriceString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                } else {
                    Section("Amount") {
                        HStack {
                            TextField("Amount", text: $usdAmountString)
                                .keyboardType(.decimalPad)
                            if !usdAmountString.isEmpty {
                                Button {
                                    usdAmountString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Reconciled", isOn: $isCleared)
                    HStack(alignment: .top) {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                        if !notes.isEmpty {
                            Button {
                                notes = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                
                Section {
                    CategoryPicker(selection: $category, usage: accountViewModel.categoryUsage())
                        .environmentObject(categoryManager)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                }
            }
        }
    }
    
    private func saveEntry() {
        let btcAmount: Decimal? = {
            if let sats = Int(btcSatsAmountString), sats != 0 {
                return Decimal(sats)
            }
            return nil
        }()
        
        let usdAmount: Decimal? = {
            let cleaned = usdAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            if let amount = Decimal(string: cleaned), amount != 0 {
                return amount
            }
            return nil
        }()
        
        let btcPrice: Decimal? = {
            let cleaned = btcPriceString.replacingOccurrences(of: ",", with: "")
            if let price = Decimal(string: cleaned), price > 0 {
                return price
            }
            return nil
        }()
        
        let categoryValue = category.isEmpty ? nil : category
        
        onSave(date, title, btcAmount, usdAmount, btcPrice, isCleared, notes.isEmpty ? nil : notes, categoryValue)
        dismiss()
    }
}

struct CategoryTransactionRow: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let entry: LedgerEntry
    let category: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    var showsSwipeActions: Bool = true

    private var usdAmount: Decimal {
        guard let account = entry.account else { return .zero }

        if category == "Digital Wallet Fees" {
            if entry.feeAmountDecimal > 0 { return entry.feeAmountDecimal }
            let fromNotes = FeeParsing.feeFromNotes(entry.notes)
            if fromNotes > 0 { return fromNotes }
            guard account.feePercentageDecimal > 0 else { return .zero }

            let transactionAmount: Decimal
            if account.currencyCode == "BTC" {
                let usd = entry.usdAmountDecimal
                if usd != 0 {
                    transactionAmount = abs(usd)
                } else {
                    let btc = entry.amountInCurrency(for: account)
                    let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : bitcoinPriceService.btcToUsdRate
                    transactionAmount = abs(btc * price)
                }
            } else {
                let amt = entry.usdAmountDecimal != 0 ? entry.usdAmountDecimal : entry.amountDecimal
                transactionAmount = abs(amt)
            }
            return transactionAmount * (account.feePercentageDecimal / 100)
        }

        let signed: Decimal
        if account.currencyCode == "BTC" {
            let usd = entry.usdAmountDecimal
            if usd != 0 {
                signed = entry.isCredit ? usd : -usd
            } else {
                let btc = entry.amountInCurrency(for: account)
                let price = entry.btcPriceAtTransactionDecimal > 0 ? entry.btcPriceAtTransactionDecimal : bitcoinPriceService.btcToUsdRate
                let usdVal = btc * price
                signed = entry.isCredit ? usdVal : -usdVal
            }
        } else {
            let amt = entry.usdAmountDecimal != 0 ? entry.usdAmountDecimal : entry.amountDecimal
            signed = entry.isCredit ? amt : -amt
        }
        return signed
    }

    private var amountColor: Color {
        if category == "Income" { return .green }
        if category == "Digital Wallet Fees" { return .orange }
        return usdAmount < 0 ? .red : .green
    }

    var body: some View {
        if showsSwipeActions {
            rowButton
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            rowButton
        }
    }

    private var rowButton: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title ?? "Untitled")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let account = entry.account {
                        Text(account.name ?? "Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ActivityMoneyFormat.string(usd: abs(usdAmount), bitcoin: bitcoinPriceService))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(amountColor)
                    if let entryCategory = entry.category, !entryCategory.isEmpty,
                       category != "Income" && category != "Digital Wallet Fees" {
                        Text(entryCategory)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selection: String
    let usage: [String: CategoryUsage]
    @EnvironmentObject private var categoryManager: CategoryManager
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var selectionBeforeAdd = ""

    private static let addTag = "__new_category__"

    private var pickerSelected: String {
        selection == Self.addTag ? selectionBeforeAdd : selection
    }

    var body: some View {
        Picker("Category", selection: $selection) {
            Text("None").tag("")
            ForEach(categoryManager.displayCategories(usage: usage, selected: pickerSelected), id: \.self) { category in
                Text(category).tag(category)
            }
            Text("New Category…").tag(Self.addTag)
        }
        .pickerStyle(.menu)
        .onAppear {
            if selection != Self.addTag {
                selectionBeforeAdd = selection
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == Self.addTag {
                selection = selectionBeforeAdd
                newCategoryName = ""
                showingAddCategory = true
            } else {
                selectionBeforeAdd = newValue
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(
                categoryName: $newCategoryName,
                onSave: {
                    if let name = categoryManager.addCategory(newCategoryName) {
                        selection = name
                        selectionBeforeAdd = name
                    }
                    showingAddCategory = false
                    newCategoryName = ""
                },
                onCancel: {
                    showingAddCategory = false
                    newCategoryName = ""
                }
            )
        }
    }
}

struct AddCategorySheet: View {
    @Binding var categoryName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Category Name", text: $categoryName)
                            .focused($isTextFieldFocused)
                            .autocapitalization(.words)
                            .autocorrectionDisabled()
                        if !categoryName.isEmpty {
                            Button {
                                categoryName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                } header: {
                    Text("Enter a new category name")
                } footer: {
                    Text("This category will be added to your custom categories.")
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - USD vs Bitcoin backtest (tracked bills)

struct UsdBtcBacktestSection: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let appeared: Bool
    @State private var shareItem: ShareFileItem?

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("USD vs Bitcoin")
                        .font(.headline)
                    Spacer()
                    if let report = reportsViewModel.usdBtcReport, reportsViewModel.usdBtcBacktestEnabled, !report.trackedBillNames.isEmpty, !report.months.isEmpty {
                        shareMenu(for: report)
                    }
                    Toggle("USD vs Bitcoin", isOn: Binding(
                        get: { reportsViewModel.usdBtcBacktestEnabled },
                        set: { reportsViewModel.setUsdBtcBacktestEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(.green)
                }
                if reportsViewModel.usdBtcBacktestEnabled {
                    if let report = reportsViewModel.usdBtcReport, !report.trackedBillNames.isEmpty {
                        Text(report.trackedBillNames.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            backtestStat(title: "USD", value: currencyFormatter.string(from: report.totalUsd as NSDecimalNumber) ?? "$0")
                            Spacer()
                            backtestStat(title: "At payment", value: currencyFormatter.string(from: report.totalBtcAtTime as NSDecimalNumber) ?? "$0")
                            Spacer()
                            backtestStat(title: "BTC today", value: currencyFormatter.string(from: report.totalBtcValueNow as NSDecimalNumber) ?? "$0")
                        }
                        if !report.months.isEmpty {
                            Chart(report.months, id: \.month) { row in
                                LineMark(
                                    x: .value("Month", row.month),
                                    y: .value("USD", NSDecimalNumber(decimal: row.usdExpenses).doubleValue),
                                    series: .value("Series", "USD")
                                )
                                .foregroundStyle(.blue)
                                LineMark(
                                    x: .value("Month", row.month),
                                    y: .value("Today", NSDecimalNumber(decimal: row.btcValueNow).doubleValue),
                                    series: .value("Series", "Today")
                                )
                                .foregroundStyle(.orange)
                            }
                            .chartLegend(position: .bottom)
                            .frame(height: 140)
                        }
                        Text(caption(for: report))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pay a dollar bill in Bitcoin (sats) to see a 4-year USD vs BTC history. Months without imported payments use the current amount and historical Bitcoin prices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.06))
                    )
            )
            .opacity(appeared ? 1 : 0)
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url]) {
                    try? FileManager.default.removeItem(at: item.url)
                    shareItem = nil
                }
            }
    }

    @ViewBuilder
    private func shareMenu(for report: UsdBtcReportData) -> some View {
        if report.bills.count <= 1 {
            let names = report.trackedBillNames
            let months = report.bills.first?.months ?? report.months
            Button {
                share(title: BillBtcBacktest.shareTitle(billNames: names), months: months, monthsBack: report.monthsBack)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Export image")
        } else {
            Menu {
                ForEach(report.bills) { bill in
                    Button(BillBtcBacktest.shareTitle(billNames: [bill.name])) {
                        share(title: BillBtcBacktest.shareTitle(billNames: [bill.name]), months: bill.months, monthsBack: report.monthsBack)
                    }
                }
                Button(BillBtcBacktest.shareTitle(billNames: report.trackedBillNames)) {
                    share(title: BillBtcBacktest.shareTitle(billNames: report.trackedBillNames), months: report.months, monthsBack: report.monthsBack)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Export image")
        }
    }

    private func share(title: String, months: [UsdBtcMonthPoint], monthsBack: Int) {
        guard let url = UsdBtcShareExport.pngURL(title: title, months: months, monthsBack: monthsBack) else { return }
        HapticManager.shared.buttonTapped()
        shareItem = ShareFileItem(url: url)
    }

    private func backtestStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func caption(for report: UsdBtcReportData) -> String {
        var parts: [String] = []
        if report.actualMonths > 0 {
            parts.append("\(report.actualMonths) month\(report.actualMonths == 1 ? "" : "s") from imported payments")
        }
        if report.estimatedMonths > 0 {
            parts.append("\(report.estimatedMonths) estimated")
        }
        if parts.isEmpty {
            return "Hypothetical cost in BTC using historical prices until real payments are imported."
        }
        return parts.joined(separator: " · ") + "."
    }
}

// MARK: - Categorize Imports (Post-Import Bulk Review)

struct CategorizeImportsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @State private var groups: [(title: String, entries: [LedgerEntry])] = []
    @State private var assigned: [String: String] = [:]  // title -> category
    @State private var editingTitle: String?

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView("All Categorized", systemImage: "checkmark.circle", description: Text("Every transaction has a category."))
                } else {
                    List {
                        Section {
                            Text("\(groups.count) merchant\(groups.count == 1 ? "" : "s") with uncategorized transactions. Tap to assign a category — it applies to all matching transactions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(groups, id: \.title) { group in
                            let cat = assigned[group.title] ?? ""
                            Button {
                                editingTitle = group.title
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.title)
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)
                                        Text("\(group.entries.count) transaction\(group.entries.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if cat.isEmpty {
                                        Image(systemName: "tag")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: CategoryStyle.icon(for: cat))
                                                .foregroundStyle(CategoryStyle.color(for: cat))
                                            Text(cat)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: Binding(
                                get: { editingTitle == group.title },
                                set: { if !$0 { editingTitle = nil } }
                            ), arrowEdge: .trailing) {
                                ImportCategoryPickerPopover(
                                    currentCategory: cat,
                                    usage: accountViewModel.categoryUsage(),
                                    onSelect: { chosen in
                                        assigned[group.title] = chosen
                                        editingTitle = nil
                                    }
                                )
                                .environmentObject(categoryManager)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Categorize Imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyCategories()
                        dismiss()
                    }
                    .disabled(assigned.values.allSatisfy { $0.isEmpty })
                }
            }
            .onAppear {
                groups = accountViewModel.uncategorizedGroupedByTitle()
                // Pre-fill suggestions
                for group in groups {
                    let suggestion = accountViewModel.suggestedCategory(forTitle: group.title)
                        ?? CategorySuggester.suggest(for: group.title)
                    if !suggestion.isEmpty {
                        assigned[group.title] = suggestion
                    }
                }
            }
        }
    }

    private func applyCategories() {
        for (title, cat) in assigned where !cat.isEmpty {
            _ = accountViewModel.bulkSetCategory(cat, forTitle: title)
        }
    }
}

