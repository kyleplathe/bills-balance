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

    private var refreshTask: Task<Void, Never>?
    private let cacheRateKey = "btcToUsdRate"
    private let cacheDateKey = "btcToUsdRateDate"
    private let refreshInterval: TimeInterval = 180

    private init() {
        loadCachedRate()
        fetchBitcoinPrice()
        startPeriodicUpdates()
    }

    private func loadCachedRate() {
        let stored = UserDefaults.standard.double(forKey: cacheRateKey)
        if stored > 0 {
            btcToUsdRate = Decimal(stored)
            lastUpdateTime = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
        }
    }

    private func cacheRate(_ rate: Decimal) {
        UserDefaults.standard.set((rate as NSDecimalNumber).doubleValue, forKey: cacheRateKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
    }

    private func startPeriodicUpdates() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.refreshInterval ?? 180) * 1_000_000_000))
                await self?.refreshPrice()
            }
        }
    }

    func fetchBitcoinPrice() {
        Task { await refreshPrice() }
    }

    func refreshPrice() async {
        let alreadyLoading = await MainActor.run { isLoading }
        guard !alreadyLoading else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let rate = try await CoinGeckoClient.fetchBitcoinUSDPrice()
            await MainActor.run {
                btcToUsdRate = rate
                lastUpdateTime = Date()
                errorMessage = nil
                isLoading = false
                cacheRate(rate)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
            #if DEBUG
            print("Bitcoin price fetch error: \(error)")
            #endif
        }
    }

    func convertBTCToUSD(_ btcAmount: Decimal) -> Decimal {
        return btcAmount * btcToUsdRate
    }

    func convertUSDtoBTC(_ usdAmount: Decimal) -> Decimal {
        guard btcToUsdRate > 0 else { return 0 }
        return usdAmount / btcToUsdRate
    }

    func formatAsSats(_ usdAmount: Decimal) -> String {
        guard btcToUsdRate > 0 else { return "…" }
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

    // MARK: - Historical daily prices

    private static let historicalCacheKey = "btcHistoricalDailyPrices"
    private static let historicalFetchedKey = "btcHistoricalDailyPricesFetchedAt"

    private var historicalDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private func loadHistoricalCache() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: Self.historicalCacheKey) as? [String: Double] ?? [:]
    }

    private func saveHistoricalCache(_ prices: [String: Double]) {
        UserDefaults.standard.set(prices, forKey: Self.historicalCacheKey)
        UserDefaults.standard.set(Date(), forKey: Self.historicalFetchedKey)
    }

    /// USD price on `date`'s UTC day, or the nearest earlier cached day.
    func historicalUSDPrice(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Decimal? {
        var utcCal = calendar
        utcCal.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let day = utcCal.startOfDay(for: date)
        let cache = loadHistoricalCache()
        let formatter = historicalDayFormatter
        let key = formatter.string(from: day)
        if let value = cache[key], value > 0 {
            return Decimal(value)
        }
        let sorted = cache.keys.compactMap { formatter.date(from: $0) }.sorted()
        if let prior = sorted.last(where: { $0 <= day }),
           let value = cache[formatter.string(from: prior)], value > 0 {
            return Decimal(value)
        }
        return nil
    }

    func ensureHistoricalPrices(from start: Date, to end: Date = Date()) async {
        let cache = loadHistoricalCache()
        let formatter = historicalDayFormatter
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDay = utcCal.startOfDay(for: start)
        let endDay = utcCal.startOfDay(for: end)
        var missing = false
        var cursor = startDay
        while cursor <= endDay {
            if cache[formatter.string(from: cursor)] == nil {
                missing = true
                break
            }
            guard let next = utcCal.date(byAdding: .day, value: 30, to: cursor) else { break }
            cursor = next
        }
        let lastFetch = UserDefaults.standard.object(forKey: Self.historicalFetchedKey) as? Date
        let cacheStale = lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 86_400
        guard missing || cache.isEmpty || cacheStale else { return }

        let days = max(utcCal.dateComponents([.day], from: startDay, to: endDay).day ?? 1461, 30)
        do {
            let fetched = try await CoinGeckoClient.fetchBitcoinMarketChart(days: min(days + 2, 1461))
            var merged = cache
            for (day, price) in fetched {
                merged[formatter.string(from: day)] = (price as NSDecimalNumber).doubleValue
            }
            saveHistoricalCache(merged)
        } catch {
            #if DEBUG
            print("Bitcoin historical price fetch error: \(error)")
            #endif
        }
    }
}

