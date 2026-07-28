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
    }
    
    struct DollarAnimation: Identifiable {
        let id = UUID()
        var position: CGPoint
        var rotation: Double = 0
        var opacity: Double = 1.0
    }
    
    let filterMonth: Date?
    
    init(filterMonth: Date? = nil) {
        self.filterMonth = filterMonth
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                bitcoinOverlay
                billListContent
                // Coin animations on top layer
                ForEach(coinAnimations) { coin in
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 55))
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(coin.rotation))
                        .opacity(coin.opacity)
                        .position(coin.position)
                }
                
                // Dollar bill animations on top layer
                ForEach(dollarAnimations) { dollar in
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 55))
                        .foregroundColor(.green)
                        .rotationEffect(.degrees(dollar.rotation))
                        .opacity(dollar.opacity)
                        .position(dollar.position)
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
                // Enabling bitcoin mode - animate and drop coins
                withAnimation {
                    bitcoinPriceService.showInBitcoin = true
                }
                
                // Clear any dollar animations
                dollarAnimations.removeAll()
                
                // Drop 6 coins only once when enabling bitcoin mode
                if !coinsDropped {
                    dropCoins(count: 6)
                    coinsDropped = true
                }
            } else {
                // Disabling bitcoin mode - drop dollars and toggle
                bitcoinPriceService.showInBitcoin = false
                dropDollars(count: 6)
                
                // Reset coins
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
            // When filtering by a specific month, show ALL bills for that month
            // This allows users to uncheck bills they accidentally marked as paid
            monthFilteredBills = monthBills
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
        let coinSize: CGFloat = 55 // Approximate coin size
        
        // Start coins from above the visible screen (falling from the sky)
        let startY: CGFloat = -150 // Start well above the visible screen
        
        // Spread coins across the ENTIRE width with minimal padding
        let minX = coinSize / 2 + 5 // Small padding to keep coin fully visible
        let maxX = screenWidth - (coinSize / 2) - 5 // Small padding on right
        
        for i in 0..<count {
            // More random stagger: between 0.05 and 0.4 seconds, with some randomness
            let baseDelay = Double(i) * 0.08
            let randomDelay = Double.random(in: 0...0.25)
            let delay = baseDelay + randomDelay
            
            // Random x position across the FULL width for better distribution
            let xPosition = CGFloat.random(in: minX...maxX)
            
            // Random fall duration for more natural look
            let fallDuration = Double.random(in: 2.5...4.0) // Slightly longer since they start higher
            
            // Random rotation speed
            let rotationAmount = Double.random(in: 360...1080)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let coin = CoinAnimation(
                    position: CGPoint(x: xPosition, y: startY)
                )
                let coinId = coin.id
                coinAnimations.append(coin)
                
                // Animate coin falling with random properties
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.linear(duration: fallDuration)) {
                        if let index = coinAnimations.firstIndex(where: { $0.id == coinId }) {
                            var updatedCoin = coinAnimations[index]
                            updatedCoin.position.y = screenHeight + 50
                            updatedCoin.rotation = rotationAmount
                            updatedCoin.opacity = 0
                            coinAnimations[index] = updatedCoin
                        }
                    }
                }
                
                // Remove coin after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + fallDuration + 0.1) {
                    coinAnimations.removeAll { $0.id == coinId }
                }
            }
        }
    }
    
    private func dropDollars(count: Int) {
        let screenWidth = animationGeometrySize.width
        let screenHeight = animationGeometrySize.height
        let dollarSize: CGFloat = 55 // Approximate dollar bill size
        
        // Start dollars from above the visible screen (falling from the sky)
        let startY: CGFloat = -150 // Start well above the visible screen
        
        // Spread dollar bills across the ENTIRE width with minimal padding
        let minX = dollarSize / 2 + 5 // Small padding to keep dollar fully visible
        let maxX = screenWidth - (dollarSize / 2) - 5 // Small padding on right
        
        for i in 0..<count {
            // More random stagger: between 0.05 and 0.4 seconds, with some randomness
            let baseDelay = Double(i) * 0.08
            let randomDelay = Double.random(in: 0...0.25)
            let delay = baseDelay + randomDelay
            
            // Random x position across the FULL width for better distribution
            let xPosition = CGFloat.random(in: minX...maxX)
            
            // Random fall duration for more natural look
            let fallDuration = Double.random(in: 2.5...4.0) // Slightly longer since they start higher
            
            // Random rotation speed
            let rotationAmount = Double.random(in: 360...1080)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let dollar = DollarAnimation(
                    position: CGPoint(x: xPosition, y: startY)
                )
                let dollarId = dollar.id
                dollarAnimations.append(dollar)
                
                // Animate dollar falling with random properties
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.linear(duration: fallDuration)) {
                        if let index = dollarAnimations.firstIndex(where: { $0.id == dollarId }) {
                            var updatedDollar = dollarAnimations[index]
                            updatedDollar.position.y = screenHeight + 50
                            updatedDollar.rotation = rotationAmount
                            updatedDollar.opacity = 0
                            dollarAnimations[index] = updatedDollar
                        }
                    }
                }
                
                // Remove dollar after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + fallDuration + 0.1) {
                    dollarAnimations.removeAll { $0.id == dollarId }
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
            // Only show summary if not filtering by month
            if filterMonth == nil {
                summarySection
            }
            
            if billViewModel.bills.isEmpty {
                Section {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } else if filteredBills.isEmpty {
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
            } else {
                ForEach(groupedBills.keys.sorted(), id: \.self) { monthDate in
                    let bills = billsForMonth(monthDate)
                    let isCurrentMonth = filterMonth == nil && Calendar.current.isDate(monthDate, equalTo: Date(), toGranularity: .month)
                    
                    if isCurrentMonth && showCurrentMonthPaidBills {
                        // Split current month bills into unpaid and paid sections
                        let unpaidBills = bills.filter { !$0.isPaid }
                        let paidBills = bills.filter { $0.isPaid }
                        
                        // Unpaid bills section
                        if !unpaidBills.isEmpty {
                            Section(header: monthSectionHeader(for: monthDate)) {
                                ForEach(unpaidBills, id: \.objectID) { bill in
                                    BillRowView(bill: bill, onMarkPaid: { billToMark in
                                        // Mark as paid - BillRowView will handle reconcile drawer if needed
                                        billViewModel.togglePaidStatus(for: billToMark)
                                        HapticManager.shared.billMarkedPaid()
                                    })
                                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
                                            Button {
                                                HapticManager.shared.buttonTapped()
                                                selectedBill = bill
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                            
                                            // Mark as Paid (cleared) - same as tapping circle
                                            if !bill.isPaid {
                                                Button {
                                                    billViewModel.togglePaidStatus(for: bill)
                                                    HapticManager.shared.billMarkedPaid()
                                                } label: {
                                                    Label("Paid", systemImage: "checkmark")
                                                }
                                                .tint(.green)
                                            }
                                        }
                                }
                            }
                        }
                        
                        // Paid bills section (with visual separator)
                        if !paidBills.isEmpty {
                            Section(header: HStack {
                                Text(monthFormatter.string(from: monthDate))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Paid Bills")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }) {
                                ForEach(paidBills, id: \.objectID) { bill in
                                    BillRowView(bill: bill, onMarkPaid: { billToMark in
                                        // For BTC accounts, show sats input sheet
                                        if let account = billToMark.account, account.currencyCode == "BTC" {
                                            billToMarkPaid = billToMark
                                            satsInputText = ""
                                            showingSatsInputSheet = true
                                        } else {
                                            billViewModel.togglePaidStatus(for: billToMark)
                                            HapticManager.shared.billMarkedPaid()
                                        }
                                    })
                                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
                                            Button {
                                                HapticManager.shared.buttonTapped()
                                                selectedBill = bill
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                            
                                            Button {
                                                billViewModel.togglePaidStatus(for: bill)
                                                HapticManager.shared.buttonTapped()
                                            } label: {
                                                Label("Unpaid", systemImage: "xmark")
                                            }
                                            .tint(.orange)
                                        }
                                }
                            }
                        }
                    } else {
                        // Regular section for other months or when paid bills are hidden
                        Section(header: monthSectionHeader(for: monthDate)) {
                            ForEach(bills, id: \.objectID) { bill in
                                BillRowView(bill: bill, onMarkPaid: { billToMark in
                                    billViewModel.togglePaidStatus(for: billToMark)
                                    HapticManager.shared.billMarkedPaid()
                                })
                                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
                                        Button {
                                            HapticManager.shared.buttonTapped()
                                            selectedBill = bill
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        
                                        // Mark as Paid (cleared) - same as tapping circle
                                        if !bill.isPaid {
                                            Button {
                                                billViewModel.togglePaidStatus(for: bill)
                                                HapticManager.shared.billMarkedPaid()
                                            } label: {
                                                Label("Paid", systemImage: "checkmark")
                                            }
                                            .tint(.green)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

// MARK: - Bill Row View
struct BillRowView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let bill: Bill
    var onMarkPaid: ((Bill) -> Void)? = nil
    
    @State private var showingReconcileDrawer = false
    @State private var billAmountString: String = ""
    @State private var feeAmountString: String = ""
    @State private var btcSatsAmountString: String = ""
    @State private var btcPriceString: String = ""
    @FocusState private var focusedField: ReconcileField?
    
    enum ReconcileField {
        case billAmount
        case feeAmount
        case btcSatsAmount
        case btcPrice
    }
    
    private var isOverdue: Bool {
        guard let dueDate = bill.dueDate else { return false }
        return dueDate < Date() && !bill.isPaid
    }
    
    private var daysUntilDue: Int {
        guard let dueDate = bill.dueDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }
    
    // Check if bill is paid with credit card only (no account)
    private var isCreditCardOnlyBill: Bool {
        if let paymentCard = bill.paymentCard, !paymentCard.isEmpty, bill.account == nil {
            return true
        }
        return false
    }
    
    // Check if bill has pending transactions (unreconciled ledger entries)
    private var hasPendingTransaction: Bool {
        // Credit card bills shouldn't have pending transactions
        if isCreditCardOnlyBill {
            return false
        }
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry>, !entries.isEmpty else { return false }
        return entries.contains { !$0.isReconciledFlag }
    }
    
    // Get the pending ledger entry for this bill
    private var pendingEntry: LedgerEntry? {
        guard let entries = bill.ledgerEntries as? Set<LedgerEntry> else { return nil }
        return entries.first { !$0.isReconciledFlag }
    }
    
    // Check if bill is in a BTC account
    private var isBTCAccount: Bool {
        bill.account?.currencyCode == "BTC"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
            // Status indicator with bitcoin theme
            Button {
                // Tap circle = Mark as cleared (paid)
                let willMarkPaid = !bill.isPaid
                
                if willMarkPaid {
                    // For BTC accounts, check if we need to show reconcile drawer
                    if isBTCAccount {
                        // Check if pending entry already has BTC price and sats values
                        if let entry = pendingEntry {
                            // Verify both BTC amount (sats) and BTC price are present and valid
                            let hasBTCAmount = entry.btcAmountDecimal > 0
                            let hasBTCPrice = entry.btcPriceAtTransactionDecimal > 0
                            
                            if hasBTCAmount && hasBTCPrice {
                                // Both sats and BTC price are present - reconcile with current info
                                // Mark the entry as reconciled
                                entry.isReconciledFlag = true
                                accountViewModel.saveContext()
                                
                                // Mark bill as paid
                                if !bill.isPaid {
                                    bill.isPaid = true
                                    bill.paidDate = Date()
                                    accountViewModel.saveContext()
                                    billViewModel.updateAppBadge()
                                }
                                
                                HapticManager.shared.billMarkedPaid()
                            } else {
                                // Missing BTC values (sats or price) - show drawer to enter them
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    showingReconcileDrawer = true
                                }
                            }
                        } else {
                            // No pending entry - show drawer to create new entry with BTC values
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                showingReconcileDrawer = true
                            }
                        }
                    } else {
                        // Non-BTC account - mark as paid directly
                        if let callback = onMarkPaid {
                            callback(bill)
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                billViewModel.togglePaidStatus(for: bill)
                            }
                            HapticManager.shared.billMarkedPaid()
                        }
                    }
                } else {
                    // Unmark as paid
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        billViewModel.togglePaidStatus(for: bill)
                    }
                    HapticManager.shared.buttonTapped()
                }
            } label: {
                // Show as unpaid (open circle) if bill has pending transactions, even if marked as paid
                let isFullyPaid = bill.isPaid && !hasPendingTransaction
                Circle()
                    .fill(isFullyPaid ? statusColor : Color.clear)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(bitcoinPriceService.showInBitcoin && !isFullyPaid ? .orange : statusColor, lineWidth: 2)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(isFullyPaid ? 1 : 0)
                    )
                    .padding(.vertical, 4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((bill.isPaid && !hasPendingTransaction) ? "Mark unpaid" : "Mark paid")
            .accessibilityHint("Tap to toggle paid state")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
            
            // Bill info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bill.name ?? "Unknown")
                        .font(.body)
                        .fontWeight(.medium)
                        // Only strikethrough if paid AND fully reconciled (no pending transactions)
                        .strikethrough(bill.isPaid && !hasPendingTransaction)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if bill.autoPay {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    // Show PENDING badge if bill has pending transactions
                    if hasPendingTransaction {
                        Text("PENDING")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if bill.isPaid {
                        // Only show PAID if fully reconciled (no pending transactions)
                        Text("PAID")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                
                HStack(spacing: 6) {
                    if let dueDate = bill.dueDate {
                        Text(dateFormatter.string(from: dueDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !bill.isPaid {
                            if daysUntilDue < 0 {
                                Text("• \(abs(daysUntilDue))d overdue")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            } else if daysUntilDue <= 3 {
                                Text("• \(daysUntilDue)d left")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    if bill.recurrenceType != "none", let recurrenceType = bill.recurrenceType {
                        Text("• \(formatRecurrenceType(recurrenceType, interval: Int(bill.recurrenceInterval)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Amount with smooth animation
            Group {
                if bitcoinPriceService.showInBitcoin, let amount = bill.amount?.decimalValue {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(bitcoinPriceService.formatAsSats(amount))
                            .font(.headline)
                            .foregroundColor(bill.isPaid ? .green : .orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("$\(amount, format: .number.precision(.fractionLength(2)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                } else {
                    Text("$\(bill.amount?.stringValue ?? "0")")
                        .font(.headline)
                        .foregroundColor(bill.isPaid ? .green : .primary)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
            
            // Removed arrow button - keeping it simple: just check off the bill
        }
        .padding(.vertical, 4)
        
            // Reconcile drawer for BTC accounts (with or without pending transactions)
            if showingReconcileDrawer && isBTCAccount {
                reconcileDrawer
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity).combined(with: .move(edge: .top)),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity).combined(with: .move(edge: .top))
                    ))
            }
        }
        .onChange(of: showingReconcileDrawer) { oldValue, newValue in
            if newValue {
                // Initialize fields when drawer opens
                if let entry = pendingEntry {
                    // Has pending transaction - use entry values
                    // Try to extract bill amount and fee from notes
                    var extractedBillAmount = entry.usdAmountDecimal
                    var extractedFee: Decimal = 0
                    
                    if let notes = entry.notes,
                       let feeRange = notes.range(of: #"Strike fee:.*?\$([\d,]+\.?\d*)"#, options: .regularExpression) {
                        let feeMatch = notes[feeRange]
                        if let amountRange = feeMatch.range(of: #"([\d,]+\.?\d*)"#, options: .regularExpression) {
                            let feeString = String(feeMatch[amountRange]).replacingOccurrences(of: ",", with: "")
                            if let fee = Decimal(string: feeString) {
                                extractedFee = fee
                                extractedBillAmount = extractedBillAmount - fee
                            }
                        }
                    }
                    
                    if extractedBillAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: extractedBillAmount as NSDecimalNumber) ?? ""
                        
                        if extractedFee > 0 {
                            feeAmountString = formatter.string(from: extractedFee as NSDecimalNumber) ?? ""
                        }
                    } else if let billAmount = bill.amount?.decimalValue, billAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: billAmount as NSDecimalNumber) ?? ""
                    }
                    
                    // Initialize BTC/sats amount if available
                    if entry.btcAmountDecimal > 0 {
                        let sats = entry.btcAmountDecimal * 100_000_000
                        let satsFormatter = NumberFormatter()
                        satsFormatter.numberStyle = .decimal
                        satsFormatter.maximumFractionDigits = 0
                        satsFormatter.groupingSeparator = ","
                        btcSatsAmountString = satsFormatter.string(from: sats as NSDecimalNumber) ?? ""
                    }
                    
                    // Always default to current BTC price if no price set
                    if entry.btcPriceAtTransactionDecimal > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        btcPriceString = formatter.string(from: entry.btcPriceAtTransactionDecimal as NSDecimalNumber) ?? ""
                    } else {
                        // Pre-fill with current BTC price
                        let currentPrice = bitcoinPriceService.btcToUsdRate
                        if currentPrice > 0 {
                            let formatter = NumberFormatter()
                            formatter.numberStyle = .decimal
                            formatter.maximumFractionDigits = 2
                            btcPriceString = formatter.string(from: currentPrice as NSDecimalNumber) ?? ""
                        }
                    }
                } else {
                    // No pending transaction - use bill amount and current BTC price
                    if let billAmount = bill.amount?.decimalValue, billAmount > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        billAmountString = formatter.string(from: billAmount as NSDecimalNumber) ?? ""
                    }
                    
                    // Pre-fill with current BTC price
                    let currentPrice = bitcoinPriceService.btcToUsdRate
                    if currentPrice > 0 {
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .decimal
                        formatter.maximumFractionDigits = 2
                        btcPriceString = formatter.string(from: currentPrice as NSDecimalNumber) ?? ""
                    }
                }
                // Auto-focus bill amount field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .billAmount
                }
            }
        }
    }
    
    private var statusColor: Color {
        if bill.isPaid {
            return .green
        } else if isOverdue {
            return .red
        } else if daysUntilDue <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    private func formatRecurrenceType(_ type: String, interval: Int) -> String {
        switch type {
        case "none":
            return ""
        case "daily":
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case "weekly":
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case "biweekly":
            return "Bi-weekly"
        case "monthly":
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        case "bimonthly":
            return "Bi-monthly"
        case "quarterly":
            return interval == 1 ? "Quarterly" : "Every \(interval) quarters"
        case "semiannually":
            return "Semi-annually"
        case "yearly":
            return interval == 1 ? "Yearly" : "Every \(interval) years"
        default:
            return type.capitalized
        }
    }
    
    @ViewBuilder
    private var reconcileDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)
            
            Text("Enter Transaction Details")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bill Amount (USD)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $billAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .billAmount)
                        .onChange(of: billAmountString) { oldValue, newValue in
                            // Auto-calculate total and BTC/sats if price is available
                            updateCalculations()
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fee Amount (USD) - Optional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $feeAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .feeAmount)
                        .onChange(of: feeAmountString) { oldValue, newValue in
                            // Auto-calculate total and BTC/sats if price is available
                            updateCalculations()
                        }
                    
                    // Show total calculation
                    if !billAmountString.isEmpty,
                       let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                       billAmount > 0 {
                        let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                        let totalAmount = billAmount + feeAmount
                        if let totalString = formatUSD(totalAmount) {
                            HStack {
                                Text("Total:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(totalString)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("BTC/Sats Amount (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter BTC or sats", text: $btcSatsAmountString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .btcSatsAmount)
                        .onChange(of: btcSatsAmountString) { oldValue, newValue in
                            updateCalculations()
                        }
                    
                    // BTC Price - show below BTC/sats field
                    HStack {
                        Text("BTC Price:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Check if we can auto-calculate price (have bill amount, fee, and sats)
                        let canAutoCalculatePrice: Bool = {
                            guard !billAmountString.isEmpty,
                                  let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                                  billAmount >= 0,
                                  !btcSatsAmountString.isEmpty,
                                  let btcSatsValue = Decimal(string: btcSatsAmountString.replacingOccurrences(of: ",", with: "")),
                                  btcSatsValue > 0 else {
                                return false
                            }
                            let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let totalAmount = billAmount + feeAmount
                            return totalAmount > 0
                        }()
                        
                        if canAutoCalculatePrice {
                            // Auto-calculated price - show as read-only
                            let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                            let totalAmount = billAmount + feeAmount
                            let btcSatsValue = Decimal(string: btcSatsAmountString.replacingOccurrences(of: ",", with: "")) ?? 0
                            let btcAmount = detectAndConvertToBTC(btcSatsValue)
                            let calculatedPrice = btcAmount > 0 ? totalAmount / btcAmount : 0
                            
                            HStack {
                                Spacer()
                                if let priceString = formatUSD(calculatedPrice) {
                                    Text(priceString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("")
                                }
                            }
                            .onAppear {
                                updateCalculations()
                            }
                            .onChange(of: billAmountString) { _, _ in
                                updateCalculations()
                            }
                            .onChange(of: feeAmountString) { _, _ in
                                updateCalculations()
                            }
                            .onChange(of: btcSatsAmountString) { _, _ in
                                updateCalculations()
                            }
                        } else {
                            // Manual price entry - editable
                            TextField("0.00", text: $btcPriceString)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .btcPrice)
                                .frame(maxWidth: 120)
                                .onChange(of: btcPriceString) { oldValue, newValue in
                                    // Only calculate sats if we have USD but not sats
                                    if !newValue.isEmpty && !billAmountString.isEmpty && btcSatsAmountString.isEmpty,
                                       let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                                       let btcPrice = Decimal(string: newValue.replacingOccurrences(of: ",", with: "")),
                                       btcPrice > 0 {
                                        let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                                        let totalAmount = billAmount + feeAmount
                                        let btcAmount = totalAmount / btcPrice
                                        let sats = btcAmount * 100_000_000
                                        let formatter = NumberFormatter()
                                        formatter.numberStyle = .decimal
                                        formatter.maximumFractionDigits = 0
                                        formatter.groupingSeparator = ","
                                        btcSatsAmountString = formatter.string(from: sats as NSDecimalNumber) ?? ""
                                    }
                                }
                        }
                    }
                }
                
                // Show calculated BTC amount when total USD and price are entered
                if !billAmountString.isEmpty && !btcPriceString.isEmpty,
                   let billAmount = Decimal(string: billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")),
                   let btcPrice = Decimal(string: btcPriceString.replacingOccurrences(of: ",", with: "")),
                   btcPrice > 0 {
                    let feeAmount = Decimal(string: feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
                    let totalAmount = billAmount + feeAmount
                    let btcAmount = totalAmount / btcPrice
                    let sats = btcAmount * 100_000_000
                    
                    HStack {
                        Text("Total BTC Amount:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatSats(sats))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingReconcileDrawer = false
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveReconcile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(billAmountString.isEmpty || (billAmountString != "0" && billAmountString != "0.00" && btcSatsAmountString.isEmpty && btcPriceString.isEmpty))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.top, 8)
    }
    
    // Helper function to update calculations when amounts change
    private func updateCalculations() {
        let cleanedBill = billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedFee = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedBTCSats = btcSatsAmountString.replacingOccurrences(of: ",", with: "")
        let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "")
        
        guard let billAmount = Decimal(string: cleanedBill), billAmount >= 0 else { return }
        let feeAmount = Decimal(string: cleanedFee) ?? 0
        let totalAmount = billAmount + feeAmount
        
        // If we have bill amount, fee, and sats, calculate BTC price
        if !cleanedBTCSats.isEmpty,
           let btcSatsValue = Decimal(string: cleanedBTCSats),
           btcSatsValue > 0,
           totalAmount > 0 {
            let btcAmount = detectAndConvertToBTC(btcSatsValue)
            if btcAmount > 0 {
                let calculatedPrice = totalAmount / btcAmount
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 2
                btcPriceString = formatter.string(from: calculatedPrice as NSDecimalNumber) ?? ""
            }
        }
        // Otherwise, if we have price and USD, calculate sats (only if sats field is empty)
        else if !cleanedPrice.isEmpty,
                let btcPrice = Decimal(string: cleanedPrice),
                btcPrice > 0,
                totalAmount > 0,
                btcSatsAmountString.isEmpty {
            let btcAmount = totalAmount / btcPrice
            let sats = btcAmount * 100_000_000
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            btcSatsAmountString = formatter.string(from: sats as NSDecimalNumber) ?? ""
        }
    }
    
    private func saveReconcile() {
        let cleanedBill = billAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedFee = feeAmountString.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        let cleanedBTCSats = btcSatsAmountString.replacingOccurrences(of: ",", with: "")
        let cleanedPrice = btcPriceString.replacingOccurrences(of: ",", with: "")
        
        // Allow zero amounts (for $0 bills)
        guard let billAmount = Decimal(string: cleanedBill), billAmount >= 0 else {
            return
        }
        
        let feeAmount = Decimal(string: cleanedFee) ?? 0
        let totalAmount = billAmount + feeAmount
        
        var btcAmount: Decimal = 0
        var btcPrice: Decimal = 0
        
        // Determine BTC amount and price from available inputs
        if !cleanedBTCSats.isEmpty, let btcSatsValue = Decimal(string: cleanedBTCSats), btcSatsValue > 0 {
            // BTC/sats amount provided
            btcAmount = detectAndConvertToBTC(btcSatsValue)
            
            if !cleanedPrice.isEmpty, let priceValue = Decimal(string: cleanedPrice), priceValue > 0 {
                // BTC price provided
                btcPrice = priceValue
            } else if totalAmount > 0 && btcAmount > 0 {
                // Calculate BTC price from total USD and BTC amounts
                btcPrice = totalAmount / btcAmount
            } else {
                // Use current BTC price as fallback
                btcPrice = bitcoinPriceService.btcToUsdRate
            }
        } else if !cleanedPrice.isEmpty, let priceValue = Decimal(string: cleanedPrice), priceValue > 0 {
            // Only USD and price provided - calculate BTC amount
            btcPrice = priceValue
            btcAmount = totalAmount / btcPrice
        } else if totalAmount > 0 {
            // Only USD provided - use current price as fallback
            btcPrice = bitcoinPriceService.btcToUsdRate
            btcAmount = totalAmount / btcPrice
        }
        
        // Build notes with fee breakdown (matching Strike format)
        var transactionNotes = bill.notes ?? ""
        if feeAmount > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            if let feeString = formatter.string(from: feeAmount as NSDecimalNumber) {
                if transactionNotes.isEmpty {
                    transactionNotes = "Strike fee: \(feeString)"
                } else {
                    transactionNotes = "\(transactionNotes)\nStrike fee: \(feeString)"
                }
            }
        }
        
        // Check if we have a pending transaction to reconcile
        if let entry = pendingEntry {
            // Reconcile existing pending transaction
            // For zero amounts, just mark as reconciled
            if totalAmount == 0 {
                entry.isReconciledFlag = true
                entry.usdAmount = NSDecimalNumber(decimal: .zero)
                entry.btcAmount = NSDecimalNumber(decimal: .zero)
                entry.amount = NSDecimalNumber(decimal: .zero)
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: .zero)
                entry.notes = transactionNotes.isEmpty ? nil : transactionNotes
                accountViewModel.saveContext()
                accountViewModel.refreshLedgerEntries()
                
                // Mark bill as paid directly (don't call togglePaidStatus to avoid creating duplicate entry)
                if !bill.isPaid {
                    bill.isPaid = true
                    bill.paidDate = Date()
                    accountViewModel.saveContext()
                    billViewModel.updateAppBadge()
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingReconcileDrawer = false
                }
                HapticManager.shared.billMarkedPaid()
                return
            }
            
            // Update entry with reconciled values (total amount includes fee)
            entry.usdAmount = NSDecimalNumber(decimal: totalAmount)
            entry.btcAmount = NSDecimalNumber(decimal: btcAmount)
            entry.amount = NSDecimalNumber(decimal: btcAmount)
            entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
            entry.notes = transactionNotes.isEmpty ? nil : transactionNotes
            entry.isReconciledFlag = true // Mark as fully reconciled
            
            accountViewModel.saveContext()
            accountViewModel.refreshLedgerEntries()
            
            // Mark bill as paid directly (don't call togglePaidStatus to avoid creating duplicate entry)
            if !bill.isPaid {
                bill.isPaid = true
                bill.paidDate = Date()
                accountViewModel.saveContext()
                billViewModel.updateAppBadge()
            }
        } else {
            // No pending transaction - create new ledger entry with BTC/sats value
            // For zero amounts, just mark bill as paid without creating entry
            if totalAmount == 0 {
                if !bill.isPaid {
                    bill.isPaid = true
                    bill.paidDate = Date()
                    accountViewModel.saveContext()
                    billViewModel.updateAppBadge()
                }
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingReconcileDrawer = false
                }
                HapticManager.shared.billMarkedPaid()
                return
            }
            
            // Create new ledger entry directly and mark as reconciled immediately
            let satsAmount = btcAmount * 100_000_000
            
            // Mark bill as paid first
            if !bill.isPaid {
                bill.isPaid = true
                bill.paidDate = Date()
            }
            
            // Create the ledger entry with total amount (bill + fee) and mark it as reconciled
            if let entry = accountViewModel.recordLedgerEntry(for: bill,
                                                              amount: totalAmount, // Store total (bill + fee)
                                                              date: bill.paidDate ?? Date(),
                                                              isCredit: false,
                                                              title: bill.name,
                                                              notes: transactionNotes,
                                                              satsAmount: satsAmount) {
                // Set BTC price and mark as reconciled
                entry.btcPriceAtTransaction = NSDecimalNumber(decimal: btcPrice)
                entry.isReconciledFlag = true
                accountViewModel.saveContext()
                accountViewModel.refreshLedgerEntries()
            }
            
            billViewModel.updateAppBadge()
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingReconcileDrawer = false
        }
        HapticManager.shared.billMarkedPaid()
    }
    
    // Helper function to detect if input is BTC or sats and convert to BTC
    private func detectAndConvertToBTC(_ value: Decimal) -> Decimal {
        // If value is >= 1, assume it's sats (convert to BTC)
        // If value is < 1, assume it's BTC
        if value >= 1 {
            return value / 100_000_000
        } else {
            return value
        }
    }
    
    private func formatSats(_ sats: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        
        if sats >= 1_000_000 {
            return "\(formatter.string(from: sats as NSDecimalNumber) ?? "") sats"
        } else {
            return "\(formatter.string(from: sats as NSDecimalNumber) ?? "") sats"
        }
    }
    
    private func formatUSD(_ value: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber)
    }
}

#Preview {
    let controller = PersistenceController.preview
    let notif = NotificationManager()
    let accountVM = AccountViewModel(context: controller.container.viewContext)
    let billVM = BillViewModel(context: controller.container.viewContext,
                               notificationManager: notif,
                               accountViewModel: accountVM)
    BillListView()
        .environmentObject(billVM)
        .environmentObject(accountVM)
        .environmentObject(notif)
}

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

