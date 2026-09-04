//
//  BillListView.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import SwiftUI
import CoreData
import UIKit

private func formatUSD(_ value: Decimal) -> String? {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: value as NSDecimalNumber)
}

struct BillListView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingAddBill = false
    @State private var selectedBill: Bill?
    @State private var showingDeleteAlert = false
    @State private var billToDelete: Bill?
    @State private var searchText: String = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var showPaidBills = false
    @State private var showCurrentMonthPaidBills = false
    @State private var coinAnimations: [CoinAnimation] = []
    @State private var dollarAnimations: [DollarAnimation] = []
    @State private var coinsDropped = false
    @State private var lastShakeTime: Date = Date.distantPast
    @State private var animationGeometrySize: CGSize = UIScreen.main.bounds.size
    @State private var neonGlowIntensity: Double = 0.5
    @State private var lastProgressState: (paid: Int, total: Int) = (0, 0)
    @State private var isComplete: Bool = false
    @State private var showingSatsInputSheet = false
    @State private var billToMarkPaid: Bill?
    @State private var satsInputText: String = ""
    @State private var completionPulseScale: Double = 1.0
    @State private var completionShimmerOffset: Double = -1.0
    @State private var completionGlowRadius: Double = 8.0
    @State private var showingManageBills = false
    
    struct CoinAnimation: Identifiable {
        let id = UUID()
        var position: CGPoint
        var rotation: Double = 0
        var opacity: Double = 1.0
        var size: CGFloat = 68
        var startFrame: Int = 0
        var spinInterval: Double = 0.11
    }
    
    struct DollarAnimation: Identifiable {
        let id: UUID
        let spec: FloatingDollarSpec

        init(spec: FloatingDollarSpec) {
            self.id = spec.id
            self.spec = spec
        }
    }
    
    let filterMonth: Date?
    
    init(filterMonth: Date? = nil) {
        self.filterMonth = filterMonth
    }
    
    private var useCompactRows: Bool {
        verticalSizeClass == .compact || filterMonth != nil
    }
    
    private var billRowInsets: EdgeInsets {
        useCompactRows
            ? EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            : EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                bitcoinOverlay
                billListContent
                ForEach(coinAnimations) { coin in
                    FallingBitcoinCoinView(
                        size: coin.size,
                        startFrame: coin.startFrame,
                        spinning: true,
                        spinInterval: coin.spinInterval
                    )
                    .rotationEffect(.degrees(coin.rotation))
                    .opacity(coin.opacity)
                    .position(coin.position)
                    .allowsHitTesting(false)
                }

                ForEach(dollarAnimations) { dollar in
                    FallingDollarBillView(spec: dollar.spec)
                }
                
            }
            .onAppear {
                // Store geometry size for animation positioning
                animationGeometrySize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                animationGeometrySize = newSize
            }
        }
        .onShake {
            // Debounce: prevent rapid shakes (at least 0.5 seconds apart)
            let now = Date()
            guard now.timeIntervalSince(lastShakeTime) > 0.5 else { return }
            lastShakeTime = now
            
            HapticManager.shared.buttonTapped()
            
            // Read current state
            let wasEnabled = bitcoinPriceService.showInBitcoin
            
            if !wasEnabled {
                withAnimation {
                    bitcoinPriceService.showInBitcoin = true
                }
                bitcoinPriceService.fetchBitcoinPrice()
                dollarAnimations.removeAll()
                if !coinsDropped {
                    dropCoins(count: Int.random(in: 6...10))
                    coinsDropped = true
                }
            } else {
                bitcoinPriceService.showInBitcoin = false
                dropDollars(count: Int.random(in: 7...11))
                coinsDropped = false
                coinAnimations.removeAll()
            }
        }
        .onChange(of: bitcoinPriceService.showInBitcoin) { oldValue, newValue in
            if !newValue {
                // Reset coins when disabling bitcoin mode (backup cleanup)
                coinsDropped = false
                coinAnimations.removeAll()
            }
        }
    }
    
    @ViewBuilder
    private var bitcoinOverlay: some View {
        if bitcoinPriceService.showInBitcoin {
            Color.orange.opacity(0.03)
                .ignoresSafeArea()
                .transition(.opacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: bitcoinPriceService.showInBitcoin)
        }
    }
    
    private var billListContent: some View {
        billList
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            addBillButton
            searchButton
            menuButton
        }
    }
    
    private var addBillButton: some View {
        Button {
            HapticManager.shared.buttonTapped()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingAddBill = true
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
        .transaction { transaction in
            transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
        }
    }
    
    private var searchButton: some View {
        Button {
            HapticManager.shared.buttonTapped()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSearchPresented.toggle()
            }
            if isSearchPresented {
                // Focus the search field after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
                searchText = ""
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title2)
        }
        .transaction { transaction in
            transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
        }
    }
    
    private var menuButton: some View {
        Menu {
            Button {
                showingManageBills = true
            } label: {
                Label("Manage Bills", systemImage: "list.bullet.rectangle")
            }
            Button {
                withAnimation {
                    let willShowPaidBills = !showPaidBills
                    showPaidBills.toggle()
                    // Also show/hide current month paid bills when toggling
                    showCurrentMonthPaidBills = willShowPaidBills
                }
            } label: {
                Label(showPaidBills ? "Hide Paid Bills" : "Show Paid Bills", 
                      systemImage: showPaidBills ? "eye.slash" : "eye")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
        .transaction { transaction in
            transaction.animation = .spring(response: 0.3, dampingFraction: 0.7)
        }
    }

    
    var body: some View {
        navigationContent
            .sheet(isPresented: $showingAddBill) {
                AddEditBillView()
                    .environmentObject(billViewModel)
            }
            .sheet(item: $selectedBill) { bill in
                AddEditBillView(bill: bill)
                    .environmentObject(billViewModel)
            }
            .sheet(isPresented: $showingManageBills) {
                ManageBillsView()
                    .environmentObject(billViewModel)
                    .environmentObject(accountViewModel)
            }
            .alert("Delete Bill", isPresented: $showingDeleteAlert) {
                deleteBillAlertButtons
            } message: {
                deleteBillAlertMessage
            }
            .sheet(isPresented: $showingSatsInputSheet) {
                if let bill = billToMarkPaid {
                    SatsInputSheet(
                        bill: bill,
                        satsInputText: $satsInputText,
                        onConfirm: { satsAmount in
                            if let sats = satsAmount {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                    billViewModel.togglePaidStatus(for: bill, satsAmount: sats)
                                }
                                HapticManager.shared.billMarkedPaid()
                            }
                            showingSatsInputSheet = false
                            billToMarkPaid = nil
                            satsInputText = ""
                        },
                        onCancel: {
                            showingSatsInputSheet = false
                            billToMarkPaid = nil
                            satsInputText = ""
                        }
                    )
                }
            }
    }
    
    private var navigationContent: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Bills")
                .navigationBarTitleDisplayMode(useCompactRows ? .inline : .large)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isSearchPresented {
                        liquidGlassSearchBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .toolbar {
                    toolbarContent
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchPresented)
        }
    }
    
    private var liquidGlassSearchBar: some View {
        VStack(spacing: 0) {
            // Liquid glass material background
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    
                    TextField("Search bills", text: $searchText)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background {
                    // Pill-shaped container with liquid glass effect
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                }
                
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSearchPresented = false
                        isSearchFocused = false
                        searchText = ""
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                // Liquid glass effect with blur
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
    
    @ViewBuilder
    private var deleteBillAlertButtons: some View {
        Button("Delete", role: .destructive) {
            if let bill = billToDelete {
                billViewModel.deleteBill(bill)
                HapticManager.shared.billDeleted()
            }
            billToDelete = nil
        }
        Button("Cancel", role: .cancel) {
            billToDelete = nil
        }
    }
    
    @ViewBuilder
    private var deleteBillAlertMessage: some View {
        if let bill = billToDelete {
            Text("Are you sure you want to delete '\(bill.name ?? "this bill")'?")
        }
    }
    
    // MARK: - Monthly Summary
    private var summarySection: some View {
        Section {
            summaryCard
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
    
    private var summaryCard: some View {
        let currencyCode = Locale.current.currency?.identifier ?? "USD"
        let isBitcoinMode = bitcoinPriceService.showInBitcoin
        let backgroundColor: Color = isBitcoinMode 
            ? (colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.08))
            : (colorScheme == .dark ? Color.black.opacity(0.82) : Color(.secondarySystemBackground))
        let borderColor: Color = isBitcoinMode
            ? Color.orange.opacity(0.3)
            : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(monthFormatter.string(from: Date()))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        Text("Monthly Snapshot")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        if isBitcoinMode {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    
                    Group {
                        if isBitcoinMode {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bitcoinPriceService.formatAsSats(Decimal(currentMonthTotalAmount)))
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("Remaining: \(bitcoinPriceService.formatAsSats(Decimal(currentMonthRemainingAmount)))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if bitcoinPriceService.btcToUsdRate > 0 {
                                    if let btcPriceString = formatUSD(bitcoinPriceService.btcToUsdRate) {
                                        Text("BTC: \(btcPriceString)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .leading))
                            ))
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentMonthTotalAmount, format: .currency(code: currencyCode))
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                Text("Remaining: \(currentMonthRemainingAmount, format: .currency(code: currencyCode))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .leading)),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .trailing))
                            ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isBitcoinMode)
                }
                Spacer()
                if currentMonthBillCount > 0 {
                    VStack(alignment: .trailing, spacing: 8) {
                        ZStack(alignment: .trailing) {
                            // Neon glow progress bar
                            ZStack {
                                ProgressView(value: Double(currentMonthPaidCount),
                                             total: Double(currentMonthBillCount))
                                    .progressViewStyle(.linear)
                                    .tint(isBitcoinMode ? .orange : .green)
                                    .frame(width: 120)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBitcoinMode)
                                    .shadow(color: isBitcoinMode ? Color.orange.opacity(0.8) : Color.green.opacity(0.8), radius: 4)
                                    .shadow(color: isBitcoinMode ? Color.orange.opacity(0.6) : Color.green.opacity(0.6), radius: 8)
                                    .shadow(color: isBitcoinMode ? Color.orange.opacity(0.4) : Color.green.opacity(0.4), radius: 12)
                                    .overlay(
                                        // Inner glow effect with pulse
                                        GeometryReader { geometry in
                                            let progress = currentMonthBillCount > 0 ? CGFloat(currentMonthPaidCount) / CGFloat(currentMonthBillCount) : 0
                                            ZStack {
                                                // Base inner glow - soft capsule shape to avoid rectangle edges
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [
                                                                (isBitcoinMode ? Color.orange : Color.green).opacity(0.3),
                                                                (isBitcoinMode ? Color.orange : Color.green).opacity(0.1),
                                                                (isBitcoinMode ? Color.orange : Color.green).opacity(0.3)
                                                            ],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: geometry.size.width * progress, height: geometry.size.height)
                                                    .blur(radius: 3)
                                                    .opacity(neonGlowIntensity)
                                                    // Subtle pulse - only slight scale when complete
                                                    .scaleEffect(x: isComplete ? min(completionPulseScale, 1.03) : 1.0, y: 1.0, anchor: .leading)
                                                
                                                // Completion shimmer effect
                                                if isComplete && progress >= 1.0 {
                                                    Capsule()
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [
                                                                    Color.white.opacity(0),
                                                                    Color.white.opacity(0.6),
                                                                    Color.white.opacity(0)
                                                                ],
                                                                startPoint: UnitPoint(x: completionShimmerOffset, y: 0),
                                                                endPoint: UnitPoint(x: completionShimmerOffset + 0.3, y: 0)
                                                            )
                                                        )
                                                        .frame(width: geometry.size.width * progress, height: geometry.size.height)
                                                        .blur(radius: 1)
                                                }
                                            }
                                        }
                                    )
                            }
                        }
                        .onAppear {
                            // Check if already complete on appear
                            let nowComplete = currentMonthBillCount > 0 && currentMonthPaidCount == currentMonthBillCount
                            self.isComplete = nowComplete
                            
                            if nowComplete {
                                // Start completion animation if already complete
                                startCompletionAnimation()
                            } else {
                                // Start continuous neon glow animation
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                    neonGlowIntensity = 1.0
                                }
                            }
                            
                            // Update last state
                            lastProgressState = (currentMonthPaidCount, currentMonthBillCount)
                        }
                        .onChange(of: currentMonthPaidCount) { oldValue, newValue in
                            checkProgressCompletion(oldPaid: oldValue, newPaid: newValue)
                        }
                        .onChange(of: currentMonthBillCount) { oldValue, newValue in
                            checkProgressCompletion(oldPaid: currentMonthPaidCount, newPaid: currentMonthPaidCount)
                        }
                        
                        Text("\(currentMonthPaidCount) of \(currentMonthBillCount) paid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
                .overlay((isBitcoinMode ? Color.orange.opacity(0.3) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12)))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBitcoinMode)
            
            HStack(spacing: 12) {
                SummaryPill(title: "\(currentMonthUnpaidCount)",
                            subtitle: "Unpaid",
                            tint: isBitcoinMode ? .orange : .blue)
                SummaryPill(title: "\(currentMonthOverdueCount)",
                            subtitle: "Overdue",
                            tint: .red)
                
                // Make paid pill tappable to show/hide paid bills
                if currentMonthPaidCount > 0 {
                    Button {
                        HapticManager.shared.buttonTapped()
                        withAnimation {
                            showCurrentMonthPaidBills.toggle()
                        }
                    } label: {
                        SummaryPill(title: "\(currentMonthPaidCount)",
                                    subtitle: "Paid",
                                    tint: .green)
                    }
                    .buttonStyle(.plain)
                } else {
                    SummaryPill(title: "\(currentMonthPaidCount)",
                                subtitle: "Paid",
                                tint: .green)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBitcoinMode)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCurrentMonthPaidBills)
            
            if let upcoming = nextUpcomingBill,
               let dueDate = upcoming.dueDate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Due")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(upcoming.name ?? "Bill") • \(dueDate, format: .dateTime.month(.abbreviated).day())")
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor)
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isBitcoinMode)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Bills Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the + button to add your first bill")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                HapticManager.shared.buttonTapped()
                showingAddBill = true
            }) {
                Label("Add Bill", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
    
    private var noResultsView: some View {
        let query = normalizedSearchText
        return VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            if query.isEmpty {
                Text("No matching bills")
                    .font(.headline)
            } else {
                Text("No matches for \(query)")
                    .font(.headline)
            }
            Text("Try searching by bill name, account, notes, or amount.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Month Section Header
    private func monthSectionHeader(for date: Date) -> some View {
        HStack {
            Text(monthFormatter.string(from: date))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Spacer()
            
            let bills = billsForMonth(date)
            let unpaidCount = bills.filter { !$0.isPaid }.count
            if unpaidCount > 0 {
                Text("\(unpaidCount) \(unpaidCount == 1 ? "bill" : "bills")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var groupedBills: [Date: [Bill]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredBills) { bill in
            guard let dueDate = bill.dueDate else { return Date.distantPast }
            let components = calendar.dateComponents([.year, .month], from: dueDate)
            return calendar.date(from: components) ?? Date.distantPast
        }
    }
    
    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Helper to check if a bill is paid with credit card only (no account)
    private func isCreditCardOnlyBill(_ bill: Bill) -> Bool {
        if let paymentCard = bill.paymentCard, !paymentCard.isEmpty, bill.account == nil {
            return true
        }
        return false
    }
    
    // Helper to check if a bill has pending transactions (unreconciled ledger entries)
    private func hasPendingTransaction(_ bill: Bill) -> Bool {
        // Credit card bills shouldn't have pending transactions
        if isCreditCardOnlyBill(bill) {
            return false
        }
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry>, !entries.isEmpty else { return false }
        // Bill has pending transaction if it has any unreconciled ledger entries
        return entries.contains { !$0.isReconciledFlag }
    }
    
    // Helper to check if bill should be shown (unpaid or has pending transactions)
    private func shouldShowBill(_ bill: Bill) -> Bool {
        // Always show unpaid bills
        if !bill.isPaid {
            return true
        }
        // Credit card bills that are paid should not show (they don't affect account balance)
        if isCreditCardOnlyBill(bill) {
            return false
        }
        // Show paid bills that have pending (unreconciled) transactions
        return hasPendingTransaction(bill)
    }
    
    private var filteredBills: [Bill] {
        let calendar = Calendar.current
        let now = Date()

        // Determine which month we're viewing
        let viewingMonth = filterMonth ?? now
        
        // Always get all bills for the viewing month (including paid ones)
        // This ensures users can uncheck bills even after marking them paid
        let monthBills = billViewModel.fetchAllBillsForMonth(viewingMonth)
        
        // Get all other bills (from billViewModel.bills)
        var bills = billViewModel.bills
        
        // Add bills from the viewing month that might not be in the main list
        let existingBillIDs = Set(bills.map { $0.objectID })
        let missingMonthBills = monthBills.filter { !existingBillIDs.contains($0.objectID) }
        bills.append(contentsOf: missingMonthBills)
        
        // Filter by month
        var monthFilteredBills: [Bill]
        if filterMonth != nil {
            // Landscape month view: hide paid bills unless the toolbar toggle is on.
            // Pending (unreconciled) paid bills still show, matching portrait.
            monthFilteredBills = monthBills.filter { bill in
                shouldShowBill(bill) || showPaidBills
            }
        } else {
            // For current month view, show unpaid bills + bills with pending transactions
            // Optionally show all paid bills if toggled
            let currentMonthBills = monthBills
            let currentMonthVisibleBills = currentMonthBills.filter { bill in
                shouldShowBill(bill) || showCurrentMonthPaidBills
            }
            
            // Get next month's date
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) else {
                monthFilteredBills = currentMonthVisibleBills
                return monthFilteredBills
            }
            
            // Get bills for next month
            let nextMonthBills = billViewModel.fetchAllBillsForMonth(nextMonth)
            
            // Filter other bills (not current month)
            let otherBills = bills.filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                let billMonth = calendar.dateComponents([.year, .month], from: dueDate)
                let currentMonth = calendar.dateComponents([.year, .month], from: now)
                return billMonth != currentMonth
            }
            
            // Include other bills if they should be shown (unpaid or pending), or if showPaidBills is on
            let filteredOtherBills = otherBills.filter { bill in
                shouldShowBill(bill) || showPaidBills
            }
            
            // Include next month's bills - show all unpaid bills and bills with pending transactions
            let nextMonthVisibleBills = nextMonthBills.filter { bill in
                // Show if unpaid or has pending transaction
                !bill.isPaid || hasPendingTransaction(bill)
            }
            
            // Combine all bills and deduplicate by objectID to prevent showing the same bill multiple times
            let allCombinedBills = currentMonthVisibleBills + filteredOtherBills + nextMonthVisibleBills
            var seenBillIDs = Set<NSManagedObjectID>()
            monthFilteredBills = allCombinedBills.filter { bill in
                let billID = bill.objectID
                if seenBillIDs.contains(billID) {
                    return false // Skip duplicate
                }
                seenBillIDs.insert(billID)
                return true
            }
        }
        
        // Then filter by search query if present
        let query = normalizedSearchText
        guard !query.isEmpty else { return monthFilteredBills }
        return monthFilteredBills.filter { bill in
            let haystacks: [String] = [
                bill.name,
                bill.notes,
                bill.account?.name,
                bill.paymentCard
            ].compactMap { $0?.lowercased() }
            let needle = query.lowercased()
            if haystacks.contains(where: { $0.contains(needle) }) {
                return true
            }
            if let amount = bill.amount?.decimalValue {
                let amountString = NSDecimalNumber(decimal: amount).stringValue.lowercased()
                return amountString.contains(needle)
            }
            return false
        }
    }
    
    private func billsForMonth(_ monthDate: Date) -> [Bill] {
        (groupedBills[monthDate] ?? []).sorted { (bill1, bill2) in
            let date1 = bill1.dueDate ?? .distantFuture
            let date2 = bill2.dueDate ?? .distantFuture
            return date1 < date2
        }
    }
    
    private var currentMonthBills: [Bill] {
        // Get ALL bills for current month, not just visible ones
        // This ensures paid bills that have been filtered out still count toward monthly stats
        let now = Date()
        return billViewModel.fetchAllBillsForMonth(now)
    }
    
    private var currentMonthTotalAmount: Double {
        currentMonthBills.reduce(0) { $0 + ($1.amount?.doubleValue ?? 0) }
    }
    
    private var currentMonthUnpaidCount: Int {
        currentMonthBills.filter { !$0.isPaid }.count
    }
    
    private var currentMonthPaidCount: Int {
        currentMonthBills.filter { $0.isPaid }.count
    }
    
    private var currentMonthOverdueCount: Int {
        let now = Date()
        return currentMonthBills.filter { bill in
            guard let dueDate = bill.dueDate else { return false }
            return dueDate < now && !bill.isPaid
        }.count
    }
    
    private var currentMonthRemainingAmount: Double {
        let unpaidBills = currentMonthBills.filter { !$0.isPaid }
        let remaining = unpaidBills.reduce(0) { total, bill in
            let amount = bill.amount?.doubleValue ?? 0
            return total + amount
        }
        return remaining
    }

    private var currentMonthBillCount: Int {
        currentMonthBills.count
    }
    
    private var nextUpcomingBill: Bill? {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return billViewModel.bills
            .filter { bill in
                guard let dueDate = bill.dueDate else { return false }
                return !bill.isPaid && dueDate >= startOfToday
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first
    }
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private func dropCoins(count: Int) {
        let screenWidth = animationGeometrySize.width
        let screenHeight = animationGeometrySize.height
        let startY: CGFloat = -160
        let minX: CGFloat = 36
        let maxX = max(minX + 1, screenWidth - 36)

        for i in 0..<count {
            let delay = Double(i) * 0.07 + Double.random(in: 0...0.28)
            let xPosition = CGFloat.random(in: minX...maxX)
            let fallDuration = Double.random(in: 2.4...4.2)
            let rotationAmount = Double.random(in: -720...720)
            let size = CGFloat.random(in: 56...86)
            let startFrame = Int.random(in: 0..<BitcoinCoinFrame.spinSequence.count)
            let spinInterval = Double.random(in: 0.08...0.16)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let coin = CoinAnimation(
                    position: CGPoint(x: xPosition, y: startY),
                    size: size,
                    startFrame: startFrame,
                    spinInterval: spinInterval
                )
                let coinId = coin.id
                coinAnimations.append(coin)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeIn(duration: fallDuration)) {
                        if let index = coinAnimations.firstIndex(where: { $0.id == coinId }) {
                            var updatedCoin = coinAnimations[index]
                            updatedCoin.position.y = screenHeight + size
                            updatedCoin.rotation = rotationAmount
                            updatedCoin.opacity = 0
                            coinAnimations[index] = updatedCoin
                        }
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + fallDuration + 0.1) {
                    coinAnimations.removeAll { $0.id == coinId }
                }
            }
        }
    }

    private func dropDollars(count: Int) {
        let screenWidth = animationGeometrySize.width
        let screenHeight = animationGeometrySize.height
        let startY: CGFloat = -120
        let minX: CGFloat = 80
        let maxX = max(minX + 1, screenWidth - 80)

        for i in 0..<count {
            let delay = Double(i) * 0.07 + Double.random(in: 0...0.28)
            let xPosition = CGFloat.random(in: minX...maxX)
            let size = CGFloat.random(in: 132...178)
            let duration = Double.random(in: 2.4...4.2)
            let swayAmplitude = CGFloat.random(in: 36...72)
            let swayFrequency = Double.random(in: 1.6...2.5)
            let driftX = CGFloat.random(in: -80...80)
            let asset = DollarBillAsset.allCases.randomElement() ?? .one

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let spec = FloatingDollarSpec(
                    asset: asset,
                    start: CGPoint(x: xPosition, y: startY),
                    endY: screenHeight + size * 0.55,
                    width: size,
                    duration: duration,
                    spawnedAt: Date(),
                    phase: Double.random(in: 0...(2 * .pi)),
                    swayAmplitude: swayAmplitude,
                    swayFrequency: swayFrequency,
                    rollAmplitude: Double.random(in: 8...18),
                    yawAmplitude: Double.random(in: 42...68),
                    pitchAmplitude: Double.random(in: 6...13),
                    driftX: driftX
                )
                let dollar = DollarAnimation(spec: spec)
                dollarAnimations.append(dollar)

                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                    dollarAnimations.removeAll { $0.id == dollar.id }
                }
            }
        }
    }
    
    private func checkProgressCompletion(oldPaid: Int, newPaid: Int) {
        let nowComplete = currentMonthBillCount > 0 && currentMonthPaidCount == currentMonthBillCount
        let wasComplete = currentMonthBillCount > 0 && oldPaid == currentMonthBillCount
        
        // Update last state
        lastProgressState = (currentMonthPaidCount, currentMonthBillCount)
        
        // Only trigger haptic feedback if we just reached completion
        if nowComplete && !wasComplete {
            self.isComplete = true
            HapticManager.shared.success()
            
            // Start completion animation sequence
            startCompletionAnimation()
        } else if !nowComplete {
            // Stop all animations when progress becomes incomplete
            if wasComplete {
                // Transitioning from complete to incomplete - stop all animations immediately
                self.isComplete = false
                
                // Reset all animation values immediately (without animation) to stop ongoing animations
                // This will override any ongoing animations
                completionPulseScale = 1.0
                completionShimmerOffset = -1.0
                completionGlowRadius = 8.0
                
                // Reset glow intensity smoothly
                withAnimation(.easeOut(duration: 0.2)) {
                    neonGlowIntensity = 0.5
                }
                
                // Restart normal glow animation after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    // Only restart if still not complete (double-check)
                    if !self.isComplete {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            self.neonGlowIntensity = 1.0
                        }
                    }
                }
            } else {
                // Already incomplete, just ensure state is correct
                self.isComplete = false
            }
        } else if nowComplete {
            // Maintain completion state
            self.isComplete = true
        }
    }
    
    private func startCompletionAnimation() {
        // Reset shimmer offset first
        completionShimmerOffset = -1.0
        
        // Initial flash and expand
        withAnimation(.easeOut(duration: 0.2)) {
            neonGlowIntensity = 1.5
            completionGlowRadius = 20.0
            completionPulseScale = 1.02
        }
        
        // Shimmer animation - start after initial flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Check completion state before starting animation
            guard self.isComplete else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                self.completionShimmerOffset = 1.3
            }
        }
        
        // Pulsing glow effect - subtle pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Check completion state before starting animation
            guard self.isComplete else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true)) {
                self.completionPulseScale = 1.03
                self.completionGlowRadius = 25.0
            }
        }
        
        // Settle into continuous glow
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Check completion state before starting animation
            guard self.isComplete else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                self.neonGlowIntensity = 1.2
                self.completionGlowRadius = 12.0
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                self.completionPulseScale = 1.01
            }
        }
    }

    private var billList: some View {
        List {
            if filterMonth == nil {
                summarySection
            }
            
            if billViewModel.bills.isEmpty {
                emptyBillsSection
            } else if filteredBills.isEmpty {
                emptyFilteredSection
            } else {
                groupedBillSections
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var emptyBillsSection: some View {
        Section {
            emptyStateView
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
    
    private var emptyFilteredSection: some View {
        Section {
            Group {
                if filterMonth != nil {
                    monthFilterEmptyView
                } else {
                    noResultsView
                }
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 32, leading: 20, bottom: 32, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
    
    private var groupedBillSections: some View {
        ForEach(groupedBills.keys.sorted(), id: \.self) { monthDate in
            monthBillSections(for: monthDate)
        }
    }
    
    @ViewBuilder
    private func monthBillSections(for monthDate: Date) -> some View {
        let bills = billsForMonth(monthDate)
        let isCurrentMonth = filterMonth == nil && Calendar.current.isDate(monthDate, equalTo: Date(), toGranularity: .month)
        
        if isCurrentMonth && showCurrentMonthPaidBills {
            unpaidMonthSection(monthDate: monthDate, bills: bills.filter { !$0.isPaid })
            paidMonthSection(monthDate: monthDate, bills: bills.filter { $0.isPaid })
        } else {
            Section(header: monthSectionHeader(for: monthDate)) {
                ForEach(bills, id: \.objectID) { bill in
                    billListRow(for: bill)
                }
            }
        }
    }
    
    @ViewBuilder
    private func unpaidMonthSection(monthDate: Date, bills: [Bill]) -> some View {
        if !bills.isEmpty {
            Section(header: monthSectionHeader(for: monthDate)) {
                ForEach(bills, id: \.objectID) { bill in
                    billListRow(for: bill)
                }
            }
        }
    }
    
    @ViewBuilder
    private func paidMonthSection(monthDate: Date, bills: [Bill]) -> some View {
        if !bills.isEmpty {
            Section(header: paidBillsSectionHeader(for: monthDate)) {
                ForEach(bills, id: \.objectID) { bill in
                    billListRow(for: bill, showsUnpaidSwipe: true)
                }
            }
        }
    }
    
    private func paidBillsSectionHeader(for monthDate: Date) -> some View {
        HStack {
            Text(monthFormatter.string(from: monthDate))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
            Text("Paid Bills")
                .font(.caption)
                .foregroundColor(.green)
        }
    }
    
    private func billListRow(for bill: Bill, showsUnpaidSwipe: Bool = false) -> some View {
        BillRowView(bill: bill, onMarkPaid: { billToMark in
            markBillPaidFromRow(billToMark)
        }, compact: useCompactRows)
        .listRowInsets(billRowInsets)
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.buttonTapped()
            selectedBill = bill
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                billToDelete = bill
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            leadingSwipeActions(for: bill, showsUnpaidSwipe: showsUnpaidSwipe)
        }
    }
    
    @ViewBuilder
    private func leadingSwipeActions(for bill: Bill, showsUnpaidSwipe: Bool) -> some View {
        Button {
            HapticManager.shared.buttonTapped()
            selectedBill = bill
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
        
        if showsUnpaidSwipe {
            Button {
                billViewModel.togglePaidStatus(for: bill)
                HapticManager.shared.buttonTapped()
            } label: {
                Label("Unpaid", systemImage: "xmark")
            }
            .tint(.orange)
        } else if !bill.isPaid {
            Button {
                billViewModel.togglePaidStatus(for: bill)
                HapticManager.shared.billMarkedPaid()
            } label: {
                Label("Paid", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }
    
    private func markBillPaidFromRow(_ bill: Bill) {
        if let account = bill.account, account.currencyCode == "BTC" {
            billToMarkPaid = bill
            satsInputText = ""
            showingSatsInputSheet = true
        } else {
            billViewModel.togglePaidStatus(for: bill)
            HapticManager.shared.billMarkedPaid()
        }
    }
    
    private var monthFilterEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            if let filterMonth = filterMonth {
                Text("No bills in \(monthFormatter.string(from: filterMonth))")
                    .font(.headline)
            } else {
                Text("No bills this month")
                    .font(.headline)
            }
            Text("Navigate to a different month to see bills.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Bill List extras

private struct SummaryPill: View {
    let title: String
    let subtitle: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}


// MARK: - Sats Input Sheet
private struct SatsInputSheet: View {
    let bill: Bill
    @Binding var satsInputText: String
    let onConfirm: (Decimal?) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text("Enter Sats Amount")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Bill: \(bill.name ?? "Unknown")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let amount = bill.amount?.decimalValue {
                                Text("Bill Amount: $\(amount, format: .number.precision(.fractionLength(2)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 20)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sats Amount")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("0", text: $satsInputText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                                .focused($isTextFieldFocused)
                                .id("satsInputField")
                                .onChange(of: isTextFieldFocused) { _, isFocused in
                                    if isFocused {
                                        // Scroll to input field when keyboard appears
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation {
                                                proxy.scrollTo("satsInputField", anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        isTextFieldFocused = true
                                    }
                                }
                        
                        if let satsValue = Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")), satsValue > 0 {
                            let btcAmount = satsValue / 100_000_000
                            if let usdString = formatUSD(bitcoinPriceService.convertBTCToUSD(btcAmount)) {
                                Text("≈ \(usdString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        Button {
                            if let sats = Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")), sats > 0 {
                                onConfirm(sats)
                                dismiss()
                            }
                        } label: {
                            Text("Confirm")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")) != nil &&
                                    (Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")) ?? 0) > 0
                                    ? Color.green : Color.gray
                                )
                                .cornerRadius(12)
                        }
                        .disabled(Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")) == nil ||
                                 (Decimal(string: satsInputText.replacingOccurrences(of: ",", with: "")) ?? 0) <= 0)
                        
                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Pay with Bitcoin")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatUSD(_ value: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber)
    }
}

