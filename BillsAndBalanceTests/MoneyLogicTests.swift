import XCTest
import CoreData
import SwiftUI
@testable import BillsAndBalance

final class RecurrenceCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMonthlyAdvancesByInterval() {
        let start = date(2026, 1, 15)
        let next = RecurrenceCalculator.nextDate(from: start, type: "monthly", interval: 1, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: next), 2)
        XCTAssertEqual(calendar.component(.day, from: next), 15)
    }

    func testBiweeklyIsTwoWeeks() {
        let start = date(2026, 1, 1)
        let next = RecurrenceCalculator.nextDate(from: start, type: "biweekly", interval: 1, calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: next).day
        XCTAssertEqual(days, 14)
    }

    func testQuarterlyIsThreeMonths() {
        let start = date(2026, 1, 10)
        let next = RecurrenceCalculator.nextDate(from: start, type: "quarterly", interval: 1, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: next), 4)
    }

    func testYearlySequence() {
        let start = date(2026, 3, 1)
        let dates = RecurrenceCalculator.dates(from: start, type: "yearly", interval: 1, count: 3, calendar: calendar)
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(calendar.component(.year, from: dates[2]), 2028)
    }

    func testUnknownTypeReturnsSameDate() {
        let start = date(2026, 5, 5)
        let next = RecurrenceCalculator.nextDate(from: start, type: "none", interval: 1, calendar: calendar)
        XCTAssertEqual(start, next)
    }

    func testPreviousMonthly() {
        let start = date(2026, 3, 15)
        let previous = RecurrenceCalculator.previousDate(from: start, type: "monthly", interval: 1, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: previous), 2)
        XCTAssertEqual(calendar.component(.day, from: previous), 15)
    }

    func testDatesGoingBack() {
        let start = date(2026, 4, 1)
        let end = date(2026, 1, 1)
        let dates = RecurrenceCalculator.datesGoingBack(from: start, through: end, type: "monthly", interval: 1, calendar: calendar)
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(calendar.component(.month, from: dates.last!), 1)
    }
}

final class MoneyFormattingTests: XCTestCase {
    func testParseUSDStripsCurrencyAndCommas() {
        XCTAssertEqual(MoneyFormatting.parse("$1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(MoneyFormatting.parse("1.2"), Decimal(string: "1.2"))
        XCTAssertNil(MoneyFormatting.parse(""))
        XCTAssertNil(MoneyFormatting.parse("   "))
        XCTAssertNil(MoneyFormatting.parse("abc"))
    }

    func testParseCollapsesExtraDecimals() {
        XCTAssertEqual(MoneyFormatting.parse("1.2.3"), Decimal(string: "1.23"))
    }

    func testFormatUSDTwoDecimalsWithGrouping() {
        XCTAssertEqual(MoneyFormatting.format(Decimal(string: "1234.5")!, kind: .usd), "1,234.50")
        XCTAssertEqual(MoneyFormatting.format(Decimal(10), kind: .usd, includeSymbol: true), "$10.00")
    }

    func testFormatForDisplay() {
        XCTAssertEqual(MoneyFormatting.formatForDisplay("1.2", kind: .usd), "1.20")
        XCTAssertEqual(MoneyFormatting.formatForDisplay("", kind: .usd), "")
        XCTAssertEqual(MoneyFormatting.formatForDisplay("1000", kind: .sats), "1,000")
    }

    func testParseSatsIgnoresDecimals() {
        XCTAssertEqual(MoneyFormatting.parse("1,000,000", kind: .sats), Decimal(1_000_000))
        XCTAssertEqual(MoneyFormatting.parse("12.3", kind: .sats), Decimal(123))
    }

    func testBTCFromSatsInput() {
        XCTAssertEqual(MoneyFormatting.btcAmount(fromInput: "100000000", displayFormat: "sats"), Decimal(1))
        XCTAssertEqual(MoneyFormatting.btcAmount(fromInput: "0.5", displayFormat: "bitcoin"), Decimal(string: "0.5"))
        XCTAssertNil(MoneyFormatting.btcAmount(fromInput: "", displayFormat: "sats"))
    }

    func testDisplayStringForBTC() {
        XCTAssertEqual(MoneyFormatting.displayString(forBTC: Decimal(1), displayFormat: "sats"), "100,000,000")
        XCTAssertEqual(MoneyFormatting.displayString(forBTC: Decimal(string: "0.5")!, displayFormat: "bitcoin"), "0.50")
    }
}

final class DuplicateBillGuardTests: XCTestCase {
    func testIdentityKeyStableForSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 20))!
        XCTAssertEqual(
            DuplicateBillGuard.identityKey(name: "Rent", date: morning, amount: 1500, calendar: calendar),
            DuplicateBillGuard.identityKey(name: "Rent", date: evening, amount: 1500, calendar: calendar)
        )
    }

    func testDetectsSeriesDuplicateOnSameDay() {
        let series = UUID()
        let due = Date()
        let existing = [(name: "Rent", amount: Decimal(1500), dueDate: due, seriesId: series)]
        XCTAssertTrue(
            DuplicateBillGuard.isDuplicate(name: "Rent", amount: 1500, dueDate: due, seriesId: series, existing: existing)
        )
    }

    func testAllowsDifferentDaySameName() {
        let calendar = Calendar.current
        let due = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: due)!
        let existing = [(name: "Rent", amount: Decimal(1500), dueDate: due, seriesId: UUID())]
        XCTAssertFalse(
            DuplicateBillGuard.isDuplicate(name: "Rent", amount: 1500, dueDate: nextMonth, seriesId: UUID(), existing: existing)
        )
    }

    func testAmountTolerance() {
        XCTAssertTrue(DuplicateBillGuard.amountsMatch(10.00, 10.004))
        XCTAssertFalse(DuplicateBillGuard.amountsMatch(10.00, 10.05))
    }
}

