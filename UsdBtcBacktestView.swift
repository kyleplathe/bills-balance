import SwiftUI
import Charts

struct UsdBtcBacktestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @State private var shareItem: ShareFileItem?
    @State private var monthsBack: Double = 48

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
            .navigationTitle("USD vs Bitcoin")
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
            HStack {
                backtestStat(title: "USD", value: currencyFormatter.string(from: report.totalUsd as NSDecimalNumber) ?? "$0")
                Spacer()
                backtestStat(title: "At payment", value: currencyFormatter.string(from: report.totalBtcAtTime as NSDecimalNumber) ?? "$0")
                Spacer()
                backtestStat(title: "BTC today", value: currencyFormatter.string(from: report.totalBtcValueNow as NSDecimalNumber) ?? "$0")
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func chartSection(_ report: UsdBtcReportData) -> some View {
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
            .foregroundStyle(Color(red: 0.969, green: 0.576, blue: 0.102))
        }
        .chartLegend(position: .bottom)
        .frame(height: 180)
        .padding(16)
        .background(cardBackground)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pay a dollar bill in Bitcoin (sats) to see a USD vs BTC history. Months without imported payments use the current amount and historical Bitcoin prices.")
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
