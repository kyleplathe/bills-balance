//
//  CategoryStyle.swift
//  BillsAndBalance
//
//  Stable color and icon for a category name. Charts, lists, and pickers
//  all read from here so Food stays orange whether it ranks first or eighth.
//

import SwiftUI

enum CategoryStyle {
    /// High-chroma tones aligned to Apple Card category hues (Food→orange,
    /// Travel→green, etc.) with matched lightness so weighted blends melt cleanly.
    private enum Tone {
        static let rose      = Color(red: 0.98, green: 0.28, blue: 0.42) // Healthcare (Apple red)
        static let coral     = Color(red: 1.00, green: 0.42, blue: 0.28) // Housing
        static let tangerine = Color(red: 1.00, green: 0.52, blue: 0.20) // Food (Apple orange)
        static let amber     = Color(red: 1.00, green: 0.78, blue: 0.18) // Shopping (Apple yellow)
        static let gold      = Color(red: 1.00, green: 0.68, blue: 0.16) // Utilities / tax
        static let emerald   = Color(red: 0.18, green: 0.82, blue: 0.48) // Travel (Apple green)
        static let jade      = Color(red: 0.12, green: 0.72, blue: 0.48) // Savings / Investments
        static let electric  = Color(red: 0.28, green: 0.52, blue: 1.00) // Transportation (Apple blue)
        static let azure     = Color(red: 0.30, green: 0.62, blue: 0.98) // Education
        static let violet    = Color(red: 0.62, green: 0.36, blue: 0.98) // Services / Insurance (Apple purple)
        static let orchid    = Color(red: 0.52, green: 0.40, blue: 0.96) // Debt / Business / Subscriptions
        static let hotPink   = Color(red: 1.00, green: 0.32, blue: 0.58) // Entertainment (Apple pink)
        static let blush     = Color(red: 0.98, green: 0.45, blue: 0.62) // Gifts
        static let cyan      = Color(red: 0.18, green: 0.82, blue: 0.92) // custom fallback
        static let teal      = Color(red: 0.12, green: 0.78, blue: 0.72) // Transfer / Personal Care
        static let mint      = Color(red: 0.22, green: 0.86, blue: 0.58) // Income
        static let muted     = Color(red: 0.52, green: 0.54, blue: 0.60) // Other
    }

    private static let customPalette: [Color] = [
        Tone.violet, Tone.cyan, Tone.tangerine, Tone.electric,
        Tone.hotPink, Tone.emerald, Tone.amber, Tone.orchid
    ]

    static func color(for name: String) -> Color {
        switch canonical(name) {
        case "Housing": return Tone.coral
        case "Utilities": return Tone.gold
        case "Food & Dining": return Tone.tangerine
        case "Transportation": return Tone.electric
        case "Healthcare": return Tone.rose
        case "Insurance": return Tone.violet
        case "Entertainment": return Tone.hotPink
        case "Shopping": return Tone.amber
        case "Personal Care": return Tone.teal
        case "Education": return Tone.azure
        case "Subscriptions": return Tone.orchid
        case "Debt Payment": return Tone.orchid
        case "Savings": return Tone.jade
        case "Investments": return Tone.jade
        case "Gifts & Donations": return Tone.blush
        case "Travel": return Tone.emerald
        case "Business": return Tone.violet
        case "Other", "Uncategorized", "": return Tone.muted
        case "Digital Wallet Fees": return Tone.gold
        case "Sales Tax": return Tone.gold
        case "Income": return Tone.mint
        case "Transfer": return Tone.teal
        default:
            return customPalette[stableIndex(for: name) % customPalette.count]
        }
    }

    static func icon(for name: String) -> String {
        switch canonical(name) {
        case "Housing": return "house"
        case "Utilities": return "bolt.fill"
        case "Food & Dining": return "fork.knife"
        case "Transportation": return "car"
        case "Healthcare": return "cross.case.fill"
        case "Insurance": return "shield.fill"
        case "Entertainment": return "tv.fill"
        case "Shopping": return "bag.fill"
        case "Personal Care": return "sparkles"
        case "Education": return "book.fill"
        case "Subscriptions": return "repeat"
        case "Debt Payment": return "creditcard"
        case "Savings": return "banknote.fill"
        case "Investments": return "chart.line.uptrend.xyaxis"
        case "Gifts & Donations": return "gift.fill"
        case "Travel": return "airplane"
        case "Business": return "briefcase.fill"
        case "Digital Wallet Fees": return "bitcoinsign.circle.fill"
        case "Sales Tax": return "percent"
        case "Income": return "arrow.down.circle.fill"
        case "Transfer": return "arrow.left.arrow.right"
        case "Other", "Uncategorized": return "questionmark.circle.fill"
        default:
            return iconFallback(for: name)
        }
    }

