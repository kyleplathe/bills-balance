import Foundation
import CoreData

protocol BillRepository {
    func fetchBills() async throws -> [SupabaseBill]
    func upsertBill(_ bill: Bill) async throws
    func setPaidStatus(for billID: UUID, isPaid: Bool) async throws
    func deleteBill(id: UUID) async throws
}

struct SupabaseBillRepository: BillRepository {
    private let supabaseManager: SupabaseManager

    init(supabaseManager: SupabaseManager) {
        self.supabaseManager = supabaseManager
    }

    func fetchBills() async throws -> [SupabaseBill] {
        try await supabaseManager.fetchBills()
    }

    func upsertBill(_ bill: Bill) async throws {
        guard
            let id = bill.id,
            let name = bill.name,
            let dueDate = bill.dueDate
        else {
            return
        }

        let recurrence = RecurrenceType(rawValue: bill.recurrenceType ?? "none") ?? .none
        let amount = bill.amount?.decimalValue ?? 0
        let notes = bill.notes?.isEmpty == true ? nil : bill.notes

        do {
            _ = try await supabaseManager.fetchBill(id: id)
            let changes = BillUpdateChanges(
                name: name,
                amount: amount,
                dueDate: dueDate,
                isPaid: bill.isPaid,
                notes: notes,
                recurrence: recurrence,
                autoPay: bill.autoPay,
                categoryID: nil,
                linkedAccountID: nil,
                seriesID: .some(bill.seriesId),
                btcValueAtPay: nil,
                isVerified: false,
                updatedAt: Date()
            )
            _ = try await supabaseManager.updateBill(id: id, changes: changes)
        } catch {
            let draft = NewBillDraft(
                id: id,
                name: name,
                amount: amount,
                dueDate: dueDate,
                isPaid: bill.isPaid,
                notes: notes,
                recurrence: recurrence,
                autoPay: bill.autoPay,
                categoryID: nil,
                linkedAccountID: nil,
                seriesID: bill.seriesId,
                btcValueAtPay: nil,
                isVerified: false
            )
            _ = try await supabaseManager.createBill(draft)
        }
    }

    func setPaidStatus(for billID: UUID, isPaid: Bool) async throws {
        let changes = BillUpdateChanges(
            name: nil,
            amount: nil,
            dueDate: nil,
            isPaid: isPaid,
            notes: nil,
            recurrence: nil,
            autoPay: nil,
            categoryID: nil,
            linkedAccountID: nil,
            seriesID: nil,
            btcValueAtPay: nil,
            isVerified: nil,
            updatedAt: Date()
        )
        _ = try await supabaseManager.updateBill(id: billID, changes: changes)
    }

    func deleteBill(id: UUID) async throws {
        try await supabaseManager.deleteBill(id: id)
    }
}

