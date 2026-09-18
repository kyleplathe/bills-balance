import Foundation
import CoreData

enum AccountExportError: LocalizedError {
    case noAccounts
    case invalidPayload
    case decodeFailed
    case missingColumns
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .noAccounts: return "There are no accounts to export."
        case .invalidPayload: return "This file is not a Bills & Balance backup."
        case .decodeFailed: return "Could not read the export file."
        case .missingColumns: return "CSV must have Name and Starting Balance columns."
        case .noValidRows: return "No valid accounts were found in the CSV."
        }
    }
}

struct AccountExportPayload: Codable {
    var version: Int
    var exportedAt: Date
    var accounts: [ExportedAccount]
    var bills: [ExportedBill]?
    var paychecks: [ExportedPaycheck]?
    var customCategories: [String]?
    var creditCards: [String]?
}

struct ExportedAccount: Codable {
    var id: UUID
    var name: String
    var type: String
    var startingBalance: Decimal
    var isHidden: Bool
    var currency: String
    var btcDisplayFormat: String
    var feePercentage: Decimal
    var order: Int16
    var reserveBalance: Decimal?
    var startingBalanceUSD: Decimal?
    var startingBalanceBTCPrice: Decimal?
    var entries: [ExportedLedgerEntry]
}

struct ExportedLedgerEntry: Codable {
    var id: UUID
    var title: String
    var amount: Decimal
    var date: Date
    var notes: String
    var isCredit: Bool
    var isReconciled: Bool
    var category: String?
    var entryType: String?
    var btcAmount: Decimal?
    var usdAmount: Decimal?
    var btcPriceAtTransaction: Decimal?
    var feeAmount: Decimal?
    var billId: UUID?
}

struct ExportedBill: Codable {
    var id: UUID
    var name: String
    var amount: Decimal
    var dueDate: Date?
    var isPaid: Bool
    var paidDate: Date?
    var notes: String?
    var category: String?
    var autoPay: Bool
    var paymentCard: String?
    var recurrenceType: String?
    var recurrenceInterval: Int16
    var seriesId: UUID?
    var trackInBitcoin: Bool
    var accountId: UUID?
    var createdAt: Date?
    var updatedAt: Date?
}

struct ExportedPaycheck: Codable {
    var id: UUID
    var name: String
    var amount: Decimal
    var firstDepositDate: Date?
    var notes: String?
    var recurrenceType: String?
    var recurrenceInterval: Int16
    var autoReconcile: Bool
    var accountId: UUID?
    var createdAt: Date?
    var updatedAt: Date?
}

enum AccountExportService {
    static let currentVersion = 2

