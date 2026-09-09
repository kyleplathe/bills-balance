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

    struct LedgerTitleSample: Equatable {
        var title: String
        var notes: String?
        var category: String?
    }

    struct TitleRewriteSuggestion: Identifiable, Equatable {
        var normalizedOriginal: String
        var originalTitle: String
        var preferredTitle: String
        var category: String?
        var transactionIds: [UUID]

        var id: String { normalizedOriginal }
        var matchCount: Int { transactionIds.count }
    }

    static func rewriteLookupKeys(for originalTitle: String) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()
        let payee = StrikeCSVParser.payeeName(from: originalTitle)
        let canonical = normalizeTitle(payee.isEmpty ? originalTitle : payee)
        let raw = normalizeTitle(originalTitle)
        for key in [canonical, raw] where !key.isEmpty && seen.insert(key).inserted {
            keys.append(key)
        }
        return keys
    }

    /// Infer original→preferred title maps from imported Strike ledger rows whose notes still have the bank payee.
    static func rewriteHints(from samples: [LedgerTitleSample]) -> [String: ImportTitleRewriteStore.Rewrite] {
        struct Bucket {
            var preferredCounts: [String: Int] = [:]
            var preferredDisplay: [String: String] = [:]
            var categoryCounts: [String: Int] = [:]
        }

        var buckets: [String: Bucket] = [:]
        for sample in samples {
            if LedgerTransfer.isTransfer(category: sample.category, title: sample.title) { continue }
            guard let original = StrikeCSVParser.originalPayee(from: sample.notes) else { continue }
            let origNorm = normalizeTitle(original)
            let prefNorm = normalizeTitle(sample.title)
            guard !origNorm.isEmpty, !prefNorm.isEmpty, origNorm != prefNorm else { continue }

            var bucket = buckets[origNorm] ?? Bucket()
            bucket.preferredCounts[prefNorm, default: 0] += 1
            bucket.preferredDisplay[prefNorm] = sample.title
            if let category = sample.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
                bucket.categoryCounts[category, default: 0] += 1
            }
            buckets[origNorm] = bucket
        }

        var hints: [String: ImportTitleRewriteStore.Rewrite] = [:]
        for (origNorm, bucket) in buckets {
            let total = bucket.preferredCounts.values.reduce(0, +)
            guard let winner = bucket.preferredCounts.max(by: { $0.value < $1.value }) else { continue }
            let tied = bucket.preferredCounts.filter { $0.value == winner.value }
            guard tied.count == 1, winner.value * 2 >= total else { continue }
            let category = bucket.categoryCounts.max(by: { $0.value < $1.value })?.key
            hints[origNorm] = ImportTitleRewriteStore.Rewrite(
                preferredTitle: bucket.preferredDisplay[winner.key] ?? winner.key,
                category: category
            )
        }
        return hints
    }

    static func lookupRewrite(
        for originalTitle: String,
        store: [String: ImportTitleRewriteStore.Rewrite],
        ledgerHints: [String: ImportTitleRewriteStore.Rewrite]
    ) -> (key: String, rewrite: ImportTitleRewriteStore.Rewrite)? {
        let keys = rewriteLookupKeys(for: originalTitle)
        for key in keys {
            if let rewrite = store[key] { return (key, rewrite) }
        }
        for key in keys {
            if let rewrite = ledgerHints[key] { return (key, rewrite) }
        }
        return nil
    }

    static func pendingTitleRewrites(
        originalTitles: [UUID: String],
        store: [String: ImportTitleRewriteStore.Rewrite],
        ledgerHints: [String: ImportTitleRewriteStore.Rewrite]
    ) -> [TitleRewriteSuggestion] {
        var groups: [String: (originalTitle: String, rewrite: ImportTitleRewriteStore.Rewrite, ids: [UUID])] = [:]
        for (id, original) in originalTitles.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let hit = lookupRewrite(for: original, store: store, ledgerHints: ledgerHints) else { continue }
            let preferredNorm = normalizeTitle(hit.rewrite.preferredTitle)
            guard !preferredNorm.isEmpty else { continue }
            let alreadyPreferred = rewriteLookupKeys(for: original).contains(preferredNorm)
            guard !alreadyPreferred else { continue }

            if var existing = groups[hit.key] {
                existing.ids.append(id)
                groups[hit.key] = existing
            } else {
                groups[hit.key] = (original, hit.rewrite, [id])
            }
        }

        return groups.map { key, value in
            TitleRewriteSuggestion(
                normalizedOriginal: key,
                originalTitle: value.originalTitle,
                preferredTitle: value.rewrite.preferredTitle,
                category: value.rewrite.category,
                transactionIds: value.ids
            )
        }
        .sorted { lhs, rhs in
            if lhs.matchCount != rhs.matchCount {
                return lhs.matchCount > rhs.matchCount
            }
            return lhs.originalTitle.localizedCaseInsensitiveCompare(rhs.originalTitle) == .orderedAscending
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
        let dict = all(defaults: defaults)
        for lookupKey in StatementImportMatching.rewriteLookupKeys(for: originalTitle) {
            if let rewrite = dict[lookupKey] { return rewrite }
        }
        return nil
    }

    static func save(
        originalTitle: String,
        preferredTitle: String,
        category: String?,
        defaults: UserDefaults = .standard
    ) {
        let keys = StatementImportMatching.rewriteLookupKeys(for: originalTitle)
        guard let norm = keys.first else { return }
        let preferred = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferred.isEmpty else { return }
        let preferredNorm = StatementImportMatching.normalizeTitle(preferred)
        guard preferredNorm != norm else { return }

        var dict = all(defaults: defaults)
        let existing = dict[norm]
        let resolvedCategory: String? = {
            if let category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return category
            }
            return existing?.category
        }()
        dict[norm] = Rewrite(preferredTitle: preferred, category: resolvedCategory)
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: key)
        }
    }

    static func learn(fromNotes notes: String?, preferredTitle: String, category: String?, defaults: UserDefaults = .standard) {
        guard let original = StrikeCSVParser.originalPayee(from: notes) else { return }
        save(originalTitle: original, preferredTitle: preferredTitle, category: category, defaults: defaults)
    }

    static func all(defaults: UserDefaults = .standard) -> [String: Rewrite] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Rewrite].self, from: data)) ?? [:]
    }
}
