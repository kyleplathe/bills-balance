import Foundation

enum CSVParseError: LocalizedError {
    case invalidEncoding
    case emptyOrNoData
    case missingRequiredColumns(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Could not read the CSV file."
        case .emptyOrNoData:
            return "CSV is empty or has no data rows."
        case .missingRequiredColumns(let columns):
            return "CSV is missing required columns (\(columns))."
        }
    }
}

enum CSVSupport {
    static func string(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        if let windows = String(data: data, encoding: .windowsCP1252) { return windows }
        return nil
    }

    /// Splits a CSV into header + data rows. Strips a UTF-8 BOM and ignores blank lines.
    static func table(from data: Data) throws -> (header: [String], rows: [[String]]) {
        guard let raw = string(from: data) else { throw CSVParseError.invalidEncoding }
        var text = raw
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard lines.count > 1 else { throw CSVParseError.emptyOrNoData }
        let header = parseLine(lines[0]).map(normalizeHeader)
        let rows = lines.dropFirst().map(parseLine)
        return (header, rows)
    }

    static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(trimField(current))
                current = ""
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }
        fields.append(trimField(current))
        return fields
    }

    static func trimField(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\u{FEFF}") {
            trimmed.removeFirst()
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed.replacingOccurrences(of: "\"\"", with: "\"")
    }

    static func normalizeHeader(_ value: String) -> String {
        trimField(value)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func index(in header: [String], names: [String]) -> Int? {
        let wanted = names.map(normalizeHeader)
        for name in wanted {
            if let match = header.firstIndex(of: name) { return match }
        }
        return nil
    }

    static func field(_ fields: [String], at index: Int?) -> String {
        guard let index, fields.indices.contains(index) else { return "" }
        return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses a date as a calendar day in `calendar`, ignoring any time or timezone suffix.
    /// `"2026-09-01"` and `"2026-09-01T00:00:00Z"` both become September 1 in the given calendar.
    static func parseCalendarDate(_ raw: String, calendar: Calendar = .current) -> Date? {
        let trimmed = trimField(raw)
        guard !trimmed.isEmpty else { return nil }

        if let ymd = extractYearMonthDay(from: trimmed) {
            return calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day))
        }

        let formats = [
            "M/d/yyyy", "MM/dd/yyyy",
            "M/d/yy", "MM/dd/yy",
            "d-MMM-yyyy", "dd-MMM-yyyy",
            "MMM d, yyyy", "MMMM d, yyyy",
            "d MMM yyyy", "dd MMM yyyy",
            "MMM dd yyyy HH:mm:ss", "MMM d yyyy HH:mm:ss",
            "MMM dd yyyy", "MMM d yyyy",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.calendar = calendar
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: trimmed) {
                let start = calendar.startOfDay(for: date)
                var parts = calendar.dateComponents([.year, .month, .day], from: start)
                if let year = parts.year, year < 100 {
                    parts.year = year < 70 ? 2000 + year : 1900 + year
                    return calendar.date(from: parts).map { calendar.startOfDay(for: $0) }
                }
                return start
            }
        }
        return nil
    }

    static func parseDecimal(_ raw: String) -> Decimal? {
        var cleaned = trimField(raw)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "BTC", with: "", options: .caseInsensitive)
        if cleaned.hasPrefix("("), cleaned.hasSuffix(")") {
            cleaned = "-" + cleaned.dropFirst().dropLast()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func parseYesNo(_ raw: String) -> Bool {
        switch trimField(raw).lowercased() {
        case "yes", "y", "true", "1", "hidden":
            return true
        default:
            return false
        }
    }

    static func escapeField(_ value: String) -> String {
        var field = value
        if field.contains("\"") {
            field = field.replacingOccurrences(of: "\"", with: "\"\"")
        }
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            return "\"\(field)\""
        }
        return field
    }

    static func formatDecimal(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func normalizeRecurrence(_ raw: String) -> String {
        let cleaned = trimField(raw)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch cleaned {
        case "", "none", "once", "one-time", "onetime":
            return "none"
        case "daily", "day":
            return "daily"
        case "weekly", "week":
            return "weekly"
        case "biweekly", "fortnightly":
            return "biweekly"
        case "monthly", "month":
            return "monthly"
        case "bimonthly":
            return "bimonthly"
        case "quarterly", "quarter":
            return "quarterly"
        case "semiannually", "semiannual", "biannually", "biannual":
            return "semiannually"
        case "yearly", "annually", "annual", "year":
            return "yearly"
        default:
            return cleaned.isEmpty ? "none" : cleaned
        }
    }

    static func normalizeAccountType(_ raw: String) -> String {
        let cleaned = trimField(raw).lowercased()
        switch cleaned {
        case "checking", "chequing", "bank":
            return "checking"
        case "savings", "saving":
            return "savings"
        case "credit", "credit card", "creditcard":
            return "credit"
        case "cash":
            return "cash"
        case "investment", "brokerage", "investments":
            return "investment"
        case "digital wallet", "wallet", "crypto", "bitcoin":
            return "digital wallet"
        default:
            return cleaned.isEmpty ? "checking" : cleaned
        }
    }

    /// Picks the best account name for a CSV value like "Strike Bus" → "Strike Business".
    static func bestAccountName(for raw: String, among names: [String]) -> String? {
        let needle = trimField(raw)
        guard !needle.isEmpty else { return nil }
        let needleLower = needle.lowercased()

        if let exact = names.first(where: { $0 == needle }) { return exact }
        if let exactCI = names.first(where: { $0.lowercased() == needleLower }) { return exactCI }

        var best: (name: String, score: Int)?
        for name in names {
            let lower = name.lowercased()
            let score: Int
            if lower.hasPrefix(needleLower) || needleLower.hasPrefix(lower) {
                score = 500 + min(lower.count, needleLower.count) - abs(lower.count - needleLower.count)
            } else if lower.contains(needleLower) || needleLower.contains(lower) {
                score = 100 + min(lower.count, needleLower.count)
            } else {
                continue
            }
            if best == nil || score > best!.score {
                best = (name, score)
            }
        }
        return best?.name
    }

    private static func extractYearMonthDay(from raw: String) -> (year: Int, month: Int, day: Int)? {
        let pattern = #"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges == 4,
              let yearRange = Range(match.range(at: 1), in: raw),
              let monthRange = Range(match.range(at: 2), in: raw),
              let dayRange = Range(match.range(at: 3), in: raw),
              let year = Int(raw[yearRange]),
              let month = Int(raw[monthRange]),
              let day = Int(raw[dayRange]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }
}

struct ParsedAccountCSVRow: Equatable {
    var name: String
    var type: String
    var startingBalance: Decimal
    var currency: String
    var btcDisplayFormat: String
    var isHidden: Bool
}

enum AccountCSVParser {
    static let headerLine = "Name,Type,Starting Balance,Currency,BTC Display Format,Is Hidden"

    static func parse(data: Data) throws -> [ParsedAccountCSVRow] {
        let table = try CSVSupport.table(from: data)
        guard let nameIndex = CSVSupport.index(in: table.header, names: ["name", "account", "account name"]),
              let balanceIndex = CSVSupport.index(in: table.header, names: ["starting balance", "balance", "current balance"])
        else {
            throw CSVParseError.missingRequiredColumns("Name, Starting Balance")
        }
        let typeIndex = CSVSupport.index(in: table.header, names: ["type", "account type"])
        let currencyIndex = CSVSupport.index(in: table.header, names: ["currency"])
        let formatIndex = CSVSupport.index(in: table.header, names: ["btc display format", "btc format", "display format"])
        let hiddenIndex = CSVSupport.index(in: table.header, names: ["is hidden", "hidden"])

        var rows: [ParsedAccountCSVRow] = []
        for fields in table.rows {
            let name = CSVSupport.field(fields, at: nameIndex)
            guard !name.isEmpty else { continue }
            guard let balance = CSVSupport.parseDecimal(CSVSupport.field(fields, at: balanceIndex)) else { continue }
            let type = CSVSupport.normalizeAccountType(CSVSupport.field(fields, at: typeIndex))
            let currencyRaw = CSVSupport.field(fields, at: currencyIndex).uppercased()
            let currency = currencyRaw.isEmpty ? "USD" : currencyRaw
            let formatRaw = CSVSupport.field(fields, at: formatIndex).lowercased()
            let format = formatRaw.isEmpty ? "sats" : formatRaw
            let hidden = CSVSupport.parseYesNo(CSVSupport.field(fields, at: hiddenIndex))
            rows.append(
                ParsedAccountCSVRow(
                    name: name,
                    type: type,
                    startingBalance: balance,
                    currency: currency,
                    btcDisplayFormat: format,
                    isHidden: hidden
                )
            )
        }
        guard !rows.isEmpty else { throw CSVParseError.emptyOrNoData }
        return rows
    }
}

struct ParsedBillCSVRow: Equatable {
    var name: String
    var amount: Decimal
    var dueDate: Date
    var recurrenceType: String
    var recurrenceInterval: Int
    var isPaid: Bool
    var paidDate: Date?
    var accountName: String?
    var autoPay: Bool
    var category: String?
    var notes: String
}

enum BillCSVParser {
    static func parse(data: Data, calendar: Calendar = .current) throws -> [ParsedBillCSVRow] {
        let table = try CSVSupport.table(from: data)
        guard let dateIndex = CSVSupport.index(in: table.header, names: ["due date", "duedate", "date"]),
              let nameIndex = CSVSupport.index(in: table.header, names: ["bill", "name", "payee"]),
              let amountIndex = CSVSupport.index(in: table.header, names: ["amount"])
        else {
            throw CSVParseError.missingRequiredColumns("Due Date, Bill/Name, Amount")
        }
        let recurrenceIndex = CSVSupport.index(in: table.header, names: ["recurrence", "recurrence type"])
        let intervalIndex = CSVSupport.index(in: table.header, names: ["recurrence interval", "interval"])
        let statusIndex = CSVSupport.index(in: table.header, names: ["status"])
        let paidDateIndex = CSVSupport.index(in: table.header, names: ["paid date", "paiddate"])
        let accountIndex = CSVSupport.index(in: table.header, names: ["account", "account name"])
        let autoPayIndex = CSVSupport.index(in: table.header, names: ["auto pay", "autopay"])
        let categoryIndex = CSVSupport.index(in: table.header, names: ["category"])
        let notesIndex = CSVSupport.index(in: table.header, names: ["notes"])

        var rows: [ParsedBillCSVRow] = []
        for fields in table.rows {
            let name = CSVSupport.field(fields, at: nameIndex)
            guard !name.isEmpty else { continue }
            guard let dueDate = CSVSupport.parseCalendarDate(CSVSupport.field(fields, at: dateIndex), calendar: calendar) else { continue }
            guard let amount = CSVSupport.parseDecimal(CSVSupport.field(fields, at: amountIndex)) else { continue }

            let recurrence = CSVSupport.normalizeRecurrence(CSVSupport.field(fields, at: recurrenceIndex))
            let intervalRaw = CSVSupport.field(fields, at: intervalIndex)
            let parsedInterval = Int(intervalRaw) ?? 0
            let interval = recurrence == "none" ? 0 : max(parsedInterval, 1)

            let status = CSVSupport.field(fields, at: statusIndex).lowercased()
            let isPaid = status == "paid" || status == "yes" || status == "true"
            let paidRaw = CSVSupport.field(fields, at: paidDateIndex)
            let paidDate = CSVSupport.parseCalendarDate(paidRaw, calendar: calendar)

            let accountName = CSVSupport.field(fields, at: accountIndex)
            let autoPay = CSVSupport.parseYesNo(CSVSupport.field(fields, at: autoPayIndex))
            let category = CSVSupport.field(fields, at: categoryIndex)
            let notes = CSVSupport.field(fields, at: notesIndex)

            rows.append(
                ParsedBillCSVRow(
                    name: name,
                    amount: amount,
                    dueDate: dueDate,
                    recurrenceType: recurrence,
                    recurrenceInterval: interval,
                    isPaid: isPaid,
                    paidDate: paidDate,
                    accountName: accountName.isEmpty ? nil : accountName,
                    autoPay: autoPay,
                    category: category.isEmpty ? nil : category,
                    notes: notes
                )
            )
        }
        guard !rows.isEmpty else { throw CSVParseError.emptyOrNoData }
        return rows
    }
}