enum CoinGeckoClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case httpStatus(Int)
        case missingPrice
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid CoinGecko URL"
            case .httpStatus(let code):
                return "CoinGecko HTTP \(code)"
            case .missingPrice:
                return "CoinGecko response was missing a Bitcoin price"
            case .rateLimited:
                return "CoinGecko rate limited the request"
            }
        }
    }

    static func fetchBitcoinUSDPrice() async throws -> Decimal {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd") else {
            throw ClientError.invalidURL
        }

        var lastError: Error = ClientError.missingPrice
        for attempt in 0..<3 {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt)) * 400_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("BillsAndBalance/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        lastError = ClientError.rateLimited
                        continue
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ClientError.httpStatus(http.statusCode)
                    }
                }
                return try CoinGeckoPriceParser.parseUSD(from: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func fetchBitcoinMarketChart(days: Int) async throws -> [(Date, Decimal)] {
        let clamped = max(1, days)
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=usd&days=\(clamped)&interval=daily") else {
            throw ClientError.invalidURL
        }

        var lastError: Error = ClientError.missingPrice
        for attempt in 0..<3 {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt)) * 400_000_000)
                try await Task.sleep(nanoseconds: delay)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("BillsAndBalance/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        lastError = ClientError.rateLimited
                        continue
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ClientError.httpStatus(http.statusCode)
                    }
                }
                return try CoinGeckoMarketChartParser.parse(from: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

enum CoinGeckoPriceParser {
    static func parseUSD(from data: Data) throws -> Decimal {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoinGeckoClient.ClientError.missingPrice
        }

        if let status = json["status"] as? [String: Any] {
            if let code = status["error_code"] as? Int, code != 0 {
                if code == 429 {
                    throw CoinGeckoClient.ClientError.rateLimited
                }
                throw CoinGeckoClient.ClientError.httpStatus(code)
            }
        }

        let bitcoin = json["bitcoin"] as? [String: Any]
        let raw = bitcoin?["usd"]
        let value: Double?
        switch raw {
        case let number as NSNumber:
            value = number.doubleValue
        case let number as Double:
            value = number
        case let number as Int:
            value = Double(number)
        case let string as String:
            value = Double(string)
        default:
            value = nil
        }

        guard let value, value > 0 else {
            throw CoinGeckoClient.ClientError.missingPrice
        }
        return Decimal(value)
    }
}

enum CoinGeckoMarketChartParser {
    static func parse(from data: Data) throws -> [(Date, Decimal)] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoinGeckoClient.ClientError.missingPrice
        }
        if let status = json["status"] as? [String: Any],
           let code = status["error_code"] as? Int, code != 0 {
            if code == 429 { throw CoinGeckoClient.ClientError.rateLimited }
            throw CoinGeckoClient.ClientError.httpStatus(code)
        }
        guard let prices = json["prices"] as? [[Any]] else {
            throw CoinGeckoClient.ClientError.missingPrice
        }
        var result: [(Date, Decimal)] = []
        for row in prices {
            guard row.count >= 2 else { continue }
            let ms: Double
            if let n = row[0] as? NSNumber {
                ms = n.doubleValue
            } else if let n = row[0] as? Double {
                ms = n
            } else {
                continue
            }
            let value: Double?
            switch row[1] {
            case let n as NSNumber:
                value = n.doubleValue
            case let n as Double:
                value = n
            case let n as Int:
                value = Double(n)
            default:
                value = nil
            }
            guard let value, value > 0 else { continue }
            result.append((Date(timeIntervalSince1970: ms / 1000), Decimal(value)))
        }
        guard !result.isEmpty else { throw CoinGeckoClient.ClientError.missingPrice }
        return result
    }
}
