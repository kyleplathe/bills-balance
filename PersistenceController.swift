//
//  PersistenceController.swift
//  BillsAndBalance
//
//  Created on 11/4/24.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        let primaryAccount = Account(context: viewContext)
        primaryAccount.id = UUID()
        primaryAccount.name = "Household Checking"
        primaryAccount.type = "checking"
        primaryAccount.startingBalance = NSDecimalNumber(value: 2500.00)
        primaryAccount.createdAt = Date()
        primaryAccount.updatedAt = Date()
        primaryAccount.order = 0
        
        let sampleBills = [
            ("Rent", 1500.00, 1),
            ("Electric", 120.50, 15),
            ("Internet", 79.99, 20),
            ("Phone", 45.00, 10),
            ("Netflix", 15.99, 5)
        ]
        
        for (name, amount, dayOffset) in sampleBills {
            let newBill = Bill(context: viewContext)
            newBill.id = UUID()
            newBill.name = name
            newBill.amount = NSDecimalNumber(value: amount)
            newBill.dueDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
            newBill.isPaid = false
            newBill.recurrenceType = "monthly"
            newBill.recurrenceInterval = 1
            newBill.autoPay = false
            newBill.seriesId = UUID()
            newBill.createdAt = Date()
            newBill.updatedAt = Date()
            newBill.account = primaryAccount
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "BillsAndBalance")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