final class BalanceMathTests: XCTestCase {
    func testClearedAddsOnlyReconciledSignedAmounts() {
        let cleared = BalanceMath.cleared(startingBalance: 1000, reconciledSignedAmounts: [-50, 200, -25])
        XCTAssertEqual(cleared, Decimal(1125))
    }

    func testAvailableSubtractsBillsAndAddsIncome() {
        let available = BalanceMath.available(currentBalance: 2000, pendingBills: 800, pendingIncome: 300)
        XCTAssertEqual(available, Decimal(1500))
    }

    func testProjectionWindowIncludesStartExcludesEnd() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let inside = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        XCTAssertTrue(BalanceMath.isInProjectionWindow(inside, start: start, days: 30, calendar: calendar))
        XCTAssertFalse(BalanceMath.isInProjectionWindow(end, start: start, days: 30, calendar: calendar))
    }

    func testTotalVisibleExcludesHiddenAccounts() {
        let total = BalanceMath.totalVisible(amounts: [
            (amount: 1_000, isHidden: false),
            (amount: 500, isHidden: true),
            (amount: 250, isHidden: false)
        ])
        XCTAssertEqual(total, Decimal(1_250))
    }
}

final class RelativeDateFormatterTests: XCTestCase {
    func testTodayYesterdayTomorrow() {
        let calendar = Calendar.current
        let now = Date()
        XCTAssertEqual(RelativeDateFormatter.string(from: now, calendar: calendar, now: now), "Today")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(RelativeDateFormatter.string(from: yesterday, calendar: calendar, now: now), "Yesterday")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(RelativeDateFormatter.string(from: tomorrow, calendar: calendar, now: now), "Tomorrow")
    }
}

final class TransactionCSVParserTests: XCTestCase {
    func testParsesAmountColumnWithNegativeCredits() throws {
        let csv = """
        Date,Description,Amount
        01/15/2026,Coffee,4.50
        01/16/2026,Payroll,-1200.00
        """
        let txs = try TransactionCSVParser.parse(data: Data(csv.utf8))
        XCTAssertEqual(txs.count, 2)
        XCTAssertEqual(txs[0].title, "Coffee")
        XCTAssertEqual(txs[0].amount, Decimal(string: "4.50"))
        XCTAssertFalse(txs[0].isCredit)
        XCTAssertTrue(txs[1].isCredit)
        XCTAssertEqual(txs[1].amount, Decimal(1200))
    }

    func testParsesDebitCreditColumns() throws {
        let csv = """
        Date,Payee,Debit,Credit
        2026-02-01,Grocery,82.10,
        2026-02-02,Refund,,12.00
        """
        let txs = try TransactionCSVParser.parse(data: Data(csv.utf8))
        XCTAssertEqual(txs.count, 2)
        XCTAssertFalse(txs[0].isCredit)
        XCTAssertTrue(txs[1].isCredit)
    }

    func testQuotedCommaInDescription() throws {
        let csv = """
        Date,Description,Amount
        03/01/2026,"Store, Inc",-20.00
        """
        let txs = try TransactionCSVParser.parse(data: Data(csv.utf8))
        XCTAssertEqual(txs[0].title, "Store, Inc")
    }

    func testMissingColumnsThrows() {
        let csv = "Foo,Bar\n1,2\n"
        XCTAssertThrowsError(try TransactionCSVParser.parse(data: Data(csv.utf8)))
    }

    func testKeepsCategoryColumn() throws {
        let csv = """
        Date,Description,Amount,Category
        01/15/2026,Coffee,4.50,Dining
        """
        let txs = try TransactionCSVParser.parse(data: Data(csv.utf8))
        XCTAssertEqual(txs[0].category, "Dining")
    }
}

