import SwiftUI

struct UsdBtcBacktestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @State private var shareItem: ShareFileItem?
    @State private var monthsBack: Double = 48
    @State private var showInflationAdjusted: Bool = false

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    lookbackSection
                    expensePickerSection
                    inflationToggleSection
                    if let report = reportsViewModel.usdBtcReport, !report.trackedBillNames.isEmpty {
                        statsSection(report)
                        chartSection(report)
                        Text(caption(for: report))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Bitcoin Deflation")
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
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let report = reportsViewModel.usdBtcReport, !report.months.isEmpty {
                        shareMenu(for: report)
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url]) {
                    try? FileManager.default.removeItem(at: item.url)
                    shareItem = nil
                }
            }
            .task {
                monthsBack = Double(reportsViewModel.usdBtcMonthsBack)
                await reportsViewModel.loadUsdBtcReport()
            }
        }
    }
    
    private var inflationToggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inflation Adjustment")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $showInflationAdjusted)
                    .labelsHidden()
                    .tint(Color(red: 0.969, green: 0.576, blue: 0.102))
            }
            if showInflationAdjusted {
                Text("Shows sats needed accounting for USD inflation (~3% annually). Green dashed line shows inflation-adjusted amount.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Shows nominal sats needed without inflation adjustment. Enable to see Bitcoin vs USD inflation comparison.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var lookbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lookback")
                    .font(.headline)
                Spacer()
                Text(lookbackLabel)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $monthsBack, in: 12...48, step: 12) {
                Text("Lookback")
            }
            .tint(Color(red: 0.969, green: 0.576, blue: 0.102))
            .onChange(of: monthsBack) { _, newValue in
                reportsViewModel.setUsdBtcMonthsBack(Int(newValue))
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var expensePickerSection: some View {
        let names = reportsViewModel.usdBtcAvailableBillNames
        return VStack(alignment: .leading, spacing: 10) {
            Text("Expenses")
                .font(.headline)
            if names.isEmpty {
                Text("No tracked bills yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.self) { name in
                    Button {
                        reportsViewModel.toggleUsdBtcBill(name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: reportsViewModel.isUsdBtcBillIncluded(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(reportsViewModel.isUsdBtcBillIncluded(name) ? Color(red: 0.969, green: 0.576, blue: 0.102) : .secondary)
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var lookbackLabel: String {
        let years = Int(monthsBack) / 12
        if years == 1 { return "1 year" }
        return "\(years) years"
    }

    private func statsSection(_ report: UsdBtcReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.trackedBillNames.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            let firstSats = report.months.first?.btcAtTime ?? 0
            let lastSats = report.months.last?.btcAtTime ?? 0
            let totalFirstSats = firstSats * 100_000_000
            let totalLastSats = lastSats * 100_000_000
            let reduction = firstSats > 0 ? ((firstSats - lastSats) / firstSats) * 100 : 0
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    backtestStat(title: "Bill amount", value: currencyFormatter.string(from: report.totalUsd as NSDecimalNumber) ?? "$0")
                    Spacer()
                }
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Started")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let first = report.months.first {
                            Text(formatSatsCompact(totalFirstSats))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color(red: 0.969, green: 0.576, blue: 0.102))
                                .monospacedDigit()
                            Text(yearLabel(for: first.month))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 18)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let last = report.months.last {
                            Text(formatSatsCompact(totalLastSats))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color(red: 0.969, green: 0.576, blue: 0.102))
                                .monospacedDigit()
                            Text(yearLabel(for: last.month))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                    
                    if reduction > 0 {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Reduction")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", (reduction as NSDecimalNumber).doubleValue))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                            Text("less sats")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func formatSatsCompact(_ sats: Decimal) -> String {
        let satsDouble = (sats as NSDecimalNumber).doubleValue
        if satsDouble >= 1_000_000 {
            return String(format: "%.2fM", satsDouble / 1_000_000)
        } else if satsDouble >= 1_000 {
            return String(format: "%.1fK", satsDouble / 1_000)
        } else {
            return String(format: "%.0f", satsDouble)
        }
    }
    
    private func yearLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func chartSection(_ report: UsdBtcReportData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                chartLegendSwatch(color: Color(red: 0.969, green: 0.576, blue: 0.102), title: "Sats needed")
                if showInflationAdjusted {
                    chartLegendSwatch(color: .green, title: "Inflation-adjusted", dashed: true)
                }
            }
            UsdBtcComparisonChart(months: report.months, style: .inApp, showInflationAdjusted: showInflationAdjusted)
                .frame(height: 180)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func chartLegendSwatch(color: Color, title: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 2)
                    .overlay(
                        Rectangle()
                            .fill(.white)
                            .frame(width: 3, height: 2)
                            .offset(x: -3)
                    )
                    .overlay(
                        Rectangle()
                            .fill(.white)
                            .frame(width: 3, height: 2)
                            .offset(x: 3)
                    )
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pay a dollar bill in Bitcoin (sats) to see Bitcoin deflation over time. The chart shows how many fewer sats you need to pay the same bill as Bitcoin's purchasing power increases.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            )
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
                    .font(.title2)
            }
            .accessibilityLabel("Share")
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
                    .font(.title2)
            }
            .accessibilityLabel("Share")
        }
    }

    private func share(title: String, months: [UsdBtcMonthPoint], monthsBack: Int) {
        guard let url = UsdBtcShareCard.pngURL(title: title, months: months, monthsBack: monthsBack) else { return }
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