    static func makePayload(
        accounts: [Account],
        bills: [Bill] = [],
        paychecks: [Paycheck] = [],
        customCategories: [String] = [],
        creditCards: [String] = []
    ) -> AccountExportPayload {
        let exportedAccounts = accounts.map { account -> ExportedAccount in
            let entries = (account.ledgerEntries as? Set<LedgerEntry> ?? [])
                .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                .map { entry in
                    ExportedLedgerEntry(
                        id: entry.id ?? UUID(),
                        title: entry.title ?? "Transaction",
                        amount: entry.amountDecimal,
                        date: entry.date ?? Date(),
                        notes: entry.notes ?? "",
                        isCredit: entry.isCredit,
                        isReconciled: entry.isReconciledFlag,
                        category: entry.category,
                        entryType: entry.entryType,
                        btcAmount: entry.btcAmount?.decimalValue,
                        usdAmount: entry.usdAmount?.decimalValue,
                        btcPriceAtTransaction: entry.btcPriceAtTransaction?.decimalValue,
                        feeAmount: entry.feeAmount?.decimalValue,
                        billId: entry.bill?.id
                    )
                }
            return ExportedAccount(
                id: account.id ?? UUID(),
                name: account.name ?? "Account",
                type: account.type ?? "checking",
                startingBalance: account.startingBalanceDecimal,
                isHidden: account.isHiddenFlag,
                currency: account.currencyCode,
                btcDisplayFormat: account.btcDisplayFormat ?? "sats",
                feePercentage: account.feePercentageDecimal,
                order: account.order,
                reserveBalance: account.reserveBalanceDecimal,
                startingBalanceUSD: account.startingBalanceUSDDecimal,
                startingBalanceBTCPrice: account.startingBalanceBTCPriceDecimal,
                entries: entries
            )
        }

        let exportedBills = bills.map { bill in
            ExportedBill(
                id: bill.id ?? UUID(),
                name: bill.name ?? "Bill",
                amount: bill.amountDecimal,
                dueDate: bill.dueDate,
                isPaid: bill.isPaid,
                paidDate: bill.paidDate,
                notes: bill.notes,
                category: bill.category,
                autoPay: bill.autoPay,
                paymentCard: bill.paymentCard,
                recurrenceType: bill.recurrenceType,
                recurrenceInterval: bill.recurrenceInterval,
                seriesId: bill.seriesId,
                trackInBitcoin: bill.trackInBitcoinFlag,
                accountId: bill.account?.id,
                createdAt: bill.createdAt,
                updatedAt: bill.updatedAt
            )
        }

        let exportedPaychecks = paychecks.map { paycheck in
            ExportedPaycheck(
                id: paycheck.id ?? UUID(),
                name: paycheck.name ?? "Income",
                amount: paycheck.amount?.decimalValue ?? 0,
                firstDepositDate: paycheck.firstDepositDate,
                notes: paycheck.notes,
                recurrenceType: paycheck.recurrenceType,
                recurrenceInterval: paycheck.recurrenceInterval,
                autoReconcile: paycheck.autoReconcile,
                accountId: paycheck.account?.id,
                createdAt: paycheck.createdAt,
                updatedAt: paycheck.updatedAt
            )
        }

        return AccountExportPayload(
            version: currentVersion,
            exportedAt: Date(),
            accounts: exportedAccounts,
            bills: exportedBills,
            paychecks: exportedPaychecks,
            customCategories: customCategories,
            creditCards: creditCards
        )
    }

    static func jsonData(from payload: AccountExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func writeExportFile(
        accounts: [Account],
        bills: [Bill] = [],
        paychecks: [Paycheck] = [],
        customCategories: [String] = [],
        creditCards: [String] = []
    ) throws -> URL {
        guard !accounts.isEmpty || !bills.isEmpty || !paychecks.isEmpty else {
            throw AccountExportError.noAccounts
        }
        let payload = makePayload(
            accounts: accounts,
            bills: bills,
            paychecks: paychecks,
            customCategories: customCategories,
            creditCards: creditCards
        )
        let data = try jsonData(from: payload)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = "BillsAndBalance-Backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func csvString(from accounts: [Account]) -> String {
        var lines = [AccountCSVParser.headerLine]
        for account in accounts {
            let digits = account.currencyCode == "BTC" ? 8 : 2
            let row = [
                CSVSupport.escapeField(account.name ?? ""),
                CSVSupport.escapeField(account.type ?? "checking"),
                CSVSupport.formatDecimal(account.startingBalanceDecimal, fractionDigits: digits),
                CSVSupport.escapeField(account.currencyCode),
                CSVSupport.escapeField(account.btcDisplayFormat ?? "sats"),
                account.isHiddenFlag ? "Yes" : "No"
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    static func importFileData(_ data: Data, context: NSManagedObjectContext) throws -> Int {
        if let text = CSVSupport.string(from: data) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                let payload = try decodePayload(from: data)
                return try importPayload(payload, context: context)
            }
        }
        return try importCSV(data, context: context)
    }

    static func importCSV(_ data: Data, context: NSManagedObjectContext) throws -> Int {
        let rows: [ParsedAccountCSVRow]
        do {
            rows = try AccountCSVParser.parse(data: data)
        } catch let error as CSVParseError {
            switch error {
            case .missingRequiredColumns: throw AccountExportError.missingColumns
            case .emptyOrNoData: throw AccountExportError.noValidRows
            case .invalidEncoding: throw AccountExportError.decodeFailed
            }
        }

        var existing: [Account] = []
        let request = NSFetchRequest<Account>(entityName: "Account")
        existing = (try? context.fetch(request)) ?? []
        var nextOrder = (existing.map(\.order).max() ?? -1) + 1
        var applied = 0

        for row in rows {
            let account: Account
            if let match = existing.first(where: {
                ($0.name ?? "") == row.name && CSVSupport.normalizeAccountType($0.type ?? "") == row.type
            }) {
                account = match
            } else {
                account = Account(context: context)
                account.id = UUID()
                account.createdAt = Date()
                account.order = nextOrder
                nextOrder += 1
                existing.append(account)
            }

            account.name = row.name
            account.type = row.type
            account.startingBalance = NSDecimalNumber(decimal: row.startingBalance)
            account.isHiddenFlag = row.isHidden
            account.currencyCode = row.currency
            account.btcDisplayFormat = row.btcDisplayFormat
            account.updatedAt = Date()
            applied += 1
        }

        if context.hasChanges {
            try context.save()
        }
        return applied
    }

    static func decodePayload(from data: Data) throws -> AccountExportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(AccountExportPayload.self, from: data)
            guard payload.version >= 1 else { throw AccountExportError.invalidPayload }
            return payload
        } catch is DecodingError {
            throw AccountExportError.decodeFailed
        }
    }

