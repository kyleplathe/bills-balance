import CoreData

protocol BillRepository {
    func fetchBills() async throws -> [SupabaseBill]
    func upsertBill(_ bill: Bill) async throws
    func setPaidStatus(for id: UUID, isPaid: Bool) async throws
    func deleteBill(id: UUID) async throws
}

enum SupabaseConfigurationError: LocalizedError {
    case implementationUnavailable

    var errorDescription: String? {
        "Supabase support is on hold for this build."
    }
}

struct SupabaseManager {
    init() throws {
        throw SupabaseConfigurationError.implementationUnavailable
    }
}

struct SupabaseBill: Identifiable, Equatable {
    let id: UUID
    var name: String
    var amount: Decimal
    var dueDate: Date?
    var notes: String
    var recurrenceType: String
    var recurrenceInterval: Int16
    var autoPay: Bool
    var isPaid: Bool
    var seriesId: UUID?
    var paymentCard: String?
    var category: String?
    var createdAt: Date?
    var updatedAt: Date?

    func apply(to bill: Bill) {
        bill.id = id
        bill.name = name
        bill.amount = NSDecimalNumber(decimal: amount)
        bill.dueDate = dueDate
        bill.notes = notes
        bill.recurrenceType = recurrenceType
        bill.recurrenceInterval = recurrenceInterval
        bill.autoPay = autoPay
        bill.isPaid = isPaid
        bill.seriesId = seriesId
        bill.paymentCard = paymentCard
        bill.category = category
        bill.createdAt = createdAt
        bill.updatedAt = updatedAt
    }

    func toUIModel(in context: NSManagedObjectContext) -> Bill {
        let bill = Bill(context: context)
        apply(to: bill)
        return bill
    }
}

final class SupabaseBillRepository: BillRepository {
    init(supabaseManager: SupabaseManager) {}

    func fetchBills() async throws -> [SupabaseBill] {
        throw SupabaseConfigurationError.implementationUnavailable
    }

    func upsertBill(_ bill: Bill) async throws {
        throw SupabaseConfigurationError.implementationUnavailable
    }

    func setPaidStatus(for id: UUID, isPaid: Bool) async throws {
        throw SupabaseConfigurationError.implementationUnavailable
    }

    func deleteBill(id: UUID) async throws {
        throw SupabaseConfigurationError.implementationUnavailable
    }
}
