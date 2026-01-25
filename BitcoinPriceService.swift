//
//  BitcoinPriceService.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import Foundation
import Combine

class BitcoinPriceService: ObservableObject {
    static let shared = BitcoinPriceService()
    
    @Published var btcToUsdRate: Decimal = 0
    @Published var lastUpdateTime: Date?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showInBitcoin: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 60 // Update every minute
    
    private init() {
        fetchBitcoinPrice()
        startPeriodicUpdates()
    }
    
    private func startPeriodicUpdates() {
        Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchBitcoinPrice()
            }
            .store(in: &cancellables)
    }
    
    func fetchBitcoinPrice() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Using CoinGecko API (free, no API key required)
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd") else {
            isLoading = false
            errorMessage = "Invalid API URL"
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: CoinGeckoResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                        print("Bitcoin price fetch error: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    if let rate = response.bitcoin.usd {
                        self?.btcToUsdRate = Decimal(rate)
                        self?.lastUpdateTime = Date()
                        self?.errorMessage = nil
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func convertBTCToUSD(_ btcAmount: Decimal) -> Decimal {
        return btcAmount * btcToUsdRate
    }
    
    func convertUSDtoBTC(_ usdAmount: Decimal) -> Decimal {
        guard btcToUsdRate > 0 else { return 0 }
        return usdAmount / btcToUsdRate
    }
    
    func formatAsSats(_ usdAmount: Decimal) -> String {
        let btcAmount = convertUSDtoBTC(usdAmount)
        if btcAmount >= 1 {
            let doubleValue = (btcAmount as NSDecimalNumber).doubleValue
            return String(format: "%.8f BTC", doubleValue)
        } else {
            let sats = btcAmount * 100_000_000
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
    
    func formatAsSatsWithUSD(_ usdAmount: Decimal) -> (sats: String, usd: String) {
        let satsString = formatAsSats(usdAmount)
        let usdString = String(format: "$%.2f", (usdAmount as NSDecimalNumber).doubleValue)
        return (satsString, usdString)
    }
}

// MARK: - API Response Models
private struct CoinGeckoResponse: Codable {
    let bitcoin: BitcoinPrice
    
    enum CodingKeys: String, CodingKey {
        case bitcoin = "bitcoin"
    }
}

private struct BitcoinPrice: Codable {
    let usd: Double?
}

