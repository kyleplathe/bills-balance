import Foundation

enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking
    case savings
    case credit
    case cash
    case investment
    case digitalWallet = "digital_wallet"
}

enum RecurrenceType: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
}

enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case cleared
    case flagged
}

struct SupabaseAccount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String
    let accountType: AccountType
    let balance: Decimal
    let currency: String
    let btcSats: Int64
    let plaidAccessToken: String?
    let isHidden: Bool
    let createdAt: Date
    let updatedAt: Date
    let projectionDaysPref: Int
    let safetyBuffer: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case accountType = "type"
        case balance
        case currency
        case btcSats = "btc_sats"
        case plaidAccessToken = "plaid_access_token"
        case isHidden = "is_hidden"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectionDaysPref = "projection_days_pref"
        case safetyBuffer = "safety_buffer"
    }
}

struct SupabaseCategory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let iconName: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
    }
}

struct SupabaseBill: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String
    let amount: Decimal
    let dueDate: Date
    let recurrence: RecurrenceType
    let categoryID: UUID?
    let linkedAccountID: UUID?
    let isPaid: Bool
    let autoPay: Bool
    let seriesID: UUID?
    let btcValueAtPay: Decimal?
    let isVerified: Bool
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case amount
        case dueDate = "due_date"
        case recurrence
        case categoryID = "category_id"
        case linkedAccountID = "linked_account_id"
        case isPaid = "is_paid"
        case autoPay = "auto_pay"
        case seriesID = "series_id"
        case btcValueAtPay = "btc_value_at_pay"
        case isVerified = "is_verified"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SupabaseTransaction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let accountID: UUID?
    let billID: UUID?
    let amount: Decimal
    let description: String?
    let date: Date
    let status: TransactionStatus
    let isBTC: Bool
    let btcPriceAtTime: Decimal?
    let emailReferenceID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case accountID = "account_id"
        case billID = "bill_id"
        case amount
        case description
        case date
        case status
        case isBTC = "is_btc"
        case btcPriceAtTime = "btc_price_at_time"
        case emailReferenceID = "email_reference_id"
    }
}

