import Foundation
import CoreData

// The missing DTO (Data Transfer Object)
struct SupabaseBill: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String
    var amount: Decimal
    var dueDate: Date
    var isPaid: Bool
    var recurrence: String?
    var seriesId: UUID?
    var btcValueAtPay: Decimal?
    var isVerified: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case amount
        case dueDate = "due_date"
        case isPaid = "is_paid"
        case recurrence
        case seriesId = "series_id"
        case btcValueAtPay = "btc_value_at_pay"
        case isVerified = "is_verified"
    }
}

extension SupabaseBill {
    func apply(to bill: Bill) {
        bill.id = self.id
        bill.name = self.name
        bill.amount = NSDecimalNumber(decimal: self.amount)
        bill.dueDate = self.dueDate
        bill.isPaid = self.isPaid
        bill.recurrenceType = self.recurrence ?? "none"
        bill.recurrenceInterval = (self.recurrence == nil || self.recurrence == "none") ? 0 : 1
        bill.seriesId = self.seriesId
        bill.paidDate = self.isPaid ? self.dueDate : nil
        bill.updatedAt = Date()
        if bill.category == nil {
            bill.category = "General"
        }
    }

    func toUIModel(in context: NSManagedObjectContext) -> Bill {
        let bill = Bill(context: context)
        bill.notes = ""
        bill.autoPay = false
        bill.createdAt = Date()
        bill.paymentCard = nil
        bill.category = "General"
        apply(to: bill)
        return bill
    }
}

extension Bill {
    func toSupabaseModel(userId: UUID) -> SupabaseBill {
        SupabaseBill(
            id: self.id ?? UUID(),
            userId: userId,
            name: self.name ?? "",
            amount: self.amount?.decimalValue ?? 0,
            dueDate: self.dueDate ?? Date(),
            isPaid: self.isPaid,
            recurrence: self.recurrenceType,
            seriesId: self.seriesId,
            btcValueAtPay: nil,
            isVerified: false
        )
    }
}