//
//  BitcoinView.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import SwiftUI

private func formatSats(_ sats: Decimal) -> String {
    let satsDouble = (sats as NSDecimalNumber).doubleValue
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: satsDouble)) ?? String(format: "%.0f", satsDouble)
}

struct BitcoinView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var coinAnimations: [CoinAnimation] = []
    @State private var animationTimer: Timer?
    @State private var coinGeometrySize: CGSize = UIScreen.main.bounds.size
    
    var onClose: (() -> Void)?
    
    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }
    
    struct CoinAnimation: Identifiable {
        let id = UUID()
        var position: CGPoint
        var rotation: Double = 0
        var opacity: Double = 1.0
    }
    
    private var currencyCode: String {
        "BTC"
    }
    
    private func convertToBTC(_ amount: Decimal) -> Decimal {
        bitcoinPriceService.convertUSDtoBTC(amount)
    }
    
    private func formatBTC(_ amount: Decimal) -> String {
        if amount >= 1 {
            let doubleValue = (amount as NSDecimalNumber).doubleValue
            return String(format: "%.8f BTC", doubleValue)
        } else {
            let sats = amount * 100_000_000
            let satsDouble = (sats as NSDecimalNumber).doubleValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 0
            let formattedSats = formatter.string(from: NSNumber(value: satsDouble)) ?? String(format: "%.0f", satsDouble)
            return "\(formattedSats) sats"
        }
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Orange theme background
                    Color.orange.opacity(0.1)
                        .ignoresSafeArea()
                    
                    // Falling BTC coins animation
                    ForEach(coinAnimations) { coin in
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 55))
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(coin.rotation))
                            .opacity(coin.opacity)
                            .position(coin.position)
                    }
                    
                    ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Bitcoin View")
                            .font(.title.bold())
                        Text("All amounts shown in BTC/Sats")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Bills Section
                    if !billViewModel.bills.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Bills in Bitcoin")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(billViewModel.bills) { bill in
                                if let amount = bill.amount?.decimalValue {
                                    let btcAmount = convertToBTC(amount)
                                    BillRowBTC(bill: bill, btcAmount: btcAmount)
                                }
                            }
                        }
                    }
                    
                    // Bitcoin Accounts Section (Digital Wallets)
                    let bitcoinAccounts = accountViewModel.accounts.filter { 
                        !$0.isHiddenFlag && $0.currencyCode == "BTC" 
                    }
                    if !bitcoinAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Bitcoin Accounts")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(bitcoinAccounts) { account in
                                let balance = accountViewModel.totalBalance(for: account)
                                AccountRowBTC(account: account, btcAmount: balance, isBitcoinAccount: true)
                            }
                        }
                    }
                    
                    // Converted Accounts Section (USD accounts shown in BTC)
                    let convertedAccounts = accountViewModel.accounts.filter { 
                        !$0.isHiddenFlag && $0.currencyCode != "BTC" 
                    }
                    if !convertedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Accounts (Converted to Bitcoin)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            ForEach(convertedAccounts) { account in
                                let balance = accountViewModel.totalBalance(for: account)
                                let btcAmount = convertToBTC(balance)
                                AccountRowBTC(account: account, btcAmount: btcAmount, isBitcoinAccount: false)
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20)
                }
                }
                .onAppear {
                    // Store geometry size for coin positioning
                    coinGeometrySize = geometry.size
                    startCoinAnimation()
                }
                .onDisappear {
                    stopCoinAnimation()
                }
            }
            .navigationTitle("Bitcoin View")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
        }
    }
    
    private func startCoinAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            addCoin()
        }
        // Add initial coins with staggered delays for better distribution
        for i in 0..<3 {
            let delay = Double(i) * 0.3 // Stagger by 0.3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                addCoin()
            }
        }
    }
    
    private func stopCoinAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func addCoin() {
        // Use geometry size for better width distribution
        let screenWidth = coinGeometrySize.width
        let screenHeight = coinGeometrySize.height
        let coinSize: CGFloat = 55 // Approximate coin size
        
        // Spread coins across the ENTIRE width with minimal padding (just enough to keep coin visible)
        // Use the full width range for maximum coverage
        let minX = coinSize / 2 + 5 // Small padding to keep coin fully visible
        let maxX = screenWidth - (coinSize / 2) - 5 // Small padding on right
        
        // Better distribution: divide screen into segments and randomly pick from different segments
        // This ensures coins don't cluster in one area
        let segmentWidth = (maxX - minX) / 3.0
        let segment = Int.random(in: 0..<3)
        let segmentMinX = minX + (CGFloat(segment) * segmentWidth)
        let segmentMaxX = minX + (CGFloat(segment + 1) * segmentWidth)
        let xPosition = CGFloat.random(in: segmentMinX...segmentMaxX)
        
        let coin = CoinAnimation(
            position: CGPoint(
                x: xPosition,
                y: -30
            )
        )
        let coinId = coin.id
        coinAnimations.append(coin)
        
        // Random rotation amount for more natural falling
        let rotationAmount = Double.random(in: 360...1080)
        let fallDuration = Double.random(in: 2.5...4.0)
        
        // Animate coin falling - use a small delay to ensure SwiftUI has processed the append
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

private struct BillRowBTC: View {
    let bill: Bill
    let btcAmount: Decimal
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name ?? "Bill")
                    .font(.headline)
                if let dueDate = bill.dueDate {
                    Text(dueDate, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if btcAmount >= 1 {
                    Text(String(format: "%.8f BTC", (btcAmount as NSDecimalNumber).doubleValue))
                        .font(.headline)
                } else {
                    let sats = btcAmount * 100_000_000
                    Text("\(formatSats(sats)) sats")
                        .font(.headline)
                }
                if let usdAmount = bill.amount?.decimalValue {
                    Text("≈ $\(usdAmount, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private struct AccountRowBTC: View {
    @EnvironmentObject private var accountViewModel: AccountViewModel
    let account: Account
    let btcAmount: Decimal
    let isBitcoinAccount: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.name ?? "Account")
                        .font(.headline)
                    if isBitcoinAccount {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Text(account.type?.capitalized ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if btcAmount >= 1 {
                    Text(String(format: "%.8f BTC", (btcAmount as NSDecimalNumber).doubleValue))
                        .font(.headline)
                } else {
                    let sats = btcAmount * 100_000_000
                    Text("\(formatSats(sats)) sats")
                        .font(.headline)
                }
                if !isBitcoinAccount {
                    let usdBalance = accountViewModel.totalBalance(for: account)
                    Text("≈ $\(usdBalance, format: .number.precision(.fractionLength(2)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(isBitcoinAccount ? Color.orange.opacity(0.1) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isBitcoinAccount ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct BitcoinPriceDisplay: View {
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    
    private var formattedPrice: String {
        let price = bitcoinPriceService.btcToUsdRate
        guard price > 0 else { return "Loading..." }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        
        return formatter.string(from: price as NSDecimalNumber) ?? "$0.00"
    }
    
    private var lastUpdateText: String {
        guard let lastUpdate = bitcoinPriceService.lastUpdateTime else {
            return "Never updated"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: lastUpdate, relativeTo: Date()))"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("BTC/USD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if bitcoinPriceService.isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .font(.headline)
                        }
                    } else {
                        Text(formattedPrice)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
                
                if bitcoinPriceService.btcToUsdRate > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("1 BTC")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("=")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if bitcoinPriceService.btcToUsdRate > 0 {
                Text(lastUpdateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

