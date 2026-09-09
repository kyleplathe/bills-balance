import Foundation

/// Pure helpers for statement CSV import: duplicate detection, signed amounts, and destination hints.
enum StatementImportMatching {
    struct ExistingEntry {
        var date: Date
        var amount: Decimal
        var title: String
        var isCredit: Bool
        var sourceReference: String?
    }

    static func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func amountsMatch(_ a: Decimal, _ b: Decimal, tolerance: Decimal = 0.01) -> Bool {
        abs(a.magnitude - b.magnitude) <= tolerance
    }

    static func signedAmount(amount: Decimal, isCredit: Bool) -> Decimal {
        isCredit ? amount.magnitude : -amount.magnitude
    }

    /// Shift starting balance by this delta so cleared balance stays the same after inserting `netSignedInserted`.
    static func startingBalanceDelta(keepingCurrentBalance netSignedInserted: Decimal) -> Decimal {
        -netSignedInserted
    }

    /// Signed amount that should affect an account's cleared balance for keep-balance math.
    /// BTC accounts only count rows with a BTC amount — never mix USD dollars into a BTC starting balance.
    static func keepBalanceSignedAmount(
        for tx: ParsedStatementTransaction,
        bitcoinAccount: Bool,
        isCredit: Bool,
        legacyMixUSDIntoBTC: Bool = false
    ) -> Decimal? {
        if bitcoinAccount {
            if let btc = tx.btcAmount, btc > 0 {
                return signedAmount(amount: btc, isCredit: isCredit)
            }
            if legacyMixUSDIntoBTC, tx.amount > 0 {
                // Old buggy path: treat USD as if it were BTC. Only for undoing a bad import.
                return signedAmount(amount: tx.amount, isCredit: isCredit)
            }
            return nil
        }
        return signedAmount(amount: tx.amount, isCredit: isCredit)
    }

    static func keepBalanceNetSigned(
        transactions: [ParsedStatementTransaction],
        bitcoinAccount: Bool,
        isCredit: (ParsedStatementTransaction) -> Bool,
        legacyMixUSDIntoBTC: Bool = false
    ) -> Decimal {
        transactions.reduce(into: Decimal.zero) { partial, tx in
            if let signed = keepBalanceSignedAmount(
                for: tx,
                bitcoinAccount: bitcoinAccount,
                isCredit: isCredit(tx),
                legacyMixUSDIntoBTC: legacyMixUSDIntoBTC
            ) {
                partial += signed
            }
        }
    }

    /// When clearing an older Strike import that may have used the USD-into-BTC bug,
    /// prefer the legacy net if it is meaningfully larger than the correct BTC-only net.
    static func netSignedForClearingBalanceAdjustment(
        transactions: [ParsedStatementTransaction],
        bitcoinAccount: Bool,
        isCredit: (ParsedStatementTransaction) -> Bool
    ) -> Decimal {
        let fixed = keepBalanceNetSigned(
            transactions: transactions,
            bitcoinAccount: bitcoinAccount,
            isCredit: isCredit,
            legacyMixUSDIntoBTC: false
        )
        guard bitcoinAccount else { return fixed }
        let legacy = keepBalanceNetSigned(
            transactions: transactions,
            bitcoinAccount: bitcoinAccount,
            isCredit: isCredit,
            legacyMixUSDIntoBTC: true
        )
        if legacy.magnitude > fixed.magnitude + 1 {
            return legacy
        }
        return fixed
    }

    static func prefersCreditAccount(fileName: String) -> Bool {
        let name = fileName.lowercased()
        let keys = ["credit", "amex", "visa", "mastercard", "discover", "card"]
        return keys.contains { name.contains($0) }
    }

