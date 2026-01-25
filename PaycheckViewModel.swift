import Foundation
import CoreData
import SwiftUI

class PaycheckViewModel: ObservableObject {
    @Published var paychecks: [Paycheck] = []
    
    private let context: NSManagedObjectContext
    private weak var accountViewModel: AccountViewModel?
    
    init(context: NSManagedObjectContext, accountViewModel: AccountViewModel? = nil) {
        self.context = context
        self.accountViewModel = accountViewModel
        fetchPaychecks()
    }
    
    func attachAccountViewModel(_ accountViewModel: AccountViewModel) {
        self.accountViewModel = accountViewModel
    }
    
    func fetchPaychecks() {
        let request = NSFetchRequest<Paycheck>(entityName: "Paycheck")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Paycheck.firstDepositDate, ascending: true)]
        do {
            paychecks = try context.fetch(request)
        } catch {
            print("Error fetching paychecks: \(error)")
            paychecks = []
        }
    }
    
    func addPaycheck(name: String,
                     amount: Decimal,
                     firstDepositDate: Date,
                     recurrenceType: String,
                     recurrenceInterval: Int,
                     autoReconcile: Bool,
                     notes: String?,
                     account: Account?) {
        let paycheck = Paycheck(context: context)
        paycheck.id = UUID()
        paycheck.name = name
        paycheck.amount = NSDecimalNumber(decimal: amount)
        paycheck.firstDepositDate = firstDepositDate
        paycheck.recurrenceType = recurrenceType
        paycheck.recurrenceInterval = Int16(max(recurrenceInterval, 1))
        paycheck.autoReconcile = autoReconcile
        paycheck.notes = notes
        paycheck.createdAt = Date()
        paycheck.updatedAt = Date()
        paycheck.account = account
        saveContext()
    }
    
    func updatePaycheck(_ paycheck: Paycheck,
                        name: String,
                        amount: Decimal,
                        firstDepositDate: Date,
                        recurrenceType: String,
                        recurrenceInterval: Int,
                        autoReconcile: Bool,
                        notes: String?,
                        account: Account?) {
        paycheck.name = name
        paycheck.amount = NSDecimalNumber(decimal: amount)
        paycheck.firstDepositDate = firstDepositDate
        paycheck.recurrenceType = recurrenceType
        paycheck.recurrenceInterval = Int16(max(recurrenceInterval, 1))
        paycheck.autoReconcile = autoReconcile
        paycheck.notes = notes
        paycheck.updatedAt = Date()
        paycheck.account = account
        saveContext()
    }
    
    func deletePaycheck(_ paycheck: Paycheck) {
        context.delete(paycheck)
        saveContext()
    }
    
    // MARK: - Occurrences
    func occurrences(in interval: DateInterval) -> [PaycheckOccurrence] {
        let calendar = Calendar.current
        let projectionStart = calendar.startOfDay(for: Date())
        // Show 3 months of future income (matching user request for 2-3 months)
        let projectionLimit = calendar.date(byAdding: .month, value: 3, to: projectionStart) ?? interval.end
        let allowProjection = interval.start < projectionLimit
        
        var results: [PaycheckOccurrence] = []
        
        // Add actual occurrences (ones that have already happened or are today)
        for paycheck in paychecks {
            guard let baseDate = paycheck.firstDepositDate else { continue }
            if interval.contains(baseDate) {
                let identifier = occurrenceIdentifier(for: paycheck, on: baseDate)
                let isProjected = baseDate > Date()
                results.append(PaycheckOccurrence(id: identifier,
                                                  paycheck: paycheck,
                                                  date: baseDate,
                                                  isProjected: isProjected))
            }
        }
        
        // Add projected occurrences for recurring paychecks
        guard allowProjection else {
            return results.sorted { $0.date < $1.date }
        }
        
        for paycheck in paychecks {
            guard let baseDate = paycheck.firstDepositDate else { continue }
            let intervalValue = max(Int(paycheck.recurrenceInterval), 1)
            let recurrenceType = paycheck.recurrenceType ?? "none"
            
            guard recurrenceType != "none" else { continue }
            
            var nextDate = baseDate
            
            // Fast-forward to interval start
            while nextDate < interval.start {
                guard let candidate = nextRecurrenceDate(from: nextDate, type: recurrenceType, interval: intervalValue) else { break }
                if candidate == nextDate { break }
                nextDate = candidate
                if nextDate >= projectionLimit { break }
            }
            
            // Generate occurrences within interval
            while nextDate < interval.end, nextDate < projectionLimit {
                if nextDate >= interval.start {
                    let identifier = occurrenceIdentifier(for: paycheck, on: nextDate)
                    let isProjected = nextDate > Date()
                    // Avoid duplicates
                    if !results.contains(where: { $0.id == identifier }) {
                        results.append(PaycheckOccurrence(id: identifier,
                                                          paycheck: paycheck,
                                                          date: nextDate,
                                                          isProjected: isProjected))
                    }
                }
                guard let candidate = nextRecurrenceDate(from: nextDate, type: recurrenceType, interval: intervalValue) else { break }
                if candidate == nextDate { break }
                nextDate = candidate
            }
        }
        
        return results.sorted { $0.date < $1.date }
    }
    
    private func nextRecurrenceDate(from date: Date, type: String, interval: Int) -> Date? {
        switch type {
        case "daily":
            return Calendar.current.date(byAdding: .day, value: interval, to: date)
        case "weekly":
            return Calendar.current.date(byAdding: .weekOfYear, value: interval, to: date)
        case "monthly":
            return Calendar.current.date(byAdding: .month, value: interval, to: date)
        case "quarterly":
            return Calendar.current.date(byAdding: .month, value: 3 * interval, to: date)
        case "semiannually":
            return Calendar.current.date(byAdding: .month, value: 6 * interval, to: date)
        case "yearly":
            return Calendar.current.date(byAdding: .year, value: interval, to: date)
        default:
            return nil
        }
    }
    
    private func occurrenceIdentifier(for paycheck: Paycheck, on date: Date) -> String {
        let base = paycheck.objectID.uriRepresentation().absoluteString
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        return "\(base)#\(day)"
    }
    
    // MARK: - Clear All Paychecks
    func clearAllPaychecks() -> (success: Bool, message: String) {
        do {
            // Fetch all paychecks
            let request = NSFetchRequest<Paycheck>(entityName: "Paycheck")
            let allPaychecks = try context.fetch(request)
            
            // Delete all paychecks individually (works better with CloudKit)
            for paycheck in allPaychecks {
                context.delete(paycheck)
            }
            
            // Save context
            try context.save()
            fetchPaychecks()
            
            return (true, "All income cleared successfully")
        } catch {
            return (false, "Error clearing income: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Persistence
    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            fetchPaychecks()
            accountViewModel?.refreshData()
        } catch {
            print("Error saving paycheck context: \(error)")
        }
    }
}

struct PaycheckOccurrence: Identifiable {
    let id: String
    let paycheck: Paycheck
    let date: Date
    let isProjected: Bool
}
