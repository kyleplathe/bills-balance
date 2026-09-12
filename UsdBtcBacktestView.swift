import SwiftUI

struct UsdBtcBacktestView: View {
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @State private var shareItem: ShareFileItem?
    @State private var lookback: BillBtcBacktest.LookbackPreset = .fiveYears

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !reportsViewModel.usdBtcAvailableBillNames.isEmpty {
                    storyCard(report: displayedReport)
                } else if reportsViewModel.usdBtcIsLoading {
                    ProgressView("Loading Bitcoin history…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Bitcoin Deflation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let report = displayedReport, !report.bills.isEmpty {
                    shareButton(for: report)
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: item.activityItems) {
                if let url = item.url {
                    try? FileManager.default.removeItem(at: url)
                }
                shareItem = nil
            }
            .id(item.id)
        }
        .task {
            lookback = BillBtcBacktest.LookbackPreset.fromStoredMonths(reportsViewModel.usdBtcMonthsBack)
            await reportsViewModel.loadUsdBtcReport()
        }
    }

    private var displayedReport: UsdBtcReportData? {
        guard let full = reportsViewModel.usdBtcReport else { return nil }
        return BillBtcBacktest.windowed(
            reportsViewModel.filteredUsdBtcReport(full),
            monthsBack: lookback.rawValue
        )
    }

    private func storyCard(report: UsdBtcReportData?) -> some View {
        let change = report.flatMap { BillBtcBacktest.storyChange(from: $0) }
        let averages = report.flatMap { BillBtcBacktest.storyAverages(from: $0) }
        return VStack(alignment: .leading, spacing: 18) {
            if let report, !report.bills.isEmpty {
                storyHeader(change: change, averages: averages, report: report)
                UsdBtcComparisonChart(
                    bills: orderedBills(report.bills),
                    style: .inApp,
                    colorNames: reportsViewModel.usdBtcAvailableBillNames,
                    onReorder: { names in
                        reportsViewModel.setUsdBtcBillOrder(names)
                    }
                )
                .id("\(lookback.rawValue)-\(report.bills.map(\.name).joined(separator: ","))")
            } else {
                Text("Turn on a bill to see Bitcoin over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            lookbackControl(report: report)
            billChips
            Text(BillBtcBacktest.historicalDisclaimer)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(18)
        .background(cardBackground)
    }

    private func storyHeader(
        change: BillBtcBacktest.BitcoinSpendChange?,
        averages: BillBtcBacktest.MonthlyAverages?,
        report: UsdBtcReportData
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            UsdBtcStoryHeadline(change: change, billCount: report.bills.count, style: .inApp)

            if let snapshot = BillBtcBacktest.thenNow(from: report) {
                UsdBtcThenNowComparison(snapshot: snapshot, style: .inApp)
                    .id("\(snapshot.thenLabel)-\(snapshot.thenSats)-\(snapshot.nowSats)")
            } else if let averages {
                Text(BillBtcBacktest.compactUsd((averages.monthlyUsd as NSDecimalNumber).doubleValue) + "/mo avg")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func orderedBills(_ bills: [UsdBtcBillSeries]) -> [UsdBtcBillSeries] {
        BillBtcBacktest.orderedBills(bills, by: reportsViewModel.orderedUsdBtcNames(bills.map(\.name)))
    }

    private var lookbackBinding: Binding<BillBtcBacktest.LookbackPreset> {
        Binding(
            get: { lookback },
            set: { newValue in
                lookback = newValue
                reportsViewModel.setUsdBtcMonthsBack(newValue.rawValue)
            }
        )
    }

    private func lookbackControl(report: UsdBtcReportData?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Lookback", selection: lookbackBinding) {
                ForEach(BillBtcBacktest.LookbackPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Lookback")
            Text(BillBtcBacktest.lookbackDataStatus(actualMonths: report?.actualMonths ?? 0))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var billChips: some View {
        let names = reportsViewModel.usdBtcAvailableBillNames
        return Group {
            if names.isEmpty {
                Text("No tracked bills yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paid in Bitcoin")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(names, id: \.self) { name in
                            let included = reportsViewModel.isUsdBtcBillIncluded(name)
                            Button {
                                reportsViewModel.toggleUsdBtcBill(name)
                                HapticManager.shared.buttonTapped()
                            } label: {
                                Text(name)
                                    .lineLimit(1)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(included ? Color.primary : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(included
                                                  ? Color(red: 0.969, green: 0.576, blue: 0.102).opacity(0.18)
                                                  : Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(included
                                                          ? Color(red: 0.969, green: 0.576, blue: 0.102).opacity(0.45)
                                                          : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .opacity(included ? 1 : 0.55)
                            .accessibilityAddTraits(included ? [.isSelected] : [])
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mark a dollar bill paid from your Bitcoin wallet to see how much less Bitcoin it takes over time.")
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

    private func shareButton(for report: UsdBtcReportData) -> some View {
        Button {
            share(report)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .offset(y: -0.5)
        }
        .accessibilityLabel("Share")
    }

    private func share(_ report: UsdBtcReportData) {
        let names = reportsViewModel.orderedUsdBtcNames(report.trackedBillNames)
        guard let image = UsdBtcShareCard.pngImage(
            title: BillBtcBacktest.shareTitle(billNames: names),
            bills: orderedBills(report.bills),
            monthsBack: report.monthsBack,
            colorNames: names
        ) else { return }
        HapticManager.shared.buttonTapped()
        shareItem = ShareFileItem(image: image)
    }
}