final class CSVSupportTests: XCTestCase {
    private var chicago: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }

    private func assertCalendarDay(_ raw: String, year: Int, month: Int, day: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let date = CSVSupport.parseCalendarDate(raw, calendar: chicago) else {
            return XCTFail("Expected to parse \(raw)", file: file, line: line)
        }
        let parts = chicago.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, year, file: file, line: line)
        XCTAssertEqual(parts.month, month, file: file, line: line)
        XCTAssertEqual(parts.day, day, file: file, line: line)
    }

    func testISODateStaysOnListedDayInUSTimeZone() {
        assertCalendarDay("2026-09-01", year: 2026, month: 9, day: 1)
        assertCalendarDay("2026-09-01T00:00:00Z", year: 2026, month: 9, day: 1)
        assertCalendarDay("2026-09-28 00:00:00", year: 2026, month: 9, day: 28)
        assertCalendarDay("9/1/2026", year: 2026, month: 9, day: 1)
        assertCalendarDay("9/28/26", year: 2026, month: 9, day: 28)
        assertCalendarDay("Jan 03 2025 06:10:15", year: 2025, month: 1, day: 3)
        assertCalendarDay("Jan 13 2025 07:38:38", year: 2025, month: 1, day: 13)
    }

    func testBOMAndCaseInsensitiveHeaders() throws {
        let csv = "\u{FEFF}Due Date,Bill,Amount\n2026-09-01,Mortgage,787.67\n"
        let rows = try BillCSVParser.parse(data: Data(csv.utf8), calendar: chicago)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Mortgage")
        XCTAssertEqual(rows[0].amount, Decimal(string: "787.67"))
        assertCalendarDay("2026-09-01", year: 2026, month: 9, day: 1)
        let parts = chicago.dateComponents([.year, .month, .day], from: rows[0].dueDate)
        XCTAssertEqual(parts.day, 1)
    }

    func testParsesUserExpenseSpreadsheet() throws {
        let csv = """
        Due Date,Bill,Amount,Recurrence,Recurrence Interval,Status,Paid Date,Account,Auto-Pay,Category,Notes
        2026-09-28,T-Mobile,66.15,monthly,1,Open,,Strike Bus,Yes,Utilities,
        2026-09-01,Mortgage,787.67,monthly,1,Open,,Strike,Yes,Housing,
        2026-09-01,CrowdHealth,62.10,monthly,1,Paid,2026-09-01,,Yes,Healthcare,
        2026-09-27,Chewy,57.19,weekly,5,Open,,,No,Dog,
        2026-09-28,Progressive Auto,300,semiannually,1,Open,,,Yes,Insurance,
        """
        let rows = try BillCSVParser.parse(data: Data(csv.utf8), calendar: chicago)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].name, "T-Mobile")
        XCTAssertEqual(chicago.component(.day, from: rows[0].dueDate), 28)
        XCTAssertEqual(rows[0].accountName, "Strike Bus")
        XCTAssertTrue(rows[0].autoPay)
        XCTAssertFalse(rows[0].isPaid)
        XCTAssertEqual(rows[2].isPaid, true)
        XCTAssertEqual(rows[3].recurrenceType, "weekly")
        XCTAssertEqual(rows[3].recurrenceInterval, 5)
        XCTAssertEqual(rows[4].recurrenceType, "semiannually")
    }

    func testParsesUserAccountSpreadsheet() throws {
        let csv = """
        Name,Type,Starting Balance,Currency,BTC Display Format,Is Hidden
        Strike,digital wallet,0.0173837,BTC,sats,No
        Blaze,checking,119.26,USD,sats,No
        Instakyle,checking,150.21,USD,sats,No
        Strike Business,digital wallet,0.03834302,BTC,sats,No
        Bitkey,digital wallet,0.25616007,BTC,sats,Yes
        Fidelity,investment,29846.48,USD,sats,Yes
         Savings,savings,0,USD,sats,Yes
        Venmo,cash,10,USD,sats,Yes
         Cash,digital wallet,20,USD,sats,Yes
        Blaze,savings,0,USD,sats,Yes
        """
        let rows = try AccountCSVParser.parse(data: Data(csv.utf8))
        XCTAssertEqual(rows.count, 10)
        XCTAssertEqual(rows[0].name, "Strike")
        XCTAssertEqual(rows[0].type, "digital wallet")
        XCTAssertEqual(rows[0].startingBalance, Decimal(string: "0.0173837"))
        XCTAssertEqual(rows[0].currency, "BTC")
        XCTAssertFalse(rows[0].isHidden)
        XCTAssertEqual(rows[4].name, "Bitkey")
        XCTAssertTrue(rows[4].isHidden)
        XCTAssertEqual(rows[6].name, " Savings")
        XCTAssertEqual(rows.filter { $0.name == "Blaze" }.count, 2)
        XCTAssertEqual(rows.first { $0.name == "Blaze" && $0.type == "checking" }?.startingBalance, Decimal(string: "119.26"))
        XCTAssertEqual(rows.first { $0.name == "Blaze" && $0.type == "savings" }?.isHidden, true)
    }

    func testStrikeBusMatchesStrikeBusiness() {
        let names = ["Strike", "Strike Business", "Instakyle"]
        XCTAssertEqual(CSVSupport.bestAccountName(for: "Strike Bus", among: names), "Strike Business")
        XCTAssertEqual(CSVSupport.bestAccountName(for: "Strike", among: names), "Strike")
        XCTAssertEqual(CSVSupport.bestAccountName(for: "instakyle", among: names), "Instakyle")
    }
}

final class FeeParsingTests: XCTestCase {
    func testParsesUSDFeeLine() {
        let notes = "Coffee\nFee: 6.36 USD (0.796%)"
        XCTAssertEqual(FeeParsing.feeFromNotes(notes), Decimal(string: "6.36"))
    }

    func testParsesStrikeFee() {
        XCTAssertEqual(FeeParsing.feeFromNotes("Strike fee: $1.25"), Decimal(string: "1.25"))
    }

    func testSumsMultipleFeeLines() {
        let notes = "Fee: 1.00 USD\nStrike fee: 2.00"
        XCTAssertEqual(FeeParsing.feeFromNotes(notes), Decimal(3))
    }

    func testNilNotesIsZero() {
        XCTAssertEqual(FeeParsing.feeFromNotes(nil), 0)
    }
}

@MainActor
final class RecurrenceCoreDataTests: XCTestCase {
    var persistence: PersistenceController!
    var billViewModel: BillViewModel!

    override func setUp() async throws {
        persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        billViewModel = BillViewModel(context: context)
    }

    func testAddBillRejectsSameNameDateAmount() {
        let due = Date()
        XCTAssertNotNil(billViewModel.addBill(name: "Netflix", amount: 15.99, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1))
        XCTAssertNil(billViewModel.addBill(name: "Netflix", amount: 15.99, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1))
    }

    func testPayingRecurringBillCreatesSingleNextOccurrence() throws {
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(name: "Rent", amount: 1500, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bill")
        }
        billViewModel.togglePaidStatus(for: bill)
        billViewModel.fetchBills()
        let rentBills = billViewModel.bills.filter { $0.name == "Rent" }
        XCTAssertEqual(rentBills.count, 2, "Paid bill plus exactly one next occurrence")
        billViewModel.togglePaidStatus(for: bill)
        billViewModel.togglePaidStatus(for: bill)
        billViewModel.fetchBills()
        let afterRetoggle = billViewModel.bills.filter { $0.name == "Rent" }
        XCTAssertEqual(afterRetoggle.count, 2, "Toggling paid twice must not create a third occurrence")
    }

