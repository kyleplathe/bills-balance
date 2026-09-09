import Foundation

/// Calendar “living within means” copy. Pure so unit tests can cover paycheck vs trailing-deposit fallback.
enum LivingMeansInsight {
    enum Source: Equatable {
        case paycheck
        case trailingDeposits
    }

    struct Means: Equatable {
        var percentage: Decimal
        var isBelow: Bool
        var source: Source
    }

    static let quotes: [String] = [
        "Today’s calendar is a plan, not a verdict.",
        "Spending less than you have is the whole game.",
        "Small bills paid on time are a kind of quiet wealth.",
        "You don’t need a salary to live with intention.",
        "Irregular income still counts. Track the month you are in.",
        "A clear due date is already a kind of control.",
        "Pay what you can see. The rest gets easier.",
        "Living within your means starts with knowing the month.",
        "One honest calendar beats a perfect budget you don’t open.",
        "Keep going. The month is still yours to shape."
    ]

    static func quote(on date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = (day - 1) % quotes.count
        return quotes[index]
    }

    /// Typical monthly income from deposits over a trailing window (default 90 days → divide by 3).
    static func typicalMonthlyIncome(from deposits: [Decimal], months: Int = 3, minimumDeposits: Int = 2) -> Decimal? {
        let positive = deposits.filter { $0 > 0 }
        guard positive.count >= minimumDeposits, months > 0 else { return nil }
        let total = positive.reduce(Decimal.zero, +)
        guard total > 0 else { return nil }
        return total / Decimal(months)
    }

    static func percentage(income: Decimal, expenses: Decimal) -> (percentage: Decimal, isBelow: Bool)? {
        guard income > 0 else { return nil }
        let difference = income - expenses
        return ((difference / income) * 100, difference >= 0)
    }

    static func means(
        paycheckIncome: Decimal,
        trailingDeposits: [Decimal],
        expenses: Decimal
    ) -> Means? {
        if let paycheck = percentage(income: paycheckIncome, expenses: expenses) {
            return Means(percentage: paycheck.percentage, isBelow: paycheck.isBelow, source: .paycheck)
        }
        guard let typical = typicalMonthlyIncome(from: trailingDeposits),
              let trailing = percentage(income: typical, expenses: expenses) else {
            return nil
        }
        return Means(percentage: trailing.percentage, isBelow: trailing.isBelow, source: .trailingDeposits)
    }

    static func meansLine(_ means: Means) -> String {
        var absPercentage = abs(means.percentage)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &absPercentage, 1, .plain)

        if rounded == 0 {
            switch means.source {
            case .paycheck:
                return "You’re breaking even this month"
            case .trailingDeposits:
                return "Based on the last 3 months of deposits, this month you’re breaking even"
            }
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let percentageString = formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0"
        let relation = means.isBelow ? "below" : "above"

        switch means.source {
        case .paycheck:
            return "This month you’re living \(percentageString)% \(relation) your means"
        case .trailingDeposits:
            return "Based on the last 3 months of deposits, this month you’re living \(percentageString)% \(relation) your typical income"
        }
    }
}
