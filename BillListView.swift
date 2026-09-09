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
    @EnvironmentObject private var notificationManager: NotificationManager
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
    @State private var completionPulseScale: Double = 1.0
    @State private var completionShimmerOffset: Double = -1.0
    @State private var completionGlowRadius: Double = 8.0
    @State private var progressBarBounce: CGFloat = 1.0
    @State private var completionFlashOpacity: Double = 0
    @State private var celebrateCompletion = false
    @State private var celebrationToken = 0
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
            : EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
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
            .overlayPreferenceValue(PaidBarAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor, celebrateCompletion {
                        PaidProgressBurst(accent: bitcoinPriceService.showInBitcoin ? .orange : Brand.mint)
                            .id(celebrationToken)
                            .frame(width: 176, height: 96)
                            .position(x: proxy[anchor].midX, y: proxy[anchor].midY)
                    }
                }
                .allowsHitTesting(false)
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
            guard accountViewModel.hasActiveBitcoinDigitalWallet else { return }
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
                    .environmentObject(notificationManager)
            }
            .alert("Delete Bill", isPresented: $showingDeleteAlert) {
                deleteBillAlertButtons
            } message: {
                deleteBillAlertMessage
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
                        ProgressView(value: Double(currentMonthPaidCount),
                                     total: Double(currentMonthBillCount))
                            .progressViewStyle(.linear)
                            .tint(isBitcoinMode ? .orange : .green)
                            .frame(width: 120)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isBitcoinMode)
                            .shadow(color: (isBitcoinMode ? Color.orange : Color.green).opacity(0.8), radius: isComplete ? max(4, completionGlowRadius * 0.28) : 4)
                            .shadow(color: (isBitcoinMode ? Color.orange : Color.green).opacity(0.6), radius: isComplete ? max(8, completionGlowRadius * 0.5) : 8)
                            .shadow(color: (isBitcoinMode ? Color.orange : Color.green).opacity(0.4), radius: isComplete ? max(12, completionGlowRadius * 0.72) : 12)
                            .overlay {
                                GeometryReader { geometry in
                                    let progress = currentMonthBillCount > 0 ? CGFloat(currentMonthPaidCount) / CGFloat(currentMonthBillCount) : 0
                                    ZStack(alignment: .leading) {
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
                                            .scaleEffect(x: isComplete ? min(completionPulseScale, 1.04) : 1.0, y: 1.0, anchor: .leading)

                                        if isComplete && progress >= 1.0 {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0),
                                                            Color.white.opacity(0.7),
                                                            Color.white.opacity(0)
                                                        ],
                                                        startPoint: UnitPoint(x: completionShimmerOffset, y: 0),
                                                        endPoint: UnitPoint(x: completionShimmerOffset + 0.28, y: 0)
                                                    )
                                                )
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                .blur(radius: 0.8)

                                            Capsule()
                                                .fill(Color.white.opacity(completionFlashOpacity))
                                                .blendMode(.plusLighter)
                                        }
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                            .scaleEffect(progressBarBounce)
                            .anchorPreference(key: PaidBarAnchorKey.self, value: .bounds) { $0 }
                            .onAppear {
                                let nowComplete = currentMonthBillCount > 0 && currentMonthPaidCount == currentMonthBillCount
                                self.isComplete = nowComplete

                                if nowComplete {
                                    startCompletionAnimation(celebrating: false)
                                } else {
                                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                        neonGlowIntensity = 1.0
                                    }
                                }

                                lastProgressState = (currentMonthPaidCount, currentMonthBillCount)
                            }
                            .onChange(of: currentMonthPaidCount) { oldValue, newValue in
                                checkProgressCompletion(oldPaid: oldValue, newPaid: newValue)
                            }
                            .onChange(of: currentMonthBillCount) { oldValue, newValue in
                                checkProgressCompletion(oldPaid: currentMonthPaidCount, newPaid: currentMonthPaidCount)
                            }

                        HStack(spacing: 4) {
                            if isComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isBitcoinMode ? Color.orange : Brand.mint)
                                    .symbolEffect(.bounce, options: .nonRepeating, value: celebrationToken)
                                Text("All paid")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isBitcoinMode ? Color.orange : Brand.mint)
                            } else {
                                Text("\(currentMonthPaidCount) of \(currentMonthBillCount) paid")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.68), value: isComplete)
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
    
    private func shouldShowBill(_ bill: Bill) -> Bool {
        !bill.isPaid
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
            monthFilteredBills = monthBills.filter { bill in
                shouldShowBill(bill) || showPaidBills
            }
        } else {
            // For current month view, show unpaid bills.
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
            
            // Include other bills if they should be shown (unpaid), or if showPaidBills is on
            let filteredOtherBills = otherBills.filter { bill in
                shouldShowBill(bill) || showPaidBills
            }
            
            // Include next month's unpaid bills
            let nextMonthVisibleBills = nextMonthBills.filter { bill in
                !bill.isPaid
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
        
        // Only celebrate if we just reached completion
        if nowComplete && !wasComplete {
            self.isComplete = true
            celebrationToken += 1
            celebrateCompletion = true
            HapticManager.shared.allBillsPaid()
            startCompletionAnimation(celebrating: true)

            let token = celebrationToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                if self.celebrationToken == token {
                    self.celebrateCompletion = false
                }
            }
        } else if !nowComplete {
            // Stop all animations when progress becomes incomplete
            if wasComplete {
                // Transitioning from complete to incomplete - stop all animations immediately
                self.isComplete = false
                self.celebrateCompletion = false
                
                // Reset all animation values immediately (without animation) to stop ongoing animations
                // This will override any ongoing animations
                completionPulseScale = 1.0
                completionShimmerOffset = -1.0
                completionGlowRadius = 8.0
                progressBarBounce = 1.0
                completionFlashOpacity = 0
                
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
    
    private func startSettledCompleteGlow() {
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            neonGlowIntensity = 1.18
            completionGlowRadius = 14.0
        }
    }

    private func startCompletionAnimation(celebrating: Bool) {
        completionShimmerOffset = -1.0

        guard celebrating else {
            startSettledCompleteGlow()
            withAnimation(.easeInOut(duration: 0.9)) {
                completionShimmerOffset = 1.35
            }
            return
        }

        progressBarBounce = 1.0
        completionFlashOpacity = 0
        completionPulseScale = 1.0

        withAnimation(.spring(response: 0.34, dampingFraction: 0.46)) {
            neonGlowIntensity = 1.7
            completionGlowRadius = 24.0
            completionPulseScale = 1.05
            progressBarBounce = 1.12
            completionFlashOpacity = 0.55
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard self.isComplete else { return }
            withAnimation(.easeOut(duration: 0.65)) {
                self.completionShimmerOffset = 1.35
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard self.isComplete else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.completionFlashOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard self.isComplete else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) {
                self.progressBarBounce = 1.0
                self.completionPulseScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            guard self.isComplete else { return }
            self.startSettledCompleteGlow()
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
        billViewModel.togglePaidStatus(for: bill)
        HapticManager.shared.billMarkedPaid()
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

private struct PaidBarAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
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

private struct PaidProgressBurst: View {
    let accent: Color

    private struct Spark: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let delay: Double
        let symbol: String
        let color: Color
        let spin: Double
    }

    private var sparks: [Spark] {
        let gold = Color(red: 1, green: 0.84, blue: 0.32)
        return [
            Spark(id: 0, angle: -88, distance: 30, size: 11, delay: 0.00, symbol: "sparkle", color: gold, spin: 28),
            Spark(id: 1, angle: -118, distance: 26, size: 8, delay: 0.03, symbol: "star.fill", color: accent, spin: -36),
            Spark(id: 2, angle: -52, distance: 24, size: 7, delay: 0.05, symbol: "sparkle", color: .white, spin: 18),
            Spark(id: 3, angle: -148, distance: 32, size: 9, delay: 0.02, symbol: "sparkle", color: Brand.mint, spin: -22),
            Spark(id: 4, angle: -28, distance: 22, size: 6, delay: 0.07, symbol: "circle.fill", color: gold.opacity(0.9), spin: 12),
            Spark(id: 5, angle: -168, distance: 28, size: 8, delay: 0.04, symbol: "star.fill", color: .white, spin: 40),
            Spark(id: 6, angle: 155, distance: 23, size: 6, delay: 0.08, symbol: "sparkle", color: accent, spin: -16),
            Spark(id: 7, angle: 198, distance: 27, size: 10, delay: 0.01, symbol: "sparkle", color: gold, spin: 32),
            Spark(id: 8, angle: -72, distance: 18, size: 5, delay: 0.06, symbol: "circle.fill", color: .white, spin: 8),
            Spark(id: 9, angle: -102, distance: 34, size: 7, delay: 0.09, symbol: "star.fill", color: Brand.mint, spin: -44),
            Spark(id: 10, angle: 12, distance: 20, size: 6, delay: 0.05, symbol: "sparkle", color: accent, spin: 24),
            Spark(id: 11, angle: -200, distance: 25, size: 8, delay: 0.03, symbol: "sparkle", color: .white, spin: -20),
            Spark(id: 12, angle: 130, distance: 21, size: 5, delay: 0.10, symbol: "circle.fill", color: gold, spin: 14),
            Spark(id: 13, angle: -40, distance: 29, size: 9, delay: 0.02, symbol: "star.fill", color: gold, spin: -30)
        ]
    }

    @State private var exploded = false

    private var confetti: [(id: Int, angle: Double, distance: CGFloat, delay: Double, rotation: Double, color: Color)] {
        [
            (0, -96, 31, 0.00, 48, accent),
            (1, -64, 27, 0.04, -56, Color(red: 1, green: 0.84, blue: 0.32)),
            (2, -132, 29, 0.02, 38, .white),
            (3, 168, 24, 0.07, -42, Brand.mint),
            (4, -20, 22, 0.06, 64, accent.opacity(0.9)),
            (5, 210, 26, 0.03, -28, Color(red: 1, green: 0.84, blue: 0.32))
        ]
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(exploded ? 0 : 0.8), lineWidth: exploded ? 0.4 : 2.4)
                .frame(width: exploded ? 70 : 6, height: exploded ? 70 : 6)
                .animation(.easeOut(duration: 0.55), value: exploded)

            Circle()
                .stroke(Color.white.opacity(exploded ? 0 : 0.55), lineWidth: exploded ? 0.3 : 1.4)
                .frame(width: exploded ? 42 : 4, height: exploded ? 42 : 4)
                .animation(.easeOut(duration: 0.4), value: exploded)

            ForEach(confetti, id: \.id) { bit in
                Capsule()
                    .fill(bit.color)
                    .frame(width: 7, height: 3)
                    .offset(
                        x: exploded ? cos(bit.angle * .pi / 180) * bit.distance : 0,
                        y: exploded ? sin(bit.angle * .pi / 180) * bit.distance : 0
                    )
                    .rotationEffect(.degrees(exploded ? bit.rotation : 0))
                    .opacity(exploded ? 0 : 1)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.7).delay(bit.delay),
                        value: exploded
                    )
            }

            ForEach(sparks) { spark in
                Image(systemName: spark.symbol)
                    .font(.system(size: spark.size, weight: .bold))
                    .foregroundStyle(spark.color)
                    .offset(
                        x: exploded ? cos(spark.angle * .pi / 180) * spark.distance : 0,
                        y: exploded ? sin(spark.angle * .pi / 180) * spark.distance : 0
                    )
                    .rotationEffect(.degrees(exploded ? spark.spin : 0))
                    .scaleEffect(exploded ? 0.12 : 0.9)
                    .opacity(exploded ? 0 : 1)
                    .animation(
                        .spring(response: 0.58, dampingFraction: 0.72).delay(spark.delay),
                        value: exploded
                    )
            }
        }
        .onAppear {
            exploded = false
            DispatchQueue.main.async {
                exploded = true
            }
        }
        .accessibilityHidden(true)
    }
}

