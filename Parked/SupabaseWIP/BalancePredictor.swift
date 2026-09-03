import Foundation

struct BalanceProjection {
    let account: SupabaseAccount
    let windowDays: Int
    let unpaidBillsTotal: Decimal
    let disposableBalance: Decimal
}

struct BalancePredictor {
    private let supabaseManager: SupabaseManager

    init(supabaseManager: SupabaseManager) {
        self.supabaseManager = supabaseManager
    }

    func disposableBalance(for accountID: UUID? = nil, windowDays overrideWindow: Int? = nil) async throws -> BalanceProjection {
        let accounts = try await supabaseManager.fetchAccounts()
        guard let account = selectAccount(from: accounts, accountID: accountID) else {
            throw BalancePredictorError.noAccountAvailable
        }

        let windowDays = overrideWindow ?? account.projectionDaysPref
        let now = Date()
        let windowEnd = Calendar.current.date(byAdding: .day, value: windowDays, to: now) ?? now

        let unpaidBills = try await supabaseManager.client
            .from("bills")
            .select()
            .eq("user_id", value: account.userID.uuidString)
            .eq("linked_account_id", value: account.id.uuidString)
            .eq("is_paid", value: false)
            .gte("due_date", value: now.ISO8601Format())
            .lte("due_date", value: windowEnd.ISO8601Format())
            .execute()
            .value as [SupabaseBill]

        let unpaidTotal = unpaidBills.reduce(Decimal.zero) { partial, bill in
            partial + bill.amount
        }

        let disposableBalance = account.balance - account.safetyBuffer - unpaidTotal
        return BalanceProjection(
            account: account,
            windowDays: windowDays,
            unpaidBillsTotal: unpaidTotal,
            disposableBalance: disposableBalance
        )
    }

    private func selectAccount(from accounts: [SupabaseAccount], accountID: UUID?) -> SupabaseAccount? {
        if let accountID {
            return accounts.first(where: { $0.id == accountID })
        }
        return accounts.first
    }
}

enum BalancePredictorError: LocalizedError {
    case noAccountAvailable

    var errorDescription: String? {
        switch self {
        case .noAccountAvailable:
            return "No account is available for projection."
        }
    }
}