    func testEnsureUpcomingRecreatesMissingNextMonth() throws {
        let calendar = Calendar.current
        let due = calendar.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(name: "HOA", amount: 365.84, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bill")
        }
        billViewModel.togglePaidStatus(for: bill)

        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "name == %@", "HOA")
        var all = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(all.count, 2)

        let next = all.first { !$0.isPaid && $0.objectID != bill.objectID }
        XCTAssertNotNil(next)
        if let next {
            billViewModel.deleteBill(next)
        }

        all = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(all.filter { !$0.isPaid }.count, 0)

        billViewModel.fetchBills()
        all = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(all.filter { !$0.isPaid }.count, 1, "Paid recurring bills must grow a next unpaid occurrence")
    }

    func testReconcilePaidPathCreatesNextOccurrence() throws {
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(name: "Mortgage", amount: 750.34, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bill")
        }

        billViewModel.markPaidPreservingLedger(for: bill)

        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "name == %@", "Mortgage")
        let all = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(bill.isPaid)
        XCTAssertEqual(all.count, 2, "Reconcile-paid recurring bills must still create the next month")
        XCTAssertEqual(all.filter { !$0.isPaid }.count, 1)
    }

    func testEnsureUpcomingCreatesNextWhenSeriesIdMissing() throws {
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(name: "HOA", amount: 365.84, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bill")
        }
        bill.isPaid = true
        bill.paidDate = Date()
        bill.seriesId = nil
        try persistence.container.viewContext.save()

        billViewModel.fetchBills()

        let request = NSFetchRequest<Bill>(entityName: "Bill")
        request.predicate = NSPredicate(format: "name == %@", "HOA")
        let all = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(all.filter { !$0.isPaid }.count, 1, "Paid recurring bills without a seriesId must still grow a next occurrence")
        XCTAssertNotNil(bill.seriesId)
    }
}

final class StrikeCSVParserTests: XCTestCase {
    private let strikeCSV = """
    Reference,Date & Time (UTC),Transaction Type,Amount USD,Fee USD,Amount BTC,Fee BTC,BTC Price,Cost Basis (USD),Description,Description
    59ced58f-w,Jan 03 2025 08:25:15,Withdrawal,-365.84,,,0,,,,"Bill pay to Condos at Lake H"
    59ced58f-s,Jan 03 2025 08:25:16,Sale,365.84,2.91,-0.00382928,,96297.48,,,"Bill pay to Condos at Lake H"
    1d9f1b6e-w,Jan 03 2025 06:15:23,Withdrawal,-750.34,,,0,,,,"Bill pay to Kyle D Plathe"
    1d9f1b6e-s,Jan 03 2025 08:11:44,Sale,750.34,5.97,-0.0078591,,96233.67,,,"Bill pay to Kyle D Plathe"
    dep-1,Jan 10 2025 12:00:00,Deposit,826.17,,,,,,,,
    buy-1,Jan 10 2025 12:00:01,Purchase,-826.17,6.48,0.0086,,96100,832.65,,
    sat-1,Jan 01 2025 00:00:01,Receive,0.00,,0.00000001,,,,lnbc10n1,Satogram: Happy New Year
    """

    func testDetectsStrikeHeader() {
        XCTAssertTrue(StrikeCSVParser.isStrikeCSV(Data(strikeCSV.utf8)))
        XCTAssertFalse(StrikeCSVParser.isStrikeCSV(Data("Date,Description,Amount\n01/01/2026,Coffee,4.50\n".utf8)))
    }

    func testPairsBillPayWithdrawalAndSale() throws {
        let txs = try TransactionCSVParser.parse(data: Data(strikeCSV.utf8))
        let billPays = txs.filter { $0.kind == .billPay }
        XCTAssertEqual(billPays.count, 2)

        let hoa = try XCTUnwrap(billPays.first { $0.title.contains("Condos") })
        XCTAssertEqual(hoa.amount, Decimal(string: "365.84"))
        XCTAssertEqual(hoa.feeUSD, Decimal(string: "2.91"))
        XCTAssertEqual(hoa.btcAmount, Decimal(string: "0.00382928"))
        XCTAssertEqual(hoa.btcPrice, Decimal(string: "96297.48"))
        XCTAssertFalse(hoa.isCredit)

        let mortgage = try XCTUnwrap(billPays.first { $0.title.contains("Kyle") })
        XCTAssertEqual(mortgage.amount, Decimal(string: "750.34"))
        XCTAssertEqual(mortgage.feeUSD, Decimal(string: "5.97"))
        XCTAssertEqual(mortgage.btcAmount, Decimal(string: "0.0078591"))
    }

    func testDoesNotImportPairedSaleTwice() throws {
        let txs = try TransactionCSVParser.parse(data: Data(strikeCSV.utf8))
        XCTAssertEqual(txs.filter { $0.kind == .sale }.count, 0)
        XCTAssertEqual(txs.filter { $0.kind == .purchase }.count, 1)
        XCTAssertEqual(txs.filter { $0.kind == .deposit }.count, 1)
        XCTAssertEqual(txs.filter { $0.kind == .receive }.count, 1)
    }

    func testPayeeExtractionAndNotes() {
        XCTAssertEqual(StrikeCSVParser.payeeName(from: "Bill pay to Condos at Lake H"), "Condos at Lake H")
        let notes = StrikeCSVParser.notes(payee: "Condos at Lake H", feeUSD: Decimal(string: "2.91"), reference: "59ced58f-s")
        XCTAssertTrue(notes.contains("Strike fee: $2.91"))
        XCTAssertEqual(StrikeCSVParser.reference(from: notes), "59ced58f-s")
    }

