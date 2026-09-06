//
//  MoneyFormatting.swift
//  BillsAndBalance
//
//  Parse and format money input for USD, sats, BTC, and percentages.
//

import Foundation
import UIKit

enum MoneyKind: Equatable {
    case usd
    case sats
    case bitcoin
    case percent

    var prefix: String? {
        switch self {
        case .usd: return "$"
        case .sats, .bitcoin: return "₿"
        case .percent: return nil
        }
    }

    var placeholder: String {
        switch self {
        case .usd: return "0.00"
        case .sats: return "0"
        case .bitcoin: return "0.00000000"
        case .percent: return "0.000"
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .sats: return .numberPad
        case .usd, .bitcoin, .percent: return .decimalPad
        }
    }
}

enum MoneyFormatting {
    static func parse(_ text: String, kind: MoneyKind = .usd) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch kind {
        case .sats:
            let cleaned = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            guard !cleaned.isEmpty else { return nil }
            return Decimal(string: cleaned)
        case .usd, .bitcoin, .percent:
            var cleaned = trimmed.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            let parts = cleaned.components(separatedBy: ".")
            if parts.count > 2 {
                cleaned = parts[0] + "." + parts.dropFirst().joined()
            }
            guard !cleaned.isEmpty, cleaned != "." else { return nil }
            return Decimal(string: cleaned)
        }
    }

    static func format(_ value: Decimal, kind: MoneyKind, includeSymbol: Bool = false) -> String {
        switch kind {
        case .usd:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            let body = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
            return includeSymbol ? "$\(body)" : body
        case .sats:
            let satsInt = (value as NSDecimalNumber).intValue
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: satsInt)) ?? "\(satsInt)"
        case .bitcoin:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.usesGroupingSeparator = true
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
            return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        case .percent:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 3
            return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        }
    }

    static func formatForDisplay(_ text: String, kind: MoneyKind) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        guard let value = parse(text, kind: kind) else { return text }
        return format(value, kind: kind)
    }

    static func currencyString(_ amount: Decimal) -> String {
        format(amount, kind: .usd, includeSymbol: true)
    }

    static func btc(fromSats sats: Decimal) -> Decimal {
        sats / 100_000_000
    }

    static func sats(fromBTC btc: Decimal) -> Decimal {
        btc * 100_000_000
    }

    /// Interprets a sats or BTC text field as a BTC amount.
    static func btcAmount(fromInput text: String, displayFormat: String) -> Decimal? {
        if displayFormat == "sats" {
            guard let sats = parse(text, kind: .sats), sats > 0 else { return nil }
            return btc(fromSats: sats)
        }
        guard let btc = parse(text, kind: .bitcoin), btc > 0 else { return nil }
        return btc
    }

    static func displayString(forBTC btc: Decimal, displayFormat: String) -> String {
        if displayFormat == "sats" {
            return format(sats(fromBTC: btc), kind: .sats)
        }
        return format(btc, kind: .bitcoin)
    }

    static func kindForBTCDisplay(_ displayFormat: String) -> MoneyKind {
        displayFormat == "sats" ? .sats : .bitcoin
    }
}
