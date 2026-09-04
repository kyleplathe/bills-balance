//
//  ReportsView.swift
//  BillsAndBalance
//
//  Activity: pushed from Balance. ScrollView + snapshot cards (same chrome as Balance).
//  No List, no paging TabView, no edge-bleed padding.
//

import SwiftUI

private struct ActivityNamedSheet: Identifiable {
    let id: String
}

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var categoryManager: CategoryManager
    @State private var appeared = false
    @State private var selectedCategory: String?
    @State private var expandedCategories: Set<String> = []
    @State private var selectedTransaction: LedgerEntry?
    @State private var showCategorizeReview = false

    private var walletPeriod: ReportsViewModel.WalletPeriod {
        reportsViewModel.lastUsedWalletPeriod
    }

    private var walletPeriodBinding: Binding<ReportsViewModel.WalletPeriod> {
        Binding(
            get: { reportsViewModel.lastUsedWalletPeriod },
            set: { reportsViewModel.setLastUsedWalletPeriod($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(periodTitle)
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                periodBody
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .tabBar)
        .activityFloatingTabBarHidden()
        .refreshable {
            reportsViewModel.loadMonthlyReport()
            reportsViewModel.loadYearWrapReport()
            reportsViewModel.loadWeekReport()
            await reportsViewModel.loadUsdBtcReport()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
            ToolbarItem(placement: .principal) {
                periodPicker
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        let next: ReportsViewModel.CreditCardViewMode =
                            reportsViewModel.creditCardViewMode == .payments ? .transactions : .payments
                        reportsViewModel.setCreditCardViewMode(next)
                    } label: {
                        Label(
                            reportsViewModel.creditCardViewMode == .payments
                                ? "Show Card Transactions"
                                : "Show Card Payments",
                            systemImage: "creditcard"
                        )
                    }
                    let uncatCount = accountViewModel.uncategorizedEntryCount()
                    if uncatCount > 0 {
                        Button {
                            showCategorizeReview = true
                        } label: {
                            Label("Review Uncategorized (\(uncatCount))", systemImage: "tag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: Binding(
            get: { selectedCategory.map { ActivityNamedSheet(id: $0) } },
            set: { selectedCategory = $0?.id }
        )) { item in
            CategoryTransactionsView(
                category: item.id,
                period: walletPeriod
            )
            .environmentObject(reportsViewModel)
            .environmentObject(accountViewModel)
            .environmentObject(bitcoinPriceService)
            .environmentObject(categoryManager)
        }
        .sheet(item: Binding(
            get: { selectedTransaction.map { LedgerEntrySheetItem($0) } },
            set: { selectedTransaction = $0?.entry }
        ), onDismiss: {
            reportsViewModel.refresh()
        }) { item in
            TransactionEditorSheet(entry: item.entry)
                .environmentObject(accountViewModel)
                .environmentObject(bitcoinPriceService)
                .environmentObject(categoryManager)
        }
        .sheet(isPresented: $showCategorizeReview, onDismiss: {
            reportsViewModel.refresh()
        }) {
            CategorizeImportsView()
                .environmentObject(accountViewModel)
                .environmentObject(categoryManager)
        }
        .onAppear(perform: handleAppear)
        .onChange(of: reportsViewModel.selectedMonth) { _, _ in
            reportsViewModel.loadMonthlyReport()
        }
        .onChange(of: reportsViewModel.lastUsedWalletPeriod) { _, p in
            handlePeriodChange(p)
        }
        .onChange(of: reportsViewModel.selectedYear) { _, _ in
            if walletPeriod == .year {
                reportsViewModel.loadYearWrapReport()
            }
        }
        .onChange(of: reportsViewModel.selectedWeekStart) { _, _ in
            if walletPeriod == .week {
                reportsViewModel.loadWeekReport()
            }
        }
        .onChange(of: reportsViewModel.creditCardViewMode) { _, _ in
            handleCreditCardViewModeChange()
        }
    }

    @ViewBuilder
    private var periodBody: some View {
        if reportsViewModel.isLoading && !walletHasReport {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else if walletPeriod == .week, let r = reportsViewModel.weeklyReport {
            periodCards(
                expenses: r.expenses + r.digitalWalletFees,
                income: r.income,
                creditCardSpending: reportsViewModel.creditCardSpending(for: .week),
                byCategory: r.byCategory,
                period: .week,
                anchorDate: r.weekStart,
                showBacktest: true
            )
        } else if walletPeriod == .month, let r = reportsViewModel.monthlyReport {
            periodCards(
                expenses: r.expenses + r.digitalWalletFees,
                income: r.income,
                creditCardSpending: reportsViewModel.creditCardSpending(for: .month),
                byCategory: r.byCategory,
                period: .month,
                anchorDate: r.month,
                showBacktest: true
            )
        } else if walletPeriod == .year, let r = reportsViewModel.yearWrapReport {
            periodCards(
                expenses: r.expenses + r.digitalWalletFees,
                income: r.income,
                creditCardSpending: reportsViewModel.creditCardSpending(for: .year),
                byCategory: r.byCategory,
                period: .year,
                anchorDate: reportsViewModel.currentAnchorDate(),
                showBacktest: true
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No data for this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    private func periodCards(
        expenses: Decimal,
        income: Decimal,
        creditCardSpending: Decimal,
        byCategory: [(name: String, amount: Decimal)],
        period: ReportsViewModel.WalletPeriod,
        anchorDate: Date,
        showBacktest: Bool
    ) -> some View {
        WalletTotalSpendingAppleCard(
            expenses: expenses,
            previousPeriodExpenses: reportsViewModel.previousPeriodExpenses(for: period),
            periodType: period,
            appeared: appeared,
            isCurrentPeriodInProgress: reportsViewModel.isCurrentPeriodInProgress(period),
            anchorDate: anchorDate
        )
        WalletIncomeFeesRows(
            income: income,
            creditCardSpending: creditCardSpending,
            appeared: appeared,
            onIncomeTap: {
                selectedCategory = "Income"
            }
        )
        if !byCategory.isEmpty {
            WalletCategorySection(
                items: byCategory,
                appeared: appeared,
                expandedCategories: $expandedCategories,
                onCategoryTap: { category in
                    selectedCategory = category
                },
                onTransactionTap: { entry in
                    selectedTransaction = entry
                },
                period: period,
                anchorDate: anchorDate
            )
        }
        if showBacktest, reportsViewModel.hasActiveBitcoinDigitalWallet {
            UsdBtcBacktestSection(appeared: appeared)
        }
    }

    private var walletHasReport: Bool {
        switch walletPeriod {
        case .week: return reportsViewModel.weeklyReport != nil
        case .month: return reportsViewModel.monthlyReport != nil
        case .year: return reportsViewModel.yearWrapReport != nil
        }
    }

    private var periodTitle: String {
        switch walletPeriod {
        case .week:
            if let r = reportsViewModel.weeklyReport {
                return weekRangeLabel(r.weekStart)
            }
            return "Week"
        case .month:
            return monthYearLabel(reportsViewModel.selectedMonth)
        case .year:
            if let r = reportsViewModel.yearWrapReport {
                return String(r.year)
            }
            return String(reportsViewModel.selectedYear)
        }
    }

    private func weekRangeLabel(_ weekStart: Date) -> String {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let y = DateFormatter()
        y.dateFormat = "yyyy"
        let startY = cal.component(.year, from: weekStart)
        let endY = cal.component(.year, from: end)
        let startStr = startY != endY ? "\(f.string(from: weekStart)), \(y.string(from: weekStart))" : f.string(from: weekStart)
        let endStr = startY != endY ? "\(f.string(from: end)), \(y.string(from: end))" : f.string(from: end)
        return "\(startStr) – \(endStr)"
    }

    private func monthYearLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    @ViewBuilder
    private var periodPicker: some View {
        if #available(iOS 26.0, *) {
            segmentedPeriodPicker
                .glassEffect(.regular.interactive())
        } else {
            segmentedPeriodPicker
        }
    }

    private var segmentedPeriodPicker: some View {
        Picker("Period", selection: walletPeriodBinding) {
            ForEach(ReportsViewModel.WalletPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: 240)
        .accessibilityElement(children: .contain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        reportsViewModel.jumpToCurrentPeriod()
                    }
                }
        )
    }

    private func handleAppear() {
        reportsViewModel.loadMonthlyReport()
        reportsViewModel.loadYearWrapReport()
        reportsViewModel.loadWeekReport()
        Task {
            await reportsViewModel.loadUsdBtcReport()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            appeared = true
        }
    }

    private func handlePeriodChange(_ p: ReportsViewModel.WalletPeriod) {
        switch p {
        case .week:
            reportsViewModel.selectedWeekStart = reportsViewModel.startOfWeek(for: Date())
            reportsViewModel.loadWeekReport()
        case .month:
            reportsViewModel.loadMonthlyReport()
        case .year:
            reportsViewModel.loadYearWrapReport()
        }
    }

    private func handleCreditCardViewModeChange() {
        switch walletPeriod {
        case .week:
            reportsViewModel.loadWeekReport()
        case .month:
            reportsViewModel.loadMonthlyReport()
        case .year:
            reportsViewModel.loadYearWrapReport()
        }
    }
}

private extension View {
    @ViewBuilder
    func activityFloatingTabBarHidden() -> some View {
        if #available(iOS 18.0, *) {
            self.toolbarVisibility(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

#Preview {
    let ctx = PersistenceController.shared.container.viewContext
    let vm = ReportsViewModel(context: ctx, bitcoinPriceService: .shared, creditCardManager: CreditCardManager())
    let accountVM = AccountViewModel(context: ctx)
    let billVM = BillViewModel(context: ctx, accountViewModel: accountVM)
    return NavigationStack {
        ReportsView()
            .environmentObject(vm)
            .environmentObject(BitcoinPriceService.shared)
            .environmentObject(accountVM)
            .environmentObject(CategoryManager())
            .environmentObject(billVM)
    }
}