    func testBillPayNameScore() {
        XCTAssertGreaterThan(BillPayMatcher.nameScore(payee: "Condos at Lake H", billName: "Condos at Lake H"), 90)
        XCTAssertGreaterThan(BillPayMatcher.nameScore(payee: "XCEL ENERGY-MN", billName: "Xcel Energy"), 0)
        XCTAssertEqual(BillPayMatcher.nameScore(payee: "Condos at Lake H", billName: "Mortgage"), 0)
    }
}

@MainActor
final class AccountCSVImportTests: XCTestCase {
    func testTwoBlazeAccountsStaySeparate() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let csv = """
        Name,Type,Starting Balance,Currency,BTC Display Format,Is Hidden
        Blaze,checking,119.26,USD,sats,No
        Blaze,savings,0,USD,sats,Yes
        Strike,digital wallet,0.0173837,BTC,sats,No
        """
        let count = try AccountExportService.importCSV(Data(csv.utf8), context: context)
        XCTAssertEqual(count, 3)
        let request = NSFetchRequest<Account>(entityName: "Account")
        let accounts = try context.fetch(request)
        XCTAssertEqual(accounts.count, 3)
        let blaze = accounts.filter { $0.name == "Blaze" }
        XCTAssertEqual(blaze.count, 2)
        XCTAssertEqual(blaze.first { $0.type == "checking" }?.startingBalanceDecimal, Decimal(string: "119.26"))
        XCTAssertEqual(blaze.first { $0.type == "savings" }?.isHiddenFlag, true)
        XCTAssertEqual(accounts.first { $0.name == "Strike" }?.currencyCode, "BTC")
    }
}

final class CoinGeckoPriceParserTests: XCTestCase {
    func testParsesIntegerUSDPrice() throws {
        let data = Data(#"{"bitcoin":{"usd":77226}}"#.utf8)
        let price = try CoinGeckoPriceParser.parseUSD(from: data)
        XCTAssertEqual(price, Decimal(77226))
    }

    func testParsesFractionalUSDPrice() throws {
        let data = Data(#"{"bitcoin":{"usd":77226.48}}"#.utf8)
        let price = try CoinGeckoPriceParser.parseUSD(from: data)
        XCTAssertEqual((price as NSDecimalNumber).doubleValue, 77226.48, accuracy: 0.01)
    }

    func testRejectsErrorPayload() {
        let data = Data(#"{"status":{"error_code":429,"error_message":"rate limited"}}"#.utf8)
        XCTAssertThrowsError(try CoinGeckoPriceParser.parseUSD(from: data))
    }

    func testRejectsMissingBitcoinKey() {
        let data = Data(#"{"ethereum":{"usd":1}}"#.utf8)
        XCTAssertThrowsError(try CoinGeckoPriceParser.parseUSD(from: data))
    }
}

final class StatementImportMatchingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testStartingBalanceDeltaNegatesInsertedNet() {
        XCTAssertEqual(StatementImportMatching.startingBalanceDelta(keepingCurrentBalance: Decimal(-500)), Decimal(500))
        XCTAssertEqual(StatementImportMatching.startingBalanceDelta(keepingCurrentBalance: Decimal(1200)), Decimal(-1200))
    }

    func testBTCKeepBalanceIgnoresUSDOnlyRows() {
        let billPay = ParsedStatementTransaction(
            date: date(2025, 1, 3),
            title: "Condos",
            amount: Decimal(string: "365.84")!,
            isCredit: false,
            btcAmount: Decimal(string: "0.00382928"),
            kind: .billPay
        )
        let usdOnly = ParsedStatementTransaction(
            date: date(2025, 1, 3),
            title: "Deposit",
            amount: Decimal(1000),
            isCredit: true,
            kind: .deposit
        )
        let net = StatementImportMatching.keepBalanceNetSigned(
            transactions: [billPay, usdOnly],
            bitcoinAccount: true,
            isCredit: { !$0.isCredit ? false : true }
        )
        XCTAssertEqual(net, Decimal(string: "-0.00382928"))
    }

    func testClearBalanceUsesLegacyWhenUSDMixedIntoBTC() {
        let usdOnlyDebit = ParsedStatementTransaction(
            date: date(2025, 1, 3),
            title: "Bill pay",
            amount: Decimal(string: "750.34")!,
            isCredit: false,
            kind: .billPay
        )
        let net = StatementImportMatching.netSignedForClearingBalanceAdjustment(
            transactions: [usdOnlyDebit],
            bitcoinAccount: true,
            isCredit: { _ in false }
        )
        XCTAssertEqual(net, Decimal(string: "-750.34"))
    }

    func testDuplicateSameDayTitleAndAmount() {
        let existing = [
            StatementImportMatching.ExistingEntry(
                date: date(2025, 3, 1),
                amount: 42.10,
                title: "STARBUCKS #123",
                isCredit: false,
                sourceReference: nil
            )
        ]
        let tx = ParsedStatementTransaction(date: date(2025, 3, 1), title: "Starbucks 123", amount: Decimal(string: "42.10")!, isCredit: false)
        XCTAssertNotNil(StatementImportMatching.matchingIndex(for: tx, in: existing, used: [], calendar: calendar))
    }

    func testDoesNotMatchDifferentTitleSameAmount() {
        let existing = [
            StatementImportMatching.ExistingEntry(
                date: date(2025, 3, 1),
                amount: 9.99,
                title: "Netflix",
                isCredit: false,
                sourceReference: nil
            )
        ]
        let tx = ParsedStatementTransaction(date: date(2025, 3, 1), title: "Spotify", amount: Decimal(string: "9.99")!, isCredit: false)
        XCTAssertNil(StatementImportMatching.matchingIndex(for: tx, in: existing, used: [], calendar: calendar))
    }

    func testPrefersCreditAccountFromFilename() {
        XCTAssertTrue(StatementImportMatching.prefersCreditAccount(fileName: "Chase_Sapphire_credit_2025.csv"))
        XCTAssertTrue(StatementImportMatching.prefersCreditAccount(fileName: "amex-activity.csv"))
        XCTAssertFalse(StatementImportMatching.prefersCreditAccount(fileName: "checking-2025.csv"))
    }

    func testStrikeReferenceMatch() {
        let existing = [
            StatementImportMatching.ExistingEntry(
                date: date(2025, 6, 1),
                amount: 1500,
                title: "Rent",
                isCredit: false,
                sourceReference: "abc-123"
            )
        ]
        var tx = ParsedStatementTransaction(date: date(2025, 6, 20), title: "Other", amount: 1, isCredit: true)
        tx.sourceReference = "abc-123"
        XCTAssertEqual(StatementImportMatching.matchingIndex(for: tx, in: existing, used: [], calendar: calendar), 0)
    }
}

final class ActivityLedgerRulesTests: XCTestCase {
    func testCreditPurchasesCountAndPaymentsDoNot() {
        XCTAssertTrue(ActivityLedgerRules.includeInTotals(accountType: "credit", isCredit: false, title: "Grocery", cardNames: ["Chase"]))
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(accountType: "credit", isCredit: true, title: "Payment Thank You", cardNames: ["Chase"]))
    }

    func testBankCardPaymentIsExcludedFromTotals() {
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(
            accountType: "checking",
            isCredit: false,
            title: "CHASE CREDIT CRD EPAY",
            cardNames: ["Chase"]
        ))
        XCTAssertTrue(ActivityLedgerRules.includeInTotals(
            accountType: "checking",
            isCredit: false,
            title: "Rent",
            cardNames: ["Chase"]
        ))
    }

    func testInAppTransfersAreExcludedFromTotals() {
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(
            accountType: "checking",
            isCredit: false,
            title: "Transfer to Savings",
            cardNames: [],
            category: "Transfer"
        ))
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(
            accountType: "savings",
            isCredit: true,
            title: "Transfer from Checking",
            cardNames: [],
            category: "Transfer"
        ))
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(
            accountType: "checking",
            isCredit: false,
            title: "Payment to Chase",
            cardNames: ["Chase"],
            category: "Transfer"
        ))
    }
}

