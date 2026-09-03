//
//  PersistenceController.swift
//  BillsAndBalance
//
//  Created on 11/4/24.
//

@preconcurrency import CoreData

extension Notification.Name {
    static let persistentStoreDidLoad = Notification.Name("persistentStoreDidLoad")
}

struct PersistenceController {
    static let shared = PersistenceController()
    static let cloudKitContainerIdentifier = "iCloud.com.kyle.billsandbalance"
    private(set) static var isStoreLoaded = false

    /// CloudKit requires matching entitlements; skip it when the ubiquity container isn't available.
    private static var canUseCloudKit: Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        return FileManager.default.url(forUbiquityContainerIdentifier: cloudKitContainerIdentifier) != nil
    }

    static func waitForStores() async {
        if isStoreLoaded { return }
        let notifications = NotificationCenter.default.notifications(named: .persistentStoreDidLoad)
        if isStoreLoaded { return }
        for await _ in notifications {
            break
        }
    }

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

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let iCloudAvailable = !inMemory && Self.canUseCloudKit
        if iCloudAvailable {
            container = NSPersistentCloudKitContainer(name: "BillsAndBalance")
        } else {
            container = NSPersistentContainer(name: "BillsAndBalance")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if iCloudAvailable {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: Self.cloudKitContainerIdentifier
                )
            } else {
                description.cloudKitContainerOptions = nil
            }
        }

        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        let loadedContainer = container
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                if storeDescription.cloudKitContainerOptions != nil {
                    storeDescription.cloudKitContainerOptions = nil
                    loadedContainer.loadPersistentStores { _, retryError in
                        if let retryError = retryError as NSError? {
                            fatalError("Unresolved error \(retryError), \(retryError.userInfo)")
                        }
                        Self.markStoreLoaded()
                    }
                    return
                }
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            Self.markStoreLoaded()
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func markStoreLoaded() {
        guard !isStoreLoaded else { return }
        isStoreLoaded = true
        NotificationCenter.default.post(name: .persistentStoreDidLoad, object: nil)
    }
}
