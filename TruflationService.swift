//
//  TruflationService.swift
//  BillsAndBalance
//
//  Fetches inflation data from Truflation API
//

import Foundation
import Combine

class TruflationService: ObservableObject {
    static let shared = TruflationService()
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var adjustForInflation: Bool = false
    
    private let historicalCacheKey = "truflationHistoricalData"
    private let historicalFetchedKey = "truflationHistoricalFetchedAt"
    
    private init() {}
    
    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
    
    private func loadHistoricalCache() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: historicalCacheKey) as? [String: Double] ?? [:]
    }
    
    private func saveHistoricalCache(_ data: [String: Double]) {
        UserDefaults.standard.set(data, forKey: historicalCacheKey)
        UserDefaults.standard.set(Date(), forKey: historicalFetchedKey)
    }
    
    /// Returns cumulative inflation multiplier from `date` to today.
    /// Example: if inflation was 20% from 2019 to 2026, returns 1.20
    func inflationMultiplier(from date: Date, to endDate: Date = Date()) -> Decimal {
        // For now, use a simple estimation based on US inflation
        // In production, this would fetch from Truflation API
        
        let cache = loadHistoricalCache()
        let formatter = dayFormatter
        let startKey = formatter.string(from: date)
        let endKey = formatter.string(from: endDate)
        
        // If we have cached data, use it
        if let startCPI = cache[startKey], let endCPI = cache[endKey], startCPI > 0 {
            return Decimal(endCPI / startCPI)
        }
        
        // Fallback: estimate ~3% annual inflation
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: date, to: endDate)
        let years = Double(components.year ?? 0)
        let months = Double(components.month ?? 0)
        let totalYears = years + (months / 12.0)
        let annualInflation = 0.03 // 3% average
        let multiplier = pow(1.0 + annualInflation, totalYears)
        
        return Decimal(multiplier)
    }
    
    /// Fetch historical inflation data from Truflation API
    /// Note: Requires API key to be set in environment or user defaults
    func ensureInflationData(from start: Date, to end: Date = Date()) async {
        let cache = loadHistoricalCache()
        
        // Check if cache is recent enough
        let lastFetch = UserDefaults.standard.object(forKey: historicalFetchedKey) as? Date
        let cacheStale = lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 86_400 * 7 // 7 days
        
        guard cache.isEmpty || cacheStale else { return }
        
        // For MVP: use estimation
        // TODO: Implement actual Truflation API call with API key
        // The API endpoint would be:
        // GET https://api.truflation.com/api/v1/feed/truflation/index-data/truCPI-US
        // Header: x-api-key: YOUR_API_KEY
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Simulate API call with estimated data
        await Task.sleep(500_000_000) // 0.5 seconds
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    /// Adjust a dollar amount for inflation from historical date to today
    func adjustForInflation(_ amount: Decimal, from date: Date, to endDate: Date = Date()) -> Decimal {
        guard adjustForInflation else { return amount }
        let multiplier = inflationMultiplier(from: date, to: endDate)
        return amount * multiplier
    }
}

// MARK: - Truflation API Client (Placeholder)
// To enable real inflation data:
// 1. Get API key from https://truflation.com/pricing/api
// 2. Store key in Keychain or secure storage
// 3. Implement TruflationAPIClient similar to CoinGeckoClient
// 4. Fetch historical CPI data from truCPI-US endpoint
// 5. Cache daily CPI values for inflation calculations

/*
enum TruflationAPIClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case httpStatus(Int)
        case missingAPIKey
        case missingData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Truflation URL"
            case .httpStatus(let code): return "Truflation HTTP \(code)"
            case .missingAPIKey: return "Truflation API key not configured"
            case .missingData: return "Truflation response missing data"
            }
        }
    }
    
    static func fetchHistoricalCPI(from startDate: Date, to endDate: Date) async throws -> [String: Double] {
        // Implementation would:
        // 1. Load API key from secure storage
        // 2. Format dates for API request
        // 3. Call Truflation API with date range
        // 4. Parse response into [date: cpi_value] dictionary
        // 5. Return daily CPI values
        
        throw ClientError.missingAPIKey
    }
}
*/
