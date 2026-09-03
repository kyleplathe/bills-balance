//
//  SupabaseManager.swift
//  BillsAndBalance
//
//  Replaces local Core Data bill persistence with Supabase.
//

import Foundation
import Supabase

@MainActor
final class SupabaseManager: ObservableObject {
    @Published private(set) var currentUser: User?

    let client: SupabaseClient
    private let billsTable = "bills"
    private let accountsTable = "accounts"

    init(supabaseURL: URL, supabaseKey: String) {
        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
    }

    convenience init() throws {
        guard
            let urlString = ProcessInfo.processInfo.environment["SUPABASE_URL"],
            let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
            let url = URL(string: urlString)
        else {
            throw SupabaseManagerError.missingConfiguration
        }

        self.init(supabaseURL: url, supabaseKey: key)
    }

    // MARK: - Authentication

    func signUp(email: String, password: String) async throws -> Session {
        let session = try await client.auth.signUp(
            email: email,
            password: password
        )
        currentUser = session.user
        return session
    }

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        currentUser = session.user
        return session
    }

    func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
    }

    @discardableResult
    func refreshCurrentUser() async throws -> User? {
        do {
            let user = try await client.auth.user()
            currentUser = user
            return user
        } catch {
            currentUser = nil
            return nil
        }
    }

    // MARK: - Bills CRUD

    func fetchBills() async throws -> [SupabaseBill] {
        let userID = try await requireCurrentUserID()

        return try await client
            .from(billsTable)
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("due_date", ascending: true)
            .execute()
            .value
    }

    func fetchBill(id: UUID) async throws -> SupabaseBill {
        let userID = try await requireCurrentUserID()

        return try await client
            .from(billsTable)
            .select()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .single()
            .execute()
            .value
    }

    func createBill(_ draft: NewBillDraft) async throws -> SupabaseBill {
        let userID = try await requireCurrentUserID()
        let now = Date()

        let payload = NewBillPayload(
            id: draft.id ?? UUID(),
            userID: userID,
            name: draft.name,
            amount: draft.amount,
            dueDate: draft.dueDate,
            isPaid: draft.isPaid,
            notes: draft.notes,
            recurrence: draft.recurrence,
            autoPay: draft.autoPay,
            categoryID: draft.categoryID,
            linkedAccountID: draft.linkedAccountID,
            seriesID: draft.seriesID,
            btcValueAtPay: draft.btcValueAtPay,
            isVerified: draft.isVerified,
            createdAt: now,
            updatedAt: now
        )

        return try await client
            .from(billsTable)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateBill(id: UUID, changes: BillUpdateChanges) async throws -> SupabaseBill {
        let userID = try await requireCurrentUserID()

        var payload = changes
        payload.updatedAt = Date()

        return try await client
            .from(billsTable)
            .update(payload)
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteBill(id: UUID) async throws {
        let userID = try await requireCurrentUserID()

        _ = try await client
            .from(billsTable)
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    func fetchAccounts() async throws -> [SupabaseAccount] {
        let userID = try await requireCurrentUserID()

        return try await client
            .from(accountsTable)
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func updateProjectionPreference(accountID: UUID, days: Int) async throws -> SupabaseAccount {
        let userID = try await requireCurrentUserID()

        let payload = AccountProjectionUpdatePayload(
            projectionDaysPref: days,
            updatedAt: Date()
        )

        return try await client
            .from(accountsTable)
            .update(payload)
            .eq("id", value: accountID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    private func requireCurrentUserID() async throws -> UUID {
        if let id = currentUser?.id {
            return id
        }

        if let user = try await refreshCurrentUser() {
            return user.id
        }

        throw SupabaseManagerError.notAuthenticated
    }
}

enum SupabaseManagerError: LocalizedError {
    case missingConfiguration
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Missing SUPABASE_URL or SUPABASE_ANON_KEY configuration."
        case .notAuthenticated:
            return "User must be authenticated before accessing bills."
        }
    }
}

struct NewBillDraft: Sendable {
    let id: UUID?
    let name: String
    let amount: Decimal
    let dueDate: Date
    let isPaid: Bool
    let notes: String?
    let recurrence: RecurrenceType
    let autoPay: Bool
    let categoryID: UUID?
    let linkedAccountID: UUID?
    let seriesID: UUID?
    let btcValueAtPay: Decimal?
    let isVerified: Bool

    init(
        id: UUID? = nil,
        name: String,
        amount: Decimal,
        dueDate: Date,
        isPaid: Bool = false,
        notes: String? = nil,
        recurrence: RecurrenceType = .monthly,
        autoPay: Bool = false,
        categoryID: UUID? = nil,
        linkedAccountID: UUID? = nil,
        seriesID: UUID? = nil,
        btcValueAtPay: Decimal? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
        self.notes = notes
        self.recurrence = recurrence
        self.autoPay = autoPay
        self.categoryID = categoryID
        self.linkedAccountID = linkedAccountID
        self.seriesID = seriesID
        self.btcValueAtPay = btcValueAtPay
        self.isVerified = isVerified
    }
}

private struct NewBillPayload: Encodable {
    let id: UUID
    let userID: UUID
    let name: String
    let amount: Decimal
    let dueDate: Date
    let isPaid: Bool
    let notes: String?
    let recurrence: RecurrenceType
    let autoPay: Bool
    let categoryID: UUID?
    let linkedAccountID: UUID?
    let seriesID: UUID?
    let btcValueAtPay: Decimal?
    let isVerified: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case amount
        case dueDate = "due_date"
        case isPaid = "is_paid"
        case notes
        case recurrence
        case autoPay = "auto_pay"
        case categoryID = "category_id"
        case linkedAccountID = "linked_account_id"
        case seriesID = "series_id"
        case btcValueAtPay = "btc_value_at_pay"
        case isVerified = "is_verified"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BillUpdateChanges: Encodable, Sendable {
    var name: String?
    var amount: Decimal?
    var dueDate: Date?
    var isPaid: Bool?
    var notes: String?
    var recurrence: RecurrenceType?
    var autoPay: Bool?
    var categoryID: UUID??
    var linkedAccountID: UUID??
    var seriesID: UUID??
    var btcValueAtPay: Decimal??
    var isVerified: Bool?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case amount
        case dueDate = "due_date"
        case isPaid = "is_paid"
        case notes
        case recurrence
        case autoPay = "auto_pay"
        case categoryID = "category_id"
        case linkedAccountID = "linked_account_id"
        case seriesID = "series_id"
        case btcValueAtPay = "btc_value_at_pay"
        case isVerified = "is_verified"
        case updatedAt = "updated_at"
    }
}

private struct AccountProjectionUpdatePayload: Encodable {
    let projectionDaysPref: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case projectionDaysPref = "projection_days_pref"
        case updatedAt = "updated_at"
    }
}