    @discardableResult
    static func importPayload(_ payload: AccountExportPayload, context: NSManagedObjectContext) throws -> Int {
        var imported = 0
        var existing: [Account] = []
        let request = NSFetchRequest<Account>(entityName: "Account")
        existing = (try? context.fetch(request)) ?? []
        let existingIDs = Set(existing.compactMap(\.id))
        let existingNames = Set(existing.compactMap(\.name))
        var accountsByID: [UUID: Account] = Dictionary(
            uniqueKeysWithValues: existing.compactMap { account in
                guard let id = account.id else { return nil }
                return (id, account)
            }
        )

        for exported in payload.accounts {
            let account: Account
            if existingIDs.contains(exported.id),
               let match = existing.first(where: { $0.id == exported.id }) {
                account = match
            } else if existingNames.contains(exported.name),
                      let match = existing.first(where: { $0.name == exported.name }) {
                account = match
            } else {
                account = Account(context: context)
                account.id = exported.id
                account.createdAt = Date()
                imported += 1
            }

            account.name = exported.name
            account.type = exported.type
            account.startingBalance = NSDecimalNumber(decimal: exported.startingBalance)
            account.isHiddenFlag = exported.isHidden
            account.currencyCode = exported.currency
            account.btcDisplayFormat = exported.btcDisplayFormat
            account.feePercentageDecimal = exported.feePercentage
            account.order = exported.order
            if let reserve = exported.reserveBalance {
                account.reserveBalanceDecimal = reserve
            }
            if let usd = exported.startingBalanceUSD {
                account.startingBalanceUSD = NSDecimalNumber(decimal: usd)
            }
            if let price = exported.startingBalanceBTCPrice {
                account.startingBalanceBTCPrice = NSDecimalNumber(decimal: price)
            }
            account.updatedAt = Date()
            if let id = account.id {
                accountsByID[id] = account
            }

            let existingEntryIDs = Set((account.ledgerEntries as? Set<LedgerEntry> ?? []).compactMap(\.id))
            for exportedEntry in exported.entries where !existingEntryIDs.contains(exportedEntry.id) {
                let entry = LedgerEntry(context: context)
                entry.id = exportedEntry.id
                entry.title = exportedEntry.title
                entry.amount = NSDecimalNumber(decimal: exportedEntry.amount)
                entry.date = exportedEntry.date
                entry.notes = exportedEntry.notes
                entry.isCredit = exportedEntry.isCredit
                entry.isReconciledFlag = exportedEntry.isReconciled
                entry.category = exportedEntry.category
                entry.entryType = exportedEntry.entryType
                entry.createdAt = Date()
                if let btc = exportedEntry.btcAmount {
                    entry.btcAmount = NSDecimalNumber(decimal: btc)
                }
                if let usd = exportedEntry.usdAmount {
                    entry.usdAmount = NSDecimalNumber(decimal: usd)
                }
                if let price = exportedEntry.btcPriceAtTransaction {
                    entry.btcPriceAtTransaction = NSDecimalNumber(decimal: price)
                }
                if let fee = exportedEntry.feeAmount {
                    entry.feeAmount = NSDecimalNumber(decimal: fee)
                }
                entry.account = account
            }
        }

        var billsByID: [UUID: Bill] = [:]
        if let bills = payload.bills {
            let billRequest = NSFetchRequest<Bill>(entityName: "Bill")
            let existingBills = (try? context.fetch(billRequest)) ?? []
            let existingBillIDs = Set(existingBills.compactMap(\.id))

            for exported in bills {
                let bill: Bill
                if existingBillIDs.contains(exported.id),
                   let match = existingBills.first(where: { $0.id == exported.id }) {
                    bill = match
                } else {
                    bill = Bill(context: context)
                    bill.id = exported.id
                    bill.createdAt = exported.createdAt ?? Date()
                    imported += 1
                }
                bill.name = exported.name
                bill.amount = NSDecimalNumber(decimal: exported.amount)
                bill.dueDate = exported.dueDate
                bill.isPaid = exported.isPaid
                bill.paidDate = exported.paidDate
                bill.notes = exported.notes
                bill.category = exported.category
                bill.autoPay = exported.autoPay
                bill.paymentCard = exported.paymentCard
                bill.recurrenceType = exported.recurrenceType
                bill.recurrenceInterval = exported.recurrenceInterval
                bill.seriesId = exported.seriesId
                bill.trackInBitcoinFlag = exported.trackInBitcoin
                bill.updatedAt = exported.updatedAt ?? Date()
                if let accountId = exported.accountId {
                    bill.account = accountsByID[accountId]
                }
                billsByID[exported.id] = bill
            }
        }

        // Link ledger entries to bills after bills exist.
        for exported in payload.accounts {
            guard let account = accountsByID[exported.id] else { continue }
            let entries = account.ledgerEntries as? Set<LedgerEntry> ?? []
            for exportedEntry in exported.entries {
                guard let billId = exportedEntry.billId,
                      let bill = billsByID[billId],
                      let entry = entries.first(where: { $0.id == exportedEntry.id }) else { continue }
                entry.bill = bill
            }
        }

        if let paychecks = payload.paychecks {
            let paycheckRequest = NSFetchRequest<Paycheck>(entityName: "Paycheck")
            let existingPaychecks = (try? context.fetch(paycheckRequest)) ?? []
            let existingPaycheckIDs = Set(existingPaychecks.compactMap(\.id))

            for exported in paychecks {
                let paycheck: Paycheck
                if existingPaycheckIDs.contains(exported.id),
                   let match = existingPaychecks.first(where: { $0.id == exported.id }) {
                    paycheck = match
                } else {
                    paycheck = Paycheck(context: context)
                    paycheck.id = exported.id
                    paycheck.createdAt = exported.createdAt ?? Date()
                    imported += 1
                }
                paycheck.name = exported.name
                paycheck.amount = NSDecimalNumber(decimal: exported.amount)
                paycheck.firstDepositDate = exported.firstDepositDate
                paycheck.notes = exported.notes
                paycheck.recurrenceType = exported.recurrenceType
                paycheck.recurrenceInterval = exported.recurrenceInterval
                paycheck.autoReconcile = exported.autoReconcile
                paycheck.updatedAt = exported.updatedAt ?? Date()
                if let accountId = exported.accountId {
                    paycheck.account = accountsByID[accountId]
                }
            }
        }

        if let categories = payload.customCategories {
            UserDefaults.standard.set(categories, forKey: "customCategories")
        }
        if let cards = payload.creditCards {
            UserDefaults.standard.set(cards, forKey: "creditCardNames")
        }

        if context.hasChanges {
            try context.save()
        }
        return imported
    }
}