    /// Fallback spectrum when a bar has no category breakdown — Apple Card hue order
    /// (red → orange → yellow → green → blue → purple → pink) in the electric-sunset family.
    /// Long overlapping stops so colors melt instead of banding. Map this to the *chart*
    /// height (not each bar) so every bar shares the same color at the same Y.
    static let appleCardSpectrum = LinearGradient(
        stops: [
            .init(color: Tone.rose,      location: 0.00),
            .init(color: Tone.tangerine, location: 0.14),
            .init(color: Tone.amber,     location: 0.28),
            .init(color: Tone.emerald,   location: 0.44),
            .init(color: Tone.electric,  location: 0.60),
            .init(color: Tone.violet,    location: 0.76),
            .init(color: Tone.hotPink,   location: 1.00),
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    /// Decorative 2–3 color blend for compact chips. Uses the largest categories.
    static func compactGradient(categories: [(name: String, amount: Decimal)]) -> LinearGradient {
        valueWeightedGradient(categories: categories)
    }

    /// Vertical gradient whose color bands are sized by each category's share of spending.
    static func valueWeightedGradient(categories: [(name: String, amount: Decimal)]) -> LinearGradient {
        let positive = categories.filter { $0.amount > 0 }
        guard !positive.isEmpty else {
            return LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .bottom, endPoint: .top)
        }

        let total = positive.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else {
            return LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .bottom, endPoint: .top)
        }

        let sorted = positive.sorted { $0.amount > $1.amount }
        if sorted.count == 1 {
            let color = color(for: sorted[0].name)
            return LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .bottom, endPoint: .top)
        }

        var stops: [Gradient.Stop] = []
        var cursor: Double = 0
        for (index, category) in sorted.enumerated() {
            let share = ((category.amount as NSDecimalNumber).doubleValue)
                / ((total as NSDecimalNumber).doubleValue)
            let color = color(for: category.name)
            let nextColor: Color = {
                guard index + 1 < sorted.count else { return color }
                return self.color(for: sorted[index + 1].name)
            }()
            // Longer soft overlap between category bands so adjacent colors melt together.
            let blend = min(0.35, max(0.10, share * 0.70))
            let holdEnd = max(cursor, cursor + share - blend)
            let bandEnd = min(1, cursor + share)
            let mid = (holdEnd + bandEnd) / 2

            if index == 0 {
                stops.append(Gradient.Stop(color: color, location: 0))
            }
            stops.append(Gradient.Stop(color: color, location: holdEnd))
            if blend > 0.001, index + 1 < sorted.count {
                stops.append(Gradient.Stop(color: color.opacity(0.88), location: mid))
                stops.append(Gradient.Stop(color: nextColor.opacity(0.92), location: bandEnd))
            } else {
                stops.append(Gradient.Stop(color: color, location: bandEnd))
            }
            cursor = bandEnd
        }
        if let last = stops.last, last.location < 1 {
            stops.append(Gradient.Stop(color: last.color, location: 1))
        }

        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .bottom, endPoint: .top)
    }

    static func canonical(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = [
            "Housing", "Utilities", "Food & Dining", "Transportation", "Healthcare",
            "Insurance", "Entertainment", "Shopping", "Personal Care", "Education",
            "Subscriptions", "Debt Payment", "Savings", "Investments", "Gifts & Donations",
            "Travel", "Business", "Other", "Uncategorized", "Digital Wallet Fees",
            "Sales Tax", "Income", "Transfer"
        ]
        return known.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
    }

    private static func stableIndex(for name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash = 0
        for scalar in key.unicodeScalars {
            hash = hash &* 31 &+ Int(scalar.value)
        }
        return abs(hash)
    }

    private static func iconFallback(for name: String) -> String {
        let lowercased = name.lowercased()
        if lowercased.contains("credit") || lowercased.contains("debt") { return "creditcard" }
        if lowercased.contains("housing") || lowercased.contains("rent") || lowercased.contains("mortgage") { return "house" }
        if lowercased.contains("food") || lowercased.contains("dining") || lowercased.contains("grocery") { return "fork.knife" }
        if lowercased.contains("transport") || lowercased.contains("fuel") { return "car" }
        if lowercased.contains("utilit") || lowercased.contains("electric") || lowercased.contains("internet") { return "bolt.fill" }
        if lowercased.contains("health") || lowercased.contains("medical") { return "cross.case.fill" }
        if lowercased.contains("insurance") { return "shield.fill" }
        if lowercased.contains("entertainment") { return "tv.fill" }
        if lowercased.contains("shop") { return "bag.fill" }
        if lowercased.contains("education") { return "book.fill" }
        if lowercased.contains("subscription") { return "repeat" }
        if lowercased.contains("saving") { return "banknote.fill" }
        if lowercased.contains("invest") { return "chart.line.uptrend.xyaxis" }
        if lowercased.contains("gift") || lowercased.contains("donation") { return "gift.fill" }
        if lowercased.contains("travel") { return "airplane" }
        if lowercased.contains("business") { return "briefcase.fill" }
        return "dollarsign.circle.fill"
    }
}