final class LedgerTransferTests: XCTestCase {
    func testPairIdRoundTrip() {
        let pairId = UUID()
        let notes = LedgerTransfer.appendingPairId(to: "Moved for rent", pairId: pairId)
        XCTAssertEqual(LedgerTransfer.pairId(from: notes), pairId)
        XCTAssertTrue(notes.contains("Moved for rent"))
    }

    func testDoesNotDuplicatePairMarker() {
        let pairId = UUID()
        let once = LedgerTransfer.appendingPairId(to: nil, pairId: pairId)
        let twice = LedgerTransfer.appendingPairId(to: once, pairId: UUID())
        XCTAssertEqual(LedgerTransfer.pairId(from: twice), pairId)
    }

    func testTitlesForAssetAndCreditAccounts() {
        XCTAssertEqual(LedgerTransfer.debitTitle(toAccountName: "Savings", toIsCreditAccount: false), "Transfer to Savings")
        XCTAssertEqual(LedgerTransfer.creditTitle(fromAccountName: "Checking", fromIsCreditAccount: false), "Transfer from Checking")
        XCTAssertEqual(LedgerTransfer.debitTitle(toAccountName: "Chase", toIsCreditAccount: true), "Payment to Chase")
        XCTAssertEqual(LedgerTransfer.creditTitle(fromAccountName: "Chase", fromIsCreditAccount: true), "Payment from Chase")
    }
}

