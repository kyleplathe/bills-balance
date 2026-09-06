import Foundation
import CoreData

enum SampleDataSeeder {
    static let sampleNotes = "Sample data"

    @MainActor
    static func seedIfNeeded(accountViewModel: AccountViewModel, billViewModel: BillViewModel) {
        guard OnboardingManager.shared.shouldLoadSampleData else { return }
        OnboardingManager.shared.shouldLoadSampleData = false
        seed(accountViewModel: accountViewModel, billViewModel: billViewModel)
    }

    @MainActor
    static func seed(accountViewModel: AccountViewModel, billViewModel: BillViewModel) {
        accountViewModel.fetchAccounts()
        if !accountViewModel.accounts.isEmpty { return }

        let checking = accountViewModel.addAccount(
            name: "Household Checking",
            type: "checking",
            startingBalance: 2500
        )
        _ = accountViewModel.addAccount(
            name: "Savings",
            type: "savings",
            startingBalance: 1200
        )

        let calendar = Calendar.current
        let today = Date()
        let sampleBills: [(String, Decimal, Int, String)] = [
            ("Rent", 1500, 1, "Housing"),
            ("Electric", 120.50, 15, "Utilities"),
            ("Internet", 79.99, 20, "Utilities"),
            ("Phone", 45, 10, "Utilities"),
            ("Netflix", 15.99, 5, "Subscriptions")
        ]

        for (name, amount, day, category) in sampleBills {
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = min(day, 28)
            let due = calendar.date(from: components) ?? today
            _ = billViewModel.addBill(
                name: name,
                amount: amount,
                dueDate: due,
                notes: sampleNotes,
                recurrenceType: "monthly",
                recurrenceInterval: 1,
                account: checking,
                category: category,
                skipDuplicateCheck: true
            )
        }

        accountViewModel.fetchAccounts()
        billViewModel.fetchBills()
    }
}
