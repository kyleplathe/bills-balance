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
        case .invalidPayload: return "This file is not a Bills & Balance account export."
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
}

enum AccountExportService {
    static func makePayload(accounts: [Account]) -> AccountExportPayload {
        let exported = accounts.map { account -> ExportedAccount in
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
                        feeAmount: entry.feeAmount?.decimalValue
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
                entries: entries
            )
        }
        return AccountExportPayload(version: 1, exportedAt: Date(), accounts: exported)
    }

    static func jsonData(from payload: AccountExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func writeExportFile(accounts: [Account]) throws -> URL {
        guard !accounts.isEmpty else { throw AccountExportError.noAccounts }
        let payload = makePayload(accounts: accounts)
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
            account.updatedAt = Date()

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

        if context.hasChanges {
            try context.save()
        }
        return imported
    }
}