final class BillBtcBacktestTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testClampsDueDayInShortMonth() {
        let feb = calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!
        let due = BillBtcBacktest.dueDate(inMonth: feb, day: 31, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: due), 28)
    }

    func testEstimateUsesHistoricalPrice() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 1500, dueDay: 1, seriesId: nil, category: "Housing")
        let result = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: Date(),
            actual: nil,
            historicalPrice: 50_000,
            currentPrice: 100_000
        )
        XCTAssertEqual(result?.isEstimate, true)
        XCTAssertEqual(result?.btc, Decimal(1500) / Decimal(50_000))
    }

    func testActualPrefersStoredBTC() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 1500, dueDay: 1, seriesId: nil, category: nil)
        let actual = BillBtcBacktest.LedgerCandidate(
            date: Date(),
            title: "Rent",
            usd: 1500,
            btc: Decimal(string: "0.02"),
            price: 75_000,
            billName: "Rent",
            billSeriesId: nil,
            category: nil
        )
        let result = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: Date(),
            actual: actual,
            historicalPrice: 50_000,
            currentPrice: 100_000
        )
        XCTAssertEqual(result?.isEstimate, false)
        XCTAssertEqual(result?.btc, Decimal(string: "0.02"))
        XCTAssertEqual(result?.price, 75_000)
    }

    func testDetectsDollarBillPaidInSats() {
        XCTAssertTrue(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: false, usdAmount: 1500, btcAmount: Decimal(string: "0.02")!))
        XCTAssertFalse(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: false, usdAmount: 1500, btcAmount: 0))
        XCTAssertFalse(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: true, usdAmount: 1500, btcAmount: Decimal(string: "0.02")!))
    }

    func testTemplatesAutoIncludeSeriesPaidInBitcoin() {
        let series = UUID()
        let paid = BillBtcBacktest.BillSource(
            groupingKey: series.uuidString,
            name: "Rent",
            amount: 1400,
            dueDate: calendar.date(from: DateComponents(year: 2025, month: 6, day: 1)),
            seriesId: series,
            category: "Housing",
            trackInBitcoin: false,
            paidInBitcoin: true
        )
        let current = BillBtcBacktest.BillSource(
            groupingKey: series.uuidString,
            name: "Rent",
            amount: 1550,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)),
            seriesId: series,
            category: "Housing",
            trackInBitcoin: false,
            paidInBitcoin: false
        )
        let ignored = BillBtcBacktest.BillSource(
            groupingKey: UUID().uuidString,
            name: "Netflix",
            amount: 15,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)),
            seriesId: nil,
            category: "Subscriptions",
            trackInBitcoin: false,
            paidInBitcoin: false
        )
        let templates = BillBtcBacktest.templates(from: [paid, current, ignored], calendar: calendar)
        XCTAssertEqual(templates.map(\.name), ["Rent"])
        XCTAssertEqual(templates.first?.amount, 1550)
        XCTAssertEqual(templates.first?.dueDay, 1)
    }

    func testShareTitleUsesBillName() {
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Mortgage"]), "Mortgage USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Rent", "Xcel"]), "Rent & Xcel USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Rent", "Xcel", "Internet"]), "Bills USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareHeadlineName(from: "Mortgage USD vs BTC"), "Mortgage")
    }

    func testBitcoinSpendChangeShowsLessOverTime() {
        let early = Array(repeating: Decimal(string: "0.04")!, count: 12)
        let late = Array(repeating: Decimal(string: "0.01")!, count: 12)
        let change = BillBtcBacktest.bitcoinSpendChange(btcAmounts: early + late, monthCount: 48)
        XCTAssertEqual(change?.percentLess, Decimal(string: "0.75"))
        XCTAssertEqual(change?.years, 4)
    }

    func testMatchesByNameInMonth() {
        let template = BillBtcBacktest.Template(name: "Xcel Energy", amount: 120, dueDay: 15, seriesId: nil, category: "Utilities")
        let monthStart = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let monthEnd = calendar.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        let candidates = [
            BillBtcBacktest.LedgerCandidate(
                date: calendar.date(from: DateComponents(year: 2025, month: 6, day: 16))!,
                title: "XCEL ENERGY",
                usd: 118,
                btc: nil,
                price: nil,
                billName: nil,
                billSeriesId: nil,
                category: "Utilities"
            )
        ]
        XCTAssertEqual(
            BillBtcBacktest.matchingIndex(
                template: template,
                in: candidates,
                used: [],
                monthStart: monthStart,
                monthEnd: monthEnd,
                calendar: calendar
            ),
            0
        )
    }
}

final class CoinGeckoMarketChartParserTests: XCTestCase {
    func testParsesDailyPrices() throws {
        let data = Data(#"{"prices":[[1577836800000,7194.89],[1577923200000,7197.21]]}"#.utf8)
        let rows = try CoinGeckoMarketChartParser.parse(from: data)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual((rows[0].1 as NSDecimalNumber).doubleValue, 7194.89, accuracy: 0.01)
    }
}

@MainActor
final class AccountTransferTests: XCTestCase {
    var persistence: PersistenceController!
    var viewModel: AccountViewModel!

    override func setUp() async throws {
        persistence = PersistenceController(inMemory: true)
        viewModel = AccountViewModel(context: persistence.container.viewContext)
    }

    private func makeAccount(name: String, type: String, starting: Decimal, currency: String = "USD") -> Account {
        viewModel.addAccount(name: name, type: type, startingBalance: starting, currency: currency)
    }

    func testUSDTransferMovesBalancesAndSkipsActivity() throws {
        let checking = makeAccount(name: "Checking", type: "checking", starting: 1000)
        let savings = makeAccount(name: "Savings", type: "savings", starting: 200)
        let pair = try XCTUnwrap(viewModel.transfer(from: checking, to: savings, usdAmount: 150, isCleared: true))

        XCTAssertEqual(viewModel.totalBalance(for: checking), Decimal(850))
        XCTAssertEqual(viewModel.totalBalance(for: savings), Decimal(350))
        XCTAssertFalse(pair.from.isCredit)
        XCTAssertTrue(pair.to.isCredit)
        XCTAssertEqual(pair.from.category, LedgerTransfer.category)
        XCTAssertEqual(LedgerTransfer.pairId(from: pair.from.notes), LedgerTransfer.pairId(from: pair.to.notes))
        XCTAssertFalse(ActivityLedgerRules.includeInTotals(
            accountType: checking.type,
            isCredit: pair.from.isCredit,
            title: pair.from.title ?? "",
            cardNames: [],
            category: pair.from.category
        ))
    }

    func testFeeStaysOnSource() throws {
        let checking = makeAccount(name: "Checking", type: "checking", starting: 1000)
        let savings = makeAccount(name: "Savings", type: "savings", starting: 0)
        _ = try XCTUnwrap(viewModel.transfer(from: checking, to: savings, usdAmount: 100, feeAmount: 2, isCleared: true))

        XCTAssertEqual(viewModel.totalBalance(for: checking), Decimal(898))
        XCTAssertEqual(viewModel.totalBalance(for: savings), Decimal(100))
    }

    func testCreditCardPaymentTitles() throws {
        let checking = makeAccount(name: "Checking", type: "checking", starting: 500)
        let card = makeAccount(name: "Chase", type: "credit", starting: -200)
        let pair = try XCTUnwrap(viewModel.transfer(from: checking, to: card, usdAmount: 50, isCleared: true))

        XCTAssertEqual(pair.from.title, "Payment to Chase")
        XCTAssertEqual(pair.to.title, "Transfer from Checking")
        XCTAssertEqual(viewModel.totalBalance(for: card), Decimal(-150))
    }

