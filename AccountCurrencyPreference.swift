//
//  AccountCurrencyPreference.swift
//  BillsAndBalance
//
//  Remembers whether an account detail screen was left showing sats/BTC
//  so Balance chips can match that primary unit.
//

import Foundation

enum AccountCurrencyPreference {
    private static func key(for accountID: UUID) -> String {
        "accountCurrencyBTC.\(accountID.uuidString)"
    }

    /// `true` when the account page last showed sats/BTC as the main amount.
    static func prefersBitcoin(for accountID: UUID?) -> Bool {
        guard let accountID else { return false }
        return UserDefaults.standard.bool(forKey: key(for: accountID))
    }

    static func setPrefersBitcoin(_ value: Bool, for accountID: UUID?) {
        guard let accountID else { return }
        UserDefaults.standard.set(value, forKey: key(for: accountID))
    }
}