    static func matchingIndex(
        for tx: ParsedStatementTransaction,
        in entries: [ExistingEntry],
        used: Set<Int>,
        calendar: Calendar = .current
    ) -> Int? {
        if let ref = tx.sourceReference, !ref.isEmpty {
            if let idx = entries.indices.first(where: { !used.contains($0) && entries[$0].sourceReference == ref }) {
                return idx
            }
        }

        let txTitle = normalizeTitle(tx.title)
        let txDay = calendar.startOfDay(for: tx.date)

        var best: (index: Int, dayDelta: Int)?
        for (idx, entry) in entries.enumerated() {
            guard !used.contains(idx) else { continue }
            guard amountsMatch(entry.amount, tx.amount) else { continue }
            guard entry.isCredit == tx.isCredit else { continue }
            guard normalizeTitle(entry.title) == txTitle else { continue }

            let entryDay = calendar.startOfDay(for: entry.date)
            let days = abs(calendar.dateComponents([.day], from: txDay, to: entryDay).day ?? 99)
            guard days <= 1 else { continue }
            if let current = best {
                if days < current.dayDelta {
                    best = (idx, days)
                }
            } else {
                best = (idx, days)
            }
        }
        return best?.index
    }

    struct TransferCounterpart: Equatable {
        var uri: String
        var accountName: String
        var date: Date
        var amount: Decimal
        var btcAmount: Decimal?
        var isCredit: Bool
        var alreadyPaired: Bool
    }

    /// Opposite-sign, same USD or BTC amount, within `maxDayDelta` days. Titles are ignored.
    static func transferMatchIndex(
        usdAmount: Decimal,
        btcAmount: Decimal?,
        isCredit: Bool,
        date: Date,
        in counterparts: [TransferCounterpart],
        used: Set<Int>,
        calendar: Calendar = .current,
        maxDayDelta: Int = 3
    ) -> Int? {
        let txDay = calendar.startOfDay(for: date)
        var best: (index: Int, dayDelta: Int, btcMatch: Bool)?

        for (idx, entry) in counterparts.enumerated() {
            guard !used.contains(idx), !entry.alreadyPaired else { continue }
            guard entry.isCredit != isCredit else { continue }

            let btcMatch: Bool = {
                guard let lhs = btcAmount, lhs > 0, let rhs = entry.btcAmount, rhs > 0 else { return false }
                return amountsMatch(lhs, rhs)
            }()
            let usdMatch = amountsMatch(entry.amount, usdAmount)
            guard btcMatch || usdMatch else { continue }

            let days = abs(calendar.dateComponents([.day], from: txDay, to: calendar.startOfDay(for: entry.date)).day ?? 99)
            guard days <= maxDayDelta else { continue }

            if let current = best {
                if days < current.dayDelta || (days == current.dayDelta && btcMatch && !current.btcMatch) {
                    best = (idx, days, btcMatch)
                }
            } else {
                best = (idx, days, btcMatch)
            }
        }
        return best?.index
    }

    static func similarTransactionIds(
        to tx: ParsedStatementTransaction,
        originalTitle: String,
        in transactions: [ParsedStatementTransaction],
        originalTitles: [UUID: String]
    ) -> [UUID] {
        let norm = normalizeTitle(originalTitle)
        return transactions.compactMap { other in
            guard other.id != tx.id else { return nil }
            let otherOriginal = originalTitles[other.id] ?? other.title
            if !norm.isEmpty, normalizeTitle(otherOriginal) == norm {
                return other.id
            }
            if amountsMatch(other.amount, tx.amount), other.kind == tx.kind {
                return other.id
            }
            return nil
        }
    }
}

enum ImportTitleRewriteStore {
    private static let key = "ImportTitleRewrites"

    struct Rewrite: Codable, Equatable {
        var preferredTitle: String
        var category: String?
    }

    static func rewrite(for originalTitle: String, defaults: UserDefaults = .standard) -> Rewrite? {
        let norm = StatementImportMatching.normalizeTitle(originalTitle)
        guard !norm.isEmpty else { return nil }
        return all(defaults: defaults)[norm]
    }

    static func save(
        originalTitle: String,
        preferredTitle: String,
        category: String?,
        defaults: UserDefaults = .standard
    ) {
        let norm = StatementImportMatching.normalizeTitle(originalTitle)
        guard !norm.isEmpty else { return }
        var dict = all(defaults: defaults)
        dict[norm] = Rewrite(preferredTitle: preferredTitle, category: category)
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: key)
        }
    }

    static func all(defaults: UserDefaults = .standard) -> [String: Rewrite] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Rewrite].self, from: data)) ?? [:]
    }
}