    func testDeletingOneSideRemovesThePair() throws {
        let checking = makeAccount(name: "Checking", type: "checking", starting: 1000)
        let savings = makeAccount(name: "Savings", type: "savings", starting: 0)
        let pair = try XCTUnwrap(viewModel.transfer(from: checking, to: savings, usdAmount: 80, isCleared: true))

        viewModel.deleteLedgerEntry(pair.from)

        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        let remaining = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(viewModel.totalBalance(for: checking), Decimal(1000))
        XCTAssertEqual(viewModel.totalBalance(for: savings), Decimal(0))
    }

    func testSameAccountTransferIsRejected() {
        let checking = makeAccount(name: "Checking", type: "checking", starting: 100)
        XCTAssertNil(viewModel.transfer(from: checking, to: checking, usdAmount: 25))
        XCTAssertEqual(viewModel.totalBalance(for: checking), Decimal(100))
    }

    func testClearImportedEntriesRestoresBTCStartingBalance() {
        let strike = makeAccount(name: "Strike", type: "digital", starting: Decimal(string: "0.5")!, currency: "BTC")
        let spentBTC = Decimal(string: "0.12")!
        _ = viewModel.addManualEntry(
            to: strike,
            title: "Bill pay",
            btcAmount: -spentBTC,
            usdAmount: Decimal(-900),
            btcPriceAtTransaction: Decimal(75000),
            date: Date(),
            notes: "Bill pay to Rent\n\(StrikeCSVParser.referenceNotePrefix) abc123",
            isReconciled: true,
            isCreditOverride: false
        )
        let net = -spentBTC
        viewModel.applyStartingBalanceOffset(
            to: strike,
            delta: StatementImportMatching.startingBalanceDelta(keepingCurrentBalance: net)
        )
        viewModel.saveContext()

        XCTAssertEqual(viewModel.clearedBalance(for: strike), Decimal(string: "0.5"))
        XCTAssertEqual(strike.startingBalanceDecimal, Decimal(string: "0.62"))

        let removed = viewModel.clearImportedEntries()
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(strike.startingBalanceDecimal, Decimal(string: "0.5"))
        XCTAssertEqual(viewModel.clearedBalance(for: strike), Decimal(string: "0.5"))
    }
}

final class CategoryStyleTests: XCTestCase {
    func testDefaultColorsAreStableByNameNotRank() {
        XCTAssertEqual(CategoryStyle.color(for: "Housing"), CategoryStyle.color(for: "housing"))
        XCTAssertEqual(CategoryStyle.color(for: "Food & Dining"), CategoryStyle.color(for: "food & dining"))
        XCTAssertNotEqual(CategoryStyle.color(for: "Housing"), CategoryStyle.color(for: "Food & Dining"))
    }

    func testCustomColorsAreStable() {
        XCTAssertEqual(CategoryStyle.color(for: "Dog Walking"), CategoryStyle.color(for: "dog walking"))
        XCTAssertEqual(CategoryStyle.icon(for: "Housing"), "house")
        XCTAssertEqual(CategoryStyle.icon(for: "Digital Wallet Fees"), "bitcoinsign.circle.fill")
    }

    func testCompactGradientUsesTopCategories() {
        let gradient = CategoryStyle.compactGradient(categories: [
            ("Housing", 300),
            ("Food & Dining", 100),
            ("Shopping", 20)
        ])
        XCTAssertNotNil(gradient)
    }

    func testAppleCardSpectrumIsChartMapped() {
        XCTAssertNotNil(CategoryStyle.appleCardSpectrum)
    }
}

final class CategorySuggesterTests: XCTestCase {
    func testHistoryBeatsKeywords() {
        let suggested = CategorySuggester.suggest(for: "Netflix", priorCategory: "Entertainment")
        XCTAssertEqual(suggested, "Entertainment")
    }

    func testMerchantKeywords() {
        XCTAssertEqual(CategorySuggester.suggest(for: "Netflix"), "Subscriptions")
        XCTAssertEqual(CategorySuggester.suggest(for: "Chevron"), "Transportation")
        XCTAssertEqual(CategorySuggester.suggest(for: "Rent"), "Housing")
        XCTAssertEqual(CategorySuggester.suggest(for: "Xcel Energy"), "")
    }

    func testAmbiguousWordsDoNotForceACategory() {
        XCTAssertEqual(CategorySuggester.suggest(for: "Monthly payment"), "")
        XCTAssertEqual(CategorySuggester.suggest(for: "Apple"), "")
    }
}

final class NotificationScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testManualBillRemindsMorningBeforeDue() {
        let due = date(2026, 9, 10, hour: 18)
        let now = date(2026, 9, 1)
        let reminder = NotificationSchedule.reminderDate(dueDate: due, autoPay: false, now: now, calendar: calendar)
        XCTAssertNotNil(reminder)
        XCTAssertEqual(calendar.component(.day, from: reminder!), 9)
        XCTAssertEqual(calendar.component(.hour, from: reminder!), 9)
    }

    func testAutoPayRemindsMorningOfDue() {
        let due = date(2026, 9, 10, hour: 18)
        let now = date(2026, 9, 1)
        let reminder = NotificationSchedule.reminderDate(dueDate: due, autoPay: true, now: now, calendar: calendar)
        XCTAssertNotNil(reminder)
        XCTAssertEqual(calendar.component(.day, from: reminder!), 10)
        XCTAssertEqual(calendar.component(.hour, from: reminder!), 9)
    }

    func testPastDueDoesNotSchedule() {
        let due = date(2026, 8, 1)
        let now = date(2026, 9, 6)
        XCTAssertNil(NotificationSchedule.reminderDate(dueDate: due, autoPay: false, now: now, calendar: calendar))
        XCTAssertNil(NotificationSchedule.reminderDate(dueDate: due, autoPay: true, now: now, calendar: calendar))
    }
}

