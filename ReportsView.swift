//
//  ReportsView.swift
//  BillsAndBalance
//
//  Activity: pushed from Balance. Apple Card-style paging between periods.
//  Each page is a ScrollView + 16pt inset + snapshot cards. No wrapping NavigationStack.
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
    @State private var selectedAnchor: Date?
    @State private var isRecenteringPager = false

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
        periodPager
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .activityFloatingTabBarHidden()
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
        .onChange(of: selectedAnchor) { _, newValue in
            if let newValue {
                handleAnchorChange(newValue)
            }
        }
        .onChange(of: reportsViewModel.selectedMonth) { _, _ in
            if walletPeriod == .month, !isRecenteringPager {
                reportsViewModel.loadMonthlyReport()
            }
        }
        .onChange(of: reportsViewModel.lastUsedWalletPeriod) { _, _ in
            handlePeriodChange()
        }
        .onChange(of: reportsViewModel.selectedYear) { _, _ in
            if walletPeriod == .year, !isRecenteringPager {
                reportsViewModel.loadYearWrapReport()
            }
        }
        .onChange(of: reportsViewModel.selectedWeekStart) { _, _ in
            if walletPeriod == .week, !isRecenteringPager {
                reportsViewModel.loadWeekReport()
            }
        }
        .onChange(of: reportsViewModel.creditCardViewMode) { _, _ in
            handleCreditCardViewModeChange()
        }
    }

    private var periodPager: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pageAnchors, id: \.self) { date in
                        activityPage(
                            snapshot: snapshot(for: date),
                            fallbackTitle: reportsViewModel.periodTitle(for: walletPeriod, date: date),
                            showBacktest: isCurrentPage(date)
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(date)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedAnchor)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .accessibilityHint("Swipe left or right to change periods")
    }

    private var pageAnchors: [Date] {
        var dates = [
            reportsViewModel.adjacentAnchorDate(offset: -1),
            reportsViewModel.currentAnchorDate()
        ]
        let next = reportsViewModel.adjacentAnchorDate(offset: 1)
        if !reportsViewModel.isAnchorAfterPresentPeriod(next) {
            dates.append(next)
        }
        return dates
    }

    private func snapshot(for date: Date) -> ActivityPeriodSnapshot? {
        let snapshots = [
            reportsViewModel.previousPeriodSnapshot,
            reportsViewModel.currentPeriodSnapshot,
            reportsViewModel.nextPeriodSnapshot
        ].compactMap { $0 }
        return snapshots.first { isSamePeriod($0.anchorDate, date) }
    }

    private func isCurrentPage(_ date: Date) -> Bool {
        isSamePeriod(date, reportsViewModel.currentAnchorDate())
    }

    private func isSamePeriod(_ lhs: Date, _ rhs: Date) -> Bool {
        let calendar = Calendar.current
        switch walletPeriod {
        case .week:
            return calendar.isDate(lhs, equalTo: rhs, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
        case .year:
            return calendar.isDate(lhs, equalTo: rhs, toGranularity: .year)
        }
    }

    private func activityPage(
        snapshot: ActivityPeriodSnapshot?,
        fallbackTitle: String,
        showBacktest: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot?.title ?? fallbackTitle)
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let snapshot {
                    if snapshot.hasActivity {
                        periodCards(from: snapshot, showBacktest: showBacktest)
                    } else {
                        emptyPeriodPlaceholder
                    }
                } else if reportsViewModel.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    emptyPeriodPlaceholder
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .refreshable {
            reportsViewModel.loadMonthlyReport()
            reportsViewModel.loadYearWrapReport()
            reportsViewModel.loadWeekReport()
            await reportsViewModel.loadUsdBtcReport()
        }
    }

    private var emptyPeriodPlaceholder: some View {
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

    @ViewBuilder
    private func periodCards(from snapshot: ActivityPeriodSnapshot, showBacktest: Bool) -> some View {
        WalletTotalSpendingAppleCard(
            expenses: reportsViewModel.periodSpendingTotal(for: snapshot.period, date: snapshot.anchorDate),
            previousPeriodExpenses: snapshot.previousComparableSpending,
            periodType: snapshot.period,
            appeared: appeared,
            isCurrentPeriodInProgress: snapshot.isCurrentPeriodInProgress,
            anchorDate: snapshot.anchorDate
        )
        WalletIncomeFeesRows(
            income: snapshot.income,
            creditCardSpending: snapshot.creditCardSpending,
            appeared: appeared,
            onIncomeTap: {
                selectedCategory = "Income"
            }
        )
        if !snapshot.byCategory.isEmpty {
            WalletCategorySection(
                items: snapshot.byCategory,
                appeared: appeared,
                expandedCategories: $expandedCategories,
                onCategoryTap: { category in
                    selectedCategory = category
                },
                onTransactionTap: { entry in
                    selectedTransaction = entry
                },
                period: snapshot.period,
                anchorDate: snapshot.anchorDate
            )
        }
        if showBacktest, reportsViewModel.hasActiveBitcoinDigitalWallet {
            UsdBtcBacktestSection(appeared: appeared)
        }
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
                    isRecenteringPager = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        reportsViewModel.jumpToCurrentPeriod()
                        selectedAnchor = reportsViewModel.currentAnchorDate()
                    }
                    DispatchQueue.main.async {
                        isRecenteringPager = false
                    }
                }
        )
    }

    private func handleAppear() {
        isRecenteringPager = true
        reportsViewModel.jumpToCurrentPeriod()
        selectedAnchor = reportsViewModel.currentAnchorDate()
        reportsViewModel.loadMonthlyReport()
        reportsViewModel.loadYearWrapReport()
        reportsViewModel.loadWeekReport()
        Task {
            await reportsViewModel.loadUsdBtcReport()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isRecenteringPager = false
            appeared = true
        }
    }

    private func handleAnchorChange(_ newValue: Date) {
        guard !isRecenteringPager else { return }
        let current = reportsViewModel.currentAnchorDate()
        guard !isSamePeriod(newValue, current) else { return }
        isRecenteringPager = true
        reportsViewModel.shiftPeriod(newValue < current ? -1 : 1)
        selectedAnchor = reportsViewModel.currentAnchorDate()
        DispatchQueue.main.async {
            isRecenteringPager = false
        }
    }

    private func handlePeriodChange() {
        isRecenteringPager = true
        reportsViewModel.jumpToCurrentPeriod()
        selectedAnchor = reportsViewModel.currentAnchorDate()
        DispatchQueue.main.async {
            isRecenteringPager = false
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
