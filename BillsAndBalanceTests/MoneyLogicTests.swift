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

    func testSpendableExcludesPendingIncomeKeepsPendingOutflows() {
        XCTAssertEqual(BalanceMath.spendable(currentBalance: 1500, pendingIncome: 500), Decimal(1000))
        XCTAssertEqual(BalanceMath.spendable(currentBalance: 950, pendingIncome: 0), Decimal(950))
        XCTAssertEqual(BalanceMath.spendable(currentBalance: 1450, pendingIncome: 500), Decimal(950))
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
        AutoPaySkipStore.resetForTests()
        persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        billViewModel = BillViewModel(context: context)
    }

    override func tearDown() async throws {
        AutoPaySkipStore.resetForTests()
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

    func testBillPayMatchesUniqueAmountWhenPayeeNameDiffers() {
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(name: "Mortgage", amount: 2150, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bill")
        }
        let matched = BillPayMatcher.match(payee: "Kyle Plathe", amount: 2150, on: due, among: [bill])
        XCTAssertEqual(matched?.objectID, bill.objectID)
    }

    func testBillPayDoesNotGuessWhenTwoBillsShareAmount() {
        let due = Calendar.current.startOfDay(for: Date())
        guard let mortgage = billViewModel.addBill(name: "Mortgage", amount: 2150, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1),
              let hoa = billViewModel.addBill(name: "HOA", amount: 2150, dueDate: due, recurrenceType: "monthly", recurrenceInterval: 1) else {
            return XCTFail("Expected bills")
        }
        XCTAssertNil(BillPayMatcher.match(
            payee: "Kyle Plathe",
            amount: 2150,
            on: due,
            among: [mortgage, hoa]
        ))
    }

    func testUnmarkingAutoPayBillRecordsSkipForThisDueDate() throws {
        let context = persistence.container.viewContext
        let accountVM = AccountViewModel(context: context)
        billViewModel.attachAccountViewModel(accountVM)
        let account = accountVM.addAccount(name: "Checking", type: "checking", startingBalance: 5_000)
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(
            name: "Cursor",
            amount: 20,
            dueDate: due,
            recurrenceType: "none",
            autoPay: true,
            account: account
        ) else {
            return XCTFail("Expected bill")
        }
        bill.isPaid = true
        bill.paidDate = Date()
        try context.save()

        billViewModel.togglePaidStatus(for: bill)
        XCTAssertFalse(bill.isPaid)
        XCTAssertTrue(AutoPaySkipStore.isSkipped(billId: bill.id, dueDate: due))
    }

    func testSkippedAutoPayBillStaysUnpaidOnFetch() throws {
        let context = persistence.container.viewContext
        let accountVM = AccountViewModel(context: context)
        billViewModel.attachAccountViewModel(accountVM)
        let account = accountVM.addAccount(name: "Checking", type: "checking", startingBalance: 5_000)
        let due = Calendar.current.startOfDay(for: Date())
        guard let bill = billViewModel.addBill(
            name: "Cursor",
            amount: 20,
            dueDate: due,
            recurrenceType: "none",
            autoPay: true,
            account: account
        ) else {
            return XCTFail("Expected bill")
        }
        bill.createdAt = Date().addingTimeInterval(-60)
        try context.save()
        AutoPaySkipStore.skip(billId: bill.id, dueDate: due)
        billViewModel.skipAutoPayProcessing(for: 0)

        billViewModel.fetchBills()
        XCTAssertFalse(bill.isPaid, "Unmarking an auto-pay bill must survive the next launch fetch")
        let pending = (bill.ledgerEntries as? Set<LedgerEntry>)?.filter { !$0.isReconciledFlag } ?? []
        XCTAssertTrue(pending.isEmpty)
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
        XCTAssertEqual(StrikeCSVParser.originalPayee(from: notes), "Condos at Lake H")
        XCTAssertNil(StrikeCSVParser.originalPayee(from: "Imported from CSV\nStrike ref: abc"))
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

    func testTransferMatchOppositeSignWithinThreeDays() {
        let counterparts = [
            StatementImportMatching.TransferCounterpart(
                uri: "x",
                accountName: "Checking",
                date: date(2026, 4, 10),
                amount: Decimal(string: "500.00")!,
                btcAmount: nil,
                isCredit: false,
                alreadyPaired: false
            )
        ]
        XCTAssertEqual(
            StatementImportMatching.transferMatchIndex(
                usdAmount: Decimal(string: "500.00")!,
                btcAmount: Decimal(string: "0.005")!,
                isCredit: true,
                date: date(2026, 4, 12),
                in: counterparts,
                used: [],
                calendar: calendar
            ),
            0
        )
    }

    func testTransferMatchIgnoresSameSignAndPaired() {
        let counterparts = [
            StatementImportMatching.TransferCounterpart(
                uri: "a",
                accountName: "Wallet",
                date: date(2026, 4, 10),
                amount: 200,
                btcAmount: Decimal(string: "0.002"),
                isCredit: true,
                alreadyPaired: false
            ),
            StatementImportMatching.TransferCounterpart(
                uri: "b",
                accountName: "Checking",
                date: date(2026, 4, 10),
                amount: 200,
                btcAmount: nil,
                isCredit: false,
                alreadyPaired: true
            )
        ]
        XCTAssertNil(
            StatementImportMatching.transferMatchIndex(
                usdAmount: 200,
                btcAmount: nil,
                isCredit: true,
                date: date(2026, 4, 10),
                in: counterparts,
                used: [],
                calendar: calendar
            )
        )
    }

    func testTransferMatchPrefersBitcoinAmount() {
        let counterparts = [
            StatementImportMatching.TransferCounterpart(
                uri: "usd-only",
                accountName: "Checking",
                date: date(2026, 4, 10),
                amount: 100,
                btcAmount: nil,
                isCredit: false,
                alreadyPaired: false
            ),
            StatementImportMatching.TransferCounterpart(
                uri: "btc",
                accountName: "Cold",
                date: date(2026, 4, 10),
                amount: 100,
                btcAmount: Decimal(string: "0.001"),
                isCredit: false,
                alreadyPaired: false
            )
        ]
        XCTAssertEqual(
            StatementImportMatching.transferMatchIndex(
                usdAmount: 100,
                btcAmount: Decimal(string: "0.001")!,
                isCredit: true,
                date: date(2026, 4, 10),
                in: counterparts,
                used: [],
                calendar: calendar
            ),
            1
        )
    }

    func testSimilarTransactionsMatchTitleOrAmountAndKind() {
        let mortgage = ParsedStatementTransaction(date: date(2026, 1, 1), title: "Kyle Plathe", amount: 2150, isCredit: false, kind: .billPay)
        let bankName = ParsedStatementTransaction(date: date(2026, 2, 1), title: "Wells Fargo", amount: 2150, isCredit: false, kind: .billPay)
        let coffee = ParsedStatementTransaction(date: date(2026, 1, 2), title: "Starbucks", amount: 6, isCredit: false, kind: .generic)
        let ids = StatementImportMatching.similarTransactionIds(
            to: mortgage,
            originalTitle: "Kyle Plathe",
            in: [mortgage, bankName, coffee],
            originalTitles: [mortgage.id: "Kyle Plathe", bankName.id: "Wells Fargo", coffee.id: "Starbucks"]
        )
        XCTAssertEqual(ids, [bankName.id])
    }

    func testTitleRewritePersistsByNormalizedOriginal() {
        let defaults = UserDefaults(suiteName: "ImportTitleRewriteTests")!
        defaults.removePersistentDomain(forName: "ImportTitleRewriteTests")
        ImportTitleRewriteStore.save(
            originalTitle: "Kyle Plathe",
            preferredTitle: "Mortgage",
            category: "Housing",
            defaults: defaults
        )
        let rewrite = ImportTitleRewriteStore.rewrite(for: "kyle  plathe", defaults: defaults)
        XCTAssertEqual(rewrite?.preferredTitle, "Mortgage")
        XCTAssertEqual(rewrite?.category, "Housing")
        XCTAssertEqual(
            ImportTitleRewriteStore.rewrite(for: "Bill pay to Kyle Plathe", defaults: defaults)?.preferredTitle,
            "Mortgage"
        )
        ImportTitleRewriteStore.save(
            originalTitle: "Kyle Plathe",
            preferredTitle: "Kyle Plathe",
            category: nil,
            defaults: defaults
        )
        XCTAssertEqual(ImportTitleRewriteStore.rewrite(for: "Kyle Plathe", defaults: defaults)?.preferredTitle, "Mortgage")
        defaults.removePersistentDomain(forName: "ImportTitleRewriteTests")
    }

    func testRewriteHintsLearnFromStrikeNotes() {
        let notes = StrikeCSVParser.notes(payee: "Kyle D Plathe", feeUSD: Decimal(string: "5.97"), reference: "abc")
        let hints = StatementImportMatching.rewriteHints(from: [
            .init(title: "Mortgage", notes: notes, category: "Housing"),
            .init(title: "Mortgage", notes: notes, category: "Housing"),
            .init(title: "Kyle D Plathe", notes: notes, category: nil)
        ])
        XCTAssertEqual(hints["kyle d plathe"]?.preferredTitle, "Mortgage")
        XCTAssertEqual(hints["kyle d plathe"]?.category, "Housing")
    }

    func testRewriteHintsSkipTiedPreferredTitles() {
        let notes = StrikeCSVParser.notes(payee: "Wells Fargo", feeUSD: nil, reference: "ref")
        let hints = StatementImportMatching.rewriteHints(from: [
            .init(title: "Transfer", notes: notes, category: nil),
            .init(title: "Bank", notes: notes, category: nil)
        ])
        XCTAssertNil(hints["wells fargo"])
    }

    func testRewriteHintsSkipTransferTitles() {
        let notes = StrikeCSVParser.notes(payee: "Wells Fargo", feeUSD: nil, reference: "ref")
        let hints = StatementImportMatching.rewriteHints(from: [
            .init(title: "Transfer to Checking", notes: notes, category: LedgerTransfer.category)
        ])
        XCTAssertTrue(hints.isEmpty)
    }

    func testPendingTitleRewritesGroupMatchesAndPreferStore() {
        let mortgageA = UUID()
        let mortgageB = UUID()
        let hoa = UUID()
        let coffee = UUID()
        let suggestions = StatementImportMatching.pendingTitleRewrites(
            originalTitles: [
                mortgageA: "Kyle D Plathe",
                mortgageB: "Bill pay to Kyle D Plathe",
                hoa: "Condos at Lake H",
                coffee: "Starbucks"
            ],
            store: [
                "kyle d plathe": .init(preferredTitle: "Mortgage", category: "Housing")
            ],
            ledgerHints: [
                "kyle d plathe": .init(preferredTitle: "Wrong", category: nil),
                "condos at lake h": .init(preferredTitle: "HOA", category: "Housing")
            ]
        )
        XCTAssertEqual(suggestions.map(\.preferredTitle), ["Mortgage", "HOA"])
        XCTAssertEqual(suggestions[0].matchCount, 2)
        XCTAssertEqual(Set(suggestions[0].transactionIds), [mortgageA, mortgageB])
        XCTAssertEqual(suggestions[0].category, "Housing")
        XCTAssertEqual(suggestions[1].preferredTitle, "HOA")
        XCTAssertEqual(suggestions[1].transactionIds, [hoa])
    }

    func testPendingTitleRewritesSkipWhenAlreadyPreferred() {
        let id = UUID()
        let suggestions = StatementImportMatching.pendingTitleRewrites(
            originalTitles: [id: "Mortgage"],
            store: ["mortgage": .init(preferredTitle: "Mortgage", category: nil)],
            ledgerHints: [:]
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testLearnFromImportedNotes() {
        let defaults = UserDefaults(suiteName: "ImportTitleRewriteLearnTests")!
        defaults.removePersistentDomain(forName: "ImportTitleRewriteLearnTests")
        let notes = StrikeCSVParser.notes(payee: "Kyle D Plathe", feeUSD: nil, reference: "abc")
        ImportTitleRewriteStore.learn(
            fromNotes: notes,
            preferredTitle: "Mortgage",
            category: "Housing",
            defaults: defaults
        )
        XCTAssertEqual(ImportTitleRewriteStore.rewrite(for: "Kyle D Plathe", defaults: defaults)?.preferredTitle, "Mortgage")
        defaults.removePersistentDomain(forName: "ImportTitleRewriteLearnTests")
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

final class CategoryPayeeGroupingTests: XCTestCase {
    private struct Item {
        let title: String?
        let amount: Decimal
        let date: Date
    }

    func testGroupsCaseInsensitiveTitlesAndSumsAmounts() {
        let later = Date()
        let earlier = later.addingTimeInterval(-86_400)
        let groups = CategoryPayeeGrouping.groups(
            [
                Item(title: "Mortgage", amount: 2000, date: earlier),
                Item(title: "mortgage", amount: 2000, date: later),
                Item(title: "HOA Dues", amount: 350, date: later)
            ],
            title: { $0.title },
            amount: { $0.amount },
            date: { $0.date }
        )
        XCTAssertEqual(groups.map(\.title), ["Mortgage", "HOA Dues"])
        XCTAssertEqual(groups[0].amount, 4000)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[1].items.count, 1)
    }

    func testSingletonStaysASingleItem() {
        let groups = CategoryPayeeGrouping.groups(
            [Item(title: "Home Depot", amount: 87, date: Date())],
            title: { $0.title },
            amount: { $0.amount },
            date: { $0.date }
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 1)
        XCTAssertEqual(groups[0].title, "Home Depot")
    }

    func testEmptyTitlesGroupAsUntitled() {
        let groups = CategoryPayeeGrouping.groups(
            [
                Item(title: nil, amount: 10, date: Date()),
                Item(title: "  ", amount: 5, date: Date())
            ],
            title: { $0.title },
            amount: { $0.amount },
            date: { $0.date }
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Untitled")
        XCTAssertEqual(groups[0].amount, 15)
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

    func testMixedListTitlesNameThisAccountAndMatchSign() {
        XCTAssertEqual(
            LedgerTransfer.mixedListTitle(
                accountName: "Venmo",
                isCredit: false,
                storedTitle: "Transfer to Bank",
                accountIsCreditAccount: false
            ),
            "Transfer from Venmo"
        )
        XCTAssertEqual(
            LedgerTransfer.mixedListTitle(
                accountName: "Bank",
                isCredit: true,
                storedTitle: "Transfer from Venmo",
                accountIsCreditAccount: false
            ),
            "Transfer to Bank"
        )
        XCTAssertEqual(
            LedgerTransfer.mixedListTitle(
                accountName: "Checking",
                isCredit: false,
                storedTitle: "Payment to Chase",
                accountIsCreditAccount: false
            ),
            "Payment from Checking"
        )
        XCTAssertEqual(
            LedgerTransfer.mixedListTitle(
                accountName: "Chase",
                isCredit: true,
                storedTitle: "Transfer from Checking",
                accountIsCreditAccount: true
            ),
            "Payment to Chase"
        )
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

    func testWildActualBtcDoesNotOverrideEstimatedSats() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 100, dueDay: 1, seriesId: nil, category: nil)
        let start = calendar.date(from: DateComponents(year: 2019, month: 1, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let actual = BillBtcBacktest.LedgerCandidate(
            date: now,
            title: "Rent",
            usd: 100,
            btc: Decimal(string: "0.5"),
            price: 80_000,
            billName: "Rent",
            billSeriesId: nil,
            category: nil
        )
        let withActual = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: actual,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        )
        let estimate = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: nil,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        )
        XCTAssertEqual(withActual?.isEstimate, false)
        XCTAssertEqual(withActual?.price, 80_000)
        XCTAssertEqual(withActual?.btc, estimate?.btc)
        XCTAssertNotEqual(withActual?.btc, Decimal(string: "0.5"))
        XCTAssertLessThan(withActual?.btc ?? 1, Decimal(string: "0.01")!)
    }

    func testActualUsdAndBtcPaymentIsUsed() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 100, dueDay: 1, seriesId: nil, category: nil)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let paidBtc = Decimal(100) / Decimal(80_000)
        let actual = BillBtcBacktest.LedgerCandidate(
            date: now,
            title: "Rent",
            usd: 100,
            btc: paidBtc,
            price: 80_000,
            billName: "Rent",
            billSeriesId: nil,
            category: nil
        )
        let result = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: actual,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(result?.isEstimate, false)
        XCTAssertEqual(result?.btc, paidBtc)
        XCTAssertEqual(result?.usd, 100)
    }

    func testMonthAmountUsesActualUsdWhenDifferentFromTemplate() {
        let template = BillBtcBacktest.Template(name: "Mortgage", amount: 2000, dueDay: 1, seriesId: nil, category: nil)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let paidBtc = Decimal(1800) / Decimal(80_000)
        let actual = BillBtcBacktest.LedgerCandidate(
            date: now,
            title: "Mortgage",
            usd: 1800,
            btc: paidBtc,
            price: 80_000,
            billName: "Mortgage",
            billSeriesId: nil,
            category: nil
        )
        let matched = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: actual,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar
        )
        let backfilled = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: nil,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(matched?.isEstimate, false)
        XCTAssertEqual(matched?.usd, 1800)
        XCTAssertEqual(matched?.btc, paidBtc)
        XCTAssertEqual(backfilled?.isEstimate, true)
        XCTAssertEqual(backfilled?.usd, 2000)
        XCTAssertEqual(backfilled?.btc, Decimal(2000) / Decimal(80_000))
    }

    func testMarkPaidFillsUsdAndBtc() {
        let fromSats = BillBtcBacktest.btcFilledFromUsd(usd: 1500, satsAmount: 2_000_000, btcUsdRate: 75_000)
        XCTAssertEqual(fromSats?.btc, Decimal(2_000_000) / Decimal(100_000_000))
        XCTAssertEqual(fromSats?.price, Decimal(1500) / (Decimal(2_000_000) / Decimal(100_000_000)))

        let fromRate = BillBtcBacktest.btcFilledFromUsd(usd: 1500, satsAmount: nil, btcUsdRate: 75_000)
        XCTAssertEqual(fromRate?.btc, Decimal(1500) / Decimal(75_000))
        XCTAssertEqual(fromRate?.price, 75_000)

        XCTAssertNil(BillBtcBacktest.btcFilledFromUsd(usd: 1500, satsAmount: nil, btcUsdRate: 0))
        XCTAssertTrue(BillBtcBacktest.isPlausibleActualBtc(Decimal(1500) / Decimal(75_000), estimated: Decimal(1500) / Decimal(80_000)))
        XCTAssertFalse(BillBtcBacktest.isPlausibleActualBtc(Decimal(string: "0.5")!, estimated: Decimal(100) / Decimal(80_000)))
    }

    func testDetectsDollarBillPaidInSats() {
        XCTAssertTrue(BillBtcBacktest.hasUsdAndBitcoinPayment(isCredit: false, usdAmount: 1500, btcAmount: Decimal(string: "0.02")!))
        XCTAssertFalse(BillBtcBacktest.hasUsdAndBitcoinPayment(isCredit: false, usdAmount: 0, btcAmount: Decimal(string: "0.02")!))
        XCTAssertTrue(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: false, usdAmount: 1500, btcAmount: Decimal(string: "0.02")!))
        XCTAssertTrue(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: false, usdAmount: 0, btcAmount: Decimal(string: "0.02")!))
        XCTAssertFalse(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: false, usdAmount: 1500, btcAmount: 0))
        XCTAssertFalse(BillBtcBacktest.isUsdBillPaidInBitcoin(isCredit: true, usdAmount: 1500, btcAmount: Decimal(string: "0.02")!))
        XCTAssertTrue(BillBtcBacktest.isTrackedBitcoinPayment(isCredit: false, usdAmount: 1500, btcAmount: 0, paysFromBitcoinWallet: true))
        XCTAssertFalse(BillBtcBacktest.isTrackedBitcoinPayment(isCredit: false, usdAmount: 1500, btcAmount: 0, paysFromBitcoinWallet: false))
    }

    func testTemplatesUseLatestAmountInSeries() {
        let series = UUID()
        let paid = BillBtcBacktest.BillSource(
            groupingKey: series.uuidString,
            name: "Rent",
            amount: 1400,
            dueDate: calendar.date(from: DateComponents(year: 2025, month: 6, day: 1)),
            seriesId: series,
            category: "Housing"
        )
        let current = BillBtcBacktest.BillSource(
            groupingKey: series.uuidString,
            name: "Rent",
            amount: 1550,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)),
            seriesId: series,
            category: "Housing"
        )
        let other = BillBtcBacktest.BillSource(
            groupingKey: UUID().uuidString,
            name: "Netflix",
            amount: 15,
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 5)),
            seriesId: nil,
            category: "Subscriptions"
        )
        let templates = BillBtcBacktest.templates(from: [paid, current, other], calendar: calendar)
        XCTAssertEqual(templates.map(\.name), ["Netflix", "Rent"])
        XCTAssertEqual(templates.first(where: { $0.name == "Rent" })?.amount, 1550)
        XCTAssertEqual(templates.first(where: { $0.name == "Rent" })?.dueDay, 1)
    }

    func testUnlinkedPaysNeedABillToBecomeATemplate() {
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 3))!
        let payments = (0..<20).map { offset in
            BillBtcBacktest.LedgerCandidate(
                date: calendar.date(byAdding: .month, value: offset, to: start)!,
                title: "Kyle Plathe",
                usd: 750.34,
                btc: Decimal(string: "0.0078591"),
                price: 96_233,
                billName: nil,
                billSeriesId: nil,
                category: "Housing"
            )
        }
        XCTAssertTrue(BillBtcBacktest.templates(from: [], calendar: calendar).isEmpty)
        let mortgage = BillBtcBacktest.BillSource(
            groupingKey: UUID().uuidString,
            name: "Mortgage",
            amount: 750.34,
            dueDate: start,
            seriesId: nil,
            category: "Housing"
        )
        XCTAssertEqual(BillBtcBacktest.templates(from: [mortgage], calendar: calendar).map(\.name), ["Mortgage"])
        XCTAssertEqual(payments.count, 20)
    }

    func testStrikeBillPayMatchesDollarAmountEvenIfPayeeDiffers() {
        let template = BillBtcBacktest.Template(name: "Mortgage", amount: 750.34, dueDay: 1, seriesId: nil, category: "Housing")
        let monthStart = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let monthEnd = calendar.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        let candidates = [
            BillBtcBacktest.LedgerCandidate(
                date: calendar.date(from: DateComponents(year: 2025, month: 6, day: 3))!,
                title: "Kyle Plathe",
                usd: 750.34,
                btc: Decimal(string: "0.0078591"),
                price: 96_233,
                billName: nil,
                billSeriesId: nil,
                category: "Housing"
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

    func testOnlyBillsWithSatsPaymentsAppear() {
        let mortgage = BillBtcBacktest.Template(name: "Mortgage", amount: 750.34, dueDay: 1, seriesId: nil, category: "Housing")
        let hoa = BillBtcBacktest.Template(name: "HOA Dues", amount: 365.84, dueDay: 3, seriesId: nil, category: "Housing")
        let netflix = BillBtcBacktest.Template(name: "Netflix", amount: 15, dueDay: 5, seriesId: nil, category: "Subscriptions")
        let start = calendar.date(from: DateComponents(year: 2025, month: 6, day: 3))!
        let candidates = [
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "Mortgage",
                usd: 750.34,
                btc: Decimal(string: "0.0078591"),
                price: 96_233,
                billName: "Mortgage",
                billSeriesId: nil,
                category: "Housing"
            ),
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "HOA Dues",
                usd: 365.84,
                btc: Decimal(string: "0.00382928"),
                price: 96_297,
                billName: "HOA Dues",
                billSeriesId: nil,
                category: "Housing"
            ),
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "Netflix",
                usd: 15,
                btc: nil,
                price: nil,
                billName: "Netflix",
                billSeriesId: nil,
                category: "Subscriptions"
            )
        ]
        XCTAssertEqual(
            BillBtcBacktest.bitcoinPaidTemplates(from: [mortgage, hoa, netflix], candidates: candidates).map(\.name),
            ["HOA Dues", "Mortgage"]
        )
    }

    func testCheckingPaidBillWithSimilarAmountDoesNotAppear() {
        let mortgage = BillBtcBacktest.Template(name: "Mortgage", amount: 750.34, dueDay: 1, seriesId: nil, category: "Housing")
        let insurance = BillBtcBacktest.Template(name: "Insurance", amount: 750, dueDay: 15, seriesId: nil, category: "Insurance")
        let netflix = BillBtcBacktest.Template(name: "Netflix", amount: 15, dueDay: 5, seriesId: nil, category: "Subscriptions")
        let start = calendar.date(from: DateComponents(year: 2025, month: 6, day: 3))!
        let candidates = [
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "Kyle D Plathe",
                usd: 750.34,
                btc: Decimal(string: "0.0078591"),
                price: 96_233,
                billName: nil,
                billSeriesId: nil,
                category: "Housing"
            ),
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "State Farm",
                usd: 750,
                btc: nil,
                price: nil,
                billName: "Insurance",
                billSeriesId: nil,
                category: "Insurance"
            ),
            BillBtcBacktest.LedgerCandidate(
                date: start,
                title: "Netflix",
                usd: 15,
                btc: nil,
                price: nil,
                billName: "Netflix",
                billSeriesId: nil,
                category: "Subscriptions"
            )
        ]
        XCTAssertEqual(
            BillBtcBacktest.bitcoinPaidTemplates(from: [mortgage, insurance, netflix], candidates: candidates).map(\.name),
            ["Mortgage"]
        )
    }

    func testSharePunchlineUsesBillName() {
        XCTAssertEqual(BillBtcBacktest.sharePunchline(billName: "Mortgage"), "Same Mortgage. Less Bitcoin.")
        XCTAssertEqual(BillBtcBacktest.sharePunchline(billName: "  "), "Same bill. Less Bitcoin.")
        XCTAssertEqual(BillBtcBacktest.sharePunchline(billNames: ["Rent", "Xcel"]), "Same bills. Less Bitcoin.")
        XCTAssertEqual(BillBtcBacktest.lessBitcoinCaption(percentLess: 0.5, billCount: 1), "less Bitcoin to pay the same bill")
        XCTAssertEqual(BillBtcBacktest.lessBitcoinCaption(percentLess: 0.5, billCount: 3), "less Bitcoin to pay the same bills")
        XCTAssertEqual(BillBtcBacktest.sameDollarsCaption(billCount: 1), "Same bill. Less Bitcoin.")
        XCTAssertEqual(BillBtcBacktest.sameDollarsCaption(billCount: 2), "Same bills. Less Bitcoin.")
        XCTAssertFalse(BillBtcBacktest.bitcoinQuotes.isEmpty)
        XCTAssertTrue(BillBtcBacktest.bitcoinQuotes.contains(BillBtcBacktest.randomBitcoinQuote()))
    }

    func testCompactSatsFormats() {
        XCTAssertEqual(BillBtcBacktest.compactSats(4_200_000), "4.2M")
        XCTAssertEqual(BillBtcBacktest.compactSats(480_000), "480k")
        XCTAssertEqual(BillBtcBacktest.satsValue(fromBTC: Decimal(string: "0.01")!), 1_000_000, accuracy: 0.1)
    }

    func testEstimateWithoutHistoricalPriceUsesFallback() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 1500, dueDay: 1, seriesId: nil, category: "Housing")
        let due = calendar.date(from: DateComponents(year: 2018, month: 6, day: 1))!
        let result = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: due,
            actual: nil,
            historicalPrice: nil,
            currentPrice: 0,
            calendar: calendar
        )
        XCTAssertEqual(result?.isEstimate, true)
        XCTAssertEqual(result?.usd, 1500)
        XCTAssertGreaterThan(result?.btc ?? 0, Decimal(1500) / Decimal(20_000))
        XCTAssertLessThan(result?.btc ?? 1, Decimal(1500) / Decimal(1_000))
    }

    func testShareTitleUsesBillName() {
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Mortgage"]), "Mortgage USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Rent", "Xcel"]), "Rent & Xcel USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareTitle(billNames: ["Rent", "Xcel", "Internet"]), "Rent, Xcel, Internet USD vs BTC")
        XCTAssertEqual(BillBtcBacktest.shareHeadlineName(from: "Mortgage USD vs BTC"), "Mortgage")
        XCTAssertEqual(BillBtcBacktest.shareHeadlineName(from: "Rent, Xcel, Internet USD vs BTC"), "Rent, Xcel, Internet")
    }

    func testBitcoinSpendChangeShowsLessOverTime() {
        let early = Array(repeating: Decimal(string: "0.04")!, count: 12)
        let late = Array(repeating: Decimal(string: "0.01")!, count: 12)
        let change = BillBtcBacktest.bitcoinSpendChange(btcAmounts: early + late, monthCount: 48)
        XCTAssertEqual(change?.percentLess, Decimal(string: "0.75"))
        XCTAssertEqual(change?.years, 4)
        XCTAssertEqual(BillBtcBacktest.changeSentence(change!), "Paid 75% less Bitcoin than 4 years ago")
    }

    func testHeadlinePercentUsesLookbackStartVersusNow() {
        let start = calendar.date(from: DateComponents(year: 2019, month: 1, day: 1))!
        let template = BillBtcBacktest.Template(name: "Rent", amount: 100, dueDay: 1, seriesId: nil, category: nil)
        func points(months: Int) -> [UsdBtcMonthPoint] {
            (0..<months).compactMap { offset -> UsdBtcMonthPoint? in
                let date = calendar.date(byAdding: .month, value: offset, to: start)!
                guard let amount = BillBtcBacktest.monthAmount(
                    template: template,
                    dueDate: date,
                    actual: nil,
                    historicalPrice: BillBtcBacktest.fallbackBtcUsd(on: date, calendar: calendar),
                    currentPrice: 100_000,
                    now: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                    calendar: calendar
                ) else { return nil }
                return UsdBtcMonthPoint(
                    month: date,
                    usdExpenses: amount.usd,
                    btcAtTime: amount.btc,
                    btcValueNow: amount.usd,
                    btcAmount: amount.btc,
                    avgBtcPrice: amount.price,
                    isEstimate: false
                )
            }
        }
        func report(from months: [UsdBtcMonthPoint]) -> UsdBtcReportData {
            UsdBtcReportData(
                months: months,
                bills: [UsdBtcBillSeries(name: "Rent", months: months, totalUsd: 100, totalBtcAtTime: 1, totalBtcValueNow: 100)],
                totalUsd: 100,
                totalBtcAtTime: 1,
                totalBtcValueNow: 100,
                monthsBack: months.count,
                trackedBillNames: ["Rent"],
                estimatedMonths: 0,
                actualMonths: months.count
            )
        }
        let long = report(from: points(months: 48))
        let short = report(from: Array(points(months: 48).suffix(12)))
        let longChange = BillBtcBacktest.storyChange(from: long)
        let shortChange = BillBtcBacktest.storyChange(from: short)
        XCTAssertGreaterThan(longChange?.percentLess ?? 0, Decimal(string: "0.5")!)
        XCTAssertGreaterThan(BillBtcBacktest.percentPoints(longChange?.percentLess ?? 0), 0)
        XCTAssertNotEqual(BillBtcBacktest.percentPoints(longChange?.percentLess ?? 0), BillBtcBacktest.percentPoints(shortChange?.percentLess ?? 0))
        XCTAssertTrue(BillBtcBacktest.hasEnoughBacktestData(from: long))
        XCTAssertEqual(BillBtcBacktest.lessBitcoinCaption(percentLess: longChange?.percentLess ?? 1, billCount: 1), "less Bitcoin to pay the same bill")
        XCTAssertTrue(BillBtcBacktest.compactBitcoin(Decimal(string: "0.0125")!).contains("BTC"))
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

    func testMonthlyAverages() {
        let usd: [Decimal] = [1500, 1500, 1800]
        let btc: [Decimal] = [Decimal(string: "0.03")!, Decimal(string: "0.02")!, Decimal(string: "0.01")!]
        let avg = BillBtcBacktest.monthlyAverages(usdAmounts: usd, btcAmounts: btc)
        XCTAssertEqual(avg?.monthCount, 3)
        XCTAssertEqual(avg?.monthlyUsd, 1600)
        XCTAssertEqual(avg?.monthlyBtc, Decimal(string: "0.02"))
    }

    func testRollingAverageUsesTrailingWindow() {
        let rolled = BillBtcBacktest.rollingAverage([1, 3, 5], window: 2)
        XCTAssertEqual(rolled, [1, 2, 4])
        XCTAssertEqual(BillBtcBacktest.smoothingWindow(monthCount: 48), 12)
        XCTAssertEqual(BillBtcBacktest.smoothingWindow(monthCount: 8), 3)
    }

    func testIndexedAverageLineDoesNotSumBills() {
        let jan = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let feb = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1))!
        let mar = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        func points(btc: [Decimal]) -> [UsdBtcMonthPoint] {
            zip([jan, feb, mar], btc).map { date, amount in
                UsdBtcMonthPoint(
                    month: date,
                    usdExpenses: 100,
                    btcAtTime: 100,
                    btcValueNow: 100,
                    btcAmount: amount,
                    avgBtcPrice: 1,
                    isEstimate: true
                )
            }
        }
        let mortgage = BillBtcBacktest.indexedAverageLine(
            from: points(btc: [Decimal(string: "0.04")!, Decimal(string: "0.02")!, Decimal(string: "0.01")!]),
            window: 1
        )
        let hoa = BillBtcBacktest.indexedAverageLine(
            from: points(btc: [Decimal(string: "0.004")!, Decimal(string: "0.002")!, Decimal(string: "0.001")!]),
            window: 1
        )
        XCTAssertEqual(mortgage?.sats.first ?? 0, 4_000_000, accuracy: 1)
        XCTAssertEqual(hoa?.sats.first ?? 0, 400_000, accuracy: 1)
        XCTAssertEqual(mortgage?.sats.last ?? 0, 1_000_000, accuracy: 1)
        XCTAssertEqual(hoa?.sats.last ?? 0, 100_000, accuracy: 1)
    }

    func testChartKeyItemsShowUsdAndSatsSpan() {
        let jan = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let dates = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: jan) }
        let months: [UsdBtcMonthPoint] = dates.enumerated().map { index, date in
            UsdBtcMonthPoint(
                month: date,
                usdExpenses: 2000,
                btcAtTime: 0,
                btcValueNow: 0,
                btcAmount: index < 6 ? Decimal(string: "0.04")! : Decimal(string: "0.01")!,
                avgBtcPrice: 1,
                isEstimate: true
            )
        }
        let bill = UsdBtcBillSeries(name: "Mortgage", months: months, totalUsd: 0, totalBtcAtTime: 0, totalBtcValueNow: 0)
        let items = BillBtcBacktest.chartKeyItems(from: [bill])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Mortgage")
        XCTAssertEqual(items.first?.monthlyUsd, 2000)
        XCTAssertGreaterThan(items.first?.percentLess ?? 0, Decimal(string: "0.5")!)
        XCTAssertEqual(items.first?.actualMonths, 0)
        XCTAssertEqual(BillBtcBacktest.actualDataCaption(actualMonths: 20), "20 mo actual")
        XCTAssertEqual(BillBtcBacktest.backtestCaption(monthCount: 42), "Backtest 3 years")
        XCTAssertEqual(BillBtcBacktest.backtestCaption(monthCount: 36), "Backtest 3 years")
        XCTAssertEqual(BillBtcBacktest.backtestCaption(monthCount: 12), "Backtest 1 year")
        XCTAssertEqual(BillBtcBacktest.backtestCaption(monthCount: 6), "Backtest")
        let spanStart = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        let spanEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        XCTAssertEqual(BillBtcBacktest.backtestMonthSpan(from: [spanStart, spanEnd], calendar: calendar), 42)
        XCTAssertEqual(BillBtcBacktest.storyHeadline(percentLess: Decimal(string: "0.67")!, billCount: 2), "Same bills. 67% less Bitcoin.")
        XCTAssertEqual(BillBtcBacktest.storyHeadline(percentLess: Decimal(string: "0.67")!, billCount: 1), "Same bill. 67% less Bitcoin.")
        XCTAssertEqual(
            BillBtcBacktest.orderedNames(["Xcel", "Mortgage", "HOA"], by: ["Mortgage", "HOA"]),
            ["Mortgage", "HOA", "Xcel"]
        )
        let snapshot = BillBtcBacktest.thenNow(from: bill)
        XCTAssertEqual(snapshot?.thenLabel, String(Calendar.current.component(.year, from: jan)))
        XCTAssertGreaterThan(snapshot?.thenSats ?? 0, snapshot?.nowSats ?? 0)
        XCTAssertEqual(BillBtcBacktest.satsCaption(1_007_783), "1.0M sats")
        let bitcoinFromSats = BillBtcBacktest.bitcoinCaption(fromSats: 4_100_000)
        XCTAssertEqual(bitcoinFromSats, BillBtcBacktest.compactBitcoin(Decimal(string: "0.041")!))
        XCTAssertTrue(bitcoinFromSats.hasSuffix(" BTC"))
        XCTAssertFalse(bitcoinFromSats.localizedCaseInsensitiveContains("sats"))
        XCTAssertEqual(BillBtcBacktest.compactBitcoinAxis(4_100_000), String(bitcoinFromSats.dropLast(4)))
        let footerDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11))!
        XCTAssertEqual(
            BillBtcBacktest.shareChartFooter(on: footerDate, locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone),
            "Bitcoin Deflation Chart · Sep 11, 2026"
        )
    }

    func testLookbackClampIncludesEightYears() {
        XCTAssertEqual(BillBtcBacktest.clampLookbackMonths(96), 96)
        XCTAssertEqual(BillBtcBacktest.clampLookbackMonths(5), 12)
        XCTAssertEqual(BillBtcBacktest.clampLookbackMonths(48), 48)
        XCTAssertEqual(BillBtcBacktest.clampLookbackMonths(200), 96)
    }

    func testLookbackPresetsSnapStoredMonths() {
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.default, .fiveYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.allCases.map(\.title), ["1Y", "3Y", "5Y", "Max"])
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(12), .oneYear)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(36), .threeYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(60), .fiveYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(96), .max)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(48), .fiveYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(24), .threeYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(72), .fiveYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(84), .max)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(5), .fiveYears)
        XCTAssertEqual(BillBtcBacktest.LookbackPreset.fromStoredMonths(200), .max)
    }

    func testHistoricalDisclaimerCopy() {
        XCTAssertEqual(
            BillBtcBacktest.historicalDisclaimer,
            "Not financial advice. Not a wallet."
        )
        XCTAssertFalse(BillBtcBacktest.historicalDisclaimer.localizedCaseInsensitiveContains("stack sats"))
        XCTAssertEqual(
            BillBtcBacktest.shareDisclaimer,
            "Paid via Strike. Not financial advice. Not a wallet."
        )
    }

    func testTwoLineQuoteBalancesLengthAndKeepsShortQuotes() {
        let long = BillBtcBacktest.twoLineQuote(
            "The root problem with conventional currency is all the trust that's required to make it work."
        )
        let lines = long.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThan(abs(lines[0].count - lines[1].count), 16)
        XCTAssertEqual(BillBtcBacktest.twoLineQuote("Don't trust, verify."), "Don't trust, verify.")
    }

    func testLookbackDataStatusCopy() {
        XCTAssertEqual(
            BillBtcBacktest.lookbackDataStatus(actualMonths: 8),
            "Using your actual payments + historical Bitcoin prices"
        )
        XCTAssertEqual(
            BillBtcBacktest.lookbackDataStatus(actualMonths: 0),
            "Backtested with your current averages + historical prices"
        )
    }

    func testWindowedLookbackPresetsUpdateThenNow() {
        let start = calendar.date(from: DateComponents(year: 2018, month: 1, day: 1))!
        let template = BillBtcBacktest.Template(name: "Rent", amount: 100, dueDay: 1, seriesId: nil, category: nil)
        let months: [UsdBtcMonthPoint] = (0..<96).compactMap { offset in
            let date = calendar.date(byAdding: .month, value: offset, to: start)!
            guard let amount = BillBtcBacktest.monthAmount(
                template: template,
                dueDate: date,
                actual: nil,
                historicalPrice: BillBtcBacktest.fallbackBtcUsd(on: date, calendar: calendar),
                currentPrice: 100_000,
                now: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!,
                calendar: calendar
            ) else { return nil }
            return UsdBtcMonthPoint(
                month: date,
                usdExpenses: amount.usd,
                btcAtTime: amount.btc,
                btcValueNow: amount.usd,
                btcAmount: amount.btc,
                avgBtcPrice: amount.price,
                isEstimate: true
            )
        }
        let full = UsdBtcReportData(
            months: months,
            bills: [UsdBtcBillSeries(name: "Rent", months: months, totalUsd: 100, totalBtcAtTime: 1, totalBtcValueNow: 100)],
            totalUsd: 100,
            totalBtcAtTime: 1,
            totalBtcValueNow: 100,
            monthsBack: months.count,
            trackedBillNames: ["Rent"],
            estimatedMonths: months.count,
            actualMonths: 0
        )
        let oneYear = BillBtcBacktest.windowed(full, monthsBack: BillBtcBacktest.LookbackPreset.oneYear.rawValue)
        let fiveYear = BillBtcBacktest.windowed(full, monthsBack: BillBtcBacktest.LookbackPreset.fiveYears.rawValue)
        let max = BillBtcBacktest.windowed(full, monthsBack: BillBtcBacktest.LookbackPreset.max.rawValue)
        XCTAssertEqual(oneYear.months.count, 12)
        XCTAssertEqual(fiveYear.months.count, 60)
        XCTAssertEqual(max.months.count, 96)
        let oneThen = BillBtcBacktest.thenNow(from: oneYear)
        let fiveThen = BillBtcBacktest.thenNow(from: fiveYear)
        let maxThen = BillBtcBacktest.thenNow(from: max)
        XCTAssertNotEqual(oneThen?.thenSats ?? 0, fiveThen?.thenSats ?? 0)
        XCTAssertNotEqual(fiveThen?.thenSats ?? 0, maxThen?.thenSats ?? 0)
        let oneChange = BillBtcBacktest.storyChange(from: oneYear)
        let fiveChange = BillBtcBacktest.storyChange(from: fiveYear)
        XCTAssertNotEqual(
            BillBtcBacktest.percentPoints(oneChange?.percentLess ?? 0),
            BillBtcBacktest.percentPoints(fiveChange?.percentLess ?? 0)
        )
        XCTAssertEqual(BillBtcBacktest.lookbackDataStatus(actualMonths: max.actualMonths), "Backtested with your current averages + historical prices")
    }

    func testEstimateHoldsConstantDollarBill() {
        let template = BillBtcBacktest.Template(name: "Rent", amount: 2000, dueDay: 1, seriesId: nil, category: "Housing")
        let due = calendar.date(from: DateComponents(year: 2018, month: 6, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let result = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: due,
            actual: nil,
            historicalPrice: 7_500,
            currentPrice: 100_000,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(result?.isEstimate, true)
        XCTAssertEqual(result?.usd, 2000)
        XCTAssertEqual(result?.btc, Decimal(2000) / Decimal(7_500))
    }

    func testRisingPriceReducesSatsNeeded() {
        let template = BillBtcBacktest.Template(name: "Mortgage", amount: 2000, dueDay: 1, seriesId: nil, category: "Housing")
        let start = calendar.date(from: DateComponents(year: 2019, month: 1, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let startAmount = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: start,
            actual: nil,
            historicalPrice: 10_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        )
        let todayAmount = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: nil,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        )
        XCTAssertNotNil(startAmount)
        XCTAssertNotNil(todayAmount)
        XCTAssertLessThan(todayAmount?.btc ?? 1, startAmount?.btc ?? 0)
        XCTAssertLessThan(todayAmount?.btc ?? 1, (startAmount?.btc ?? 0) * Decimal(string: "0.2")!)
    }

    func testIndexedAverageLineFallsWhenPriceRises() {
        let template = BillBtcBacktest.Template(name: "Mortgage", amount: 2000, dueDay: 1, seriesId: nil, category: "Housing")
        let start = calendar.date(from: DateComponents(year: 2019, month: 1, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        guard let startAmount = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: start,
            actual: nil,
            historicalPrice: 10_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        ), let todayAmount = BillBtcBacktest.monthAmount(
            template: template,
            dueDate: now,
            actual: nil,
            historicalPrice: 80_000,
            currentPrice: 80_000,
            now: now,
            calendar: calendar,
            lookbackStart: start
        ) else {
            return XCTFail("Expected month amounts")
        }
        func point(month: Date, amount: BillBtcBacktest.MonthAmount) -> UsdBtcMonthPoint {
            UsdBtcMonthPoint(
                month: month,
                usdExpenses: amount.usd,
                btcAtTime: amount.btc,
                btcValueNow: 0,
                btcAmount: amount.btc,
                avgBtcPrice: amount.price,
                isEstimate: amount.isEstimate
            )
        }
        let line = BillBtcBacktest.indexedAverageLine(
            from: [point(month: start, amount: startAmount), point(month: now, amount: todayAmount)],
            window: 1
        )
        XCTAssertNotNil(line)
        XCTAssertLessThan(line?.sats.last ?? 1, line?.sats.first ?? 0)
    }

    func testTrailingAveragesUsesLastWindow() {
        let usd = Array(repeating: Decimal(1000), count: 12) + Array(repeating: Decimal(2000), count: 12)
        let btc = Array(repeating: Decimal(string: "0.04")!, count: 12) + Array(repeating: Decimal(string: "0.01")!, count: 12)
        let avg = BillBtcBacktest.trailingAverages(usdAmounts: usd, btcAmounts: btc)
        XCTAssertEqual(avg?.monthlyUsd, 2000)
        XCTAssertEqual(avg?.monthlyBtc, Decimal(string: "0.01"))
    }

    func testSignedPercentLabel() {
        let up = BillBtcBacktest.BitcoinSpendChange(percentLess: Decimal(string: "-0.10")!, years: 4, monthCount: 48)
        let down = BillBtcBacktest.BitcoinSpendChange(percentLess: Decimal(string: "0.05")!, years: 4, monthCount: 48)
        XCTAssertEqual(BillBtcBacktest.signedPercentLabel(up), "+10%")
        XCTAssertEqual(BillBtcBacktest.signedPercentLabel(down), "−5%")
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

final class LivingMeansInsightTests: XCTestCase {
    func testQuoteIsStableForAGivenDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        XCTAssertEqual(LivingMeansInsight.quote(on: day, calendar: calendar), LivingMeansInsight.quote(on: day, calendar: calendar))
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        XCTAssertNotEqual(LivingMeansInsight.quote(on: day, calendar: calendar), LivingMeansInsight.quote(on: next, calendar: calendar))
    }

    func testPaycheckIncomeTakesPriority() {
        let means = LivingMeansInsight.means(
            paycheckIncome: 4000,
            trailingDeposits: [1000, 1000],
            expenses: 3000
        )
        XCTAssertEqual(means?.source, .paycheck)
        XCTAssertEqual(means?.isBelow, true)
        XCTAssertEqual(means?.percentage, 25)
        XCTAssertTrue(LivingMeansInsight.meansLine(means!).contains("below your means"))
    }

    func testTrailingDepositsWhenPaychecksAreZero() {
        let means = LivingMeansInsight.means(
            paycheckIncome: 0,
            trailingDeposits: [3000, 3000, 3000],
            expenses: 2000
        )
        XCTAssertEqual(means?.source, .trailingDeposits)
        XCTAssertEqual(means?.isBelow, true)
        XCTAssertTrue(LivingMeansInsight.meansLine(means!).contains("typical income"))
    }

    func testTooFewDepositsYieldsNoMeans() {
        let means = LivingMeansInsight.means(
            paycheckIncome: 0,
            trailingDeposits: [5000],
            expenses: 1000
        )
        XCTAssertNil(means)
    }

    func testTypicalMonthlyIncomeAveragesThreeMonths() {
        let typical = LivingMeansInsight.typicalMonthlyIncome(from: [3000, 3000, 3000])
        XCTAssertEqual(typical, 3000)
    }
}

final class AutoPayShortfallTests: XCTestCase {
    func testDebitIncludesWalletFee() {
        let debit = AutoPayShortfall.debitAmount(billAmount: 100, feePercentage: 1.5)
        XCTAssertEqual(debit, Decimal(string: "101.5"))
    }

    func testHoldWhenBelowReserve() {
        let hold = AutoPayShortfall.wouldHold(
            autoPay: true,
            isPaid: false,
            currencyCode: "USD",
            currentBalance: 600,
            billAmount: 200,
            feePercentage: 0,
            reserve: 500
        )
        XCTAssertTrue(hold)
    }

    func testProceedWhenReserveIsMet() {
        let hold = AutoPayShortfall.wouldHold(
            autoPay: true,
            isPaid: false,
            currencyCode: "USD",
            currentBalance: 800,
            billAmount: 200,
            feePercentage: 0,
            reserve: 500
        )
        XCTAssertFalse(hold)
    }

    func testHoldWhenBalanceWouldGoNegativeWithZeroReserve() {
        let hold = AutoPayShortfall.wouldHold(
            autoPay: true,
            isPaid: false,
            currencyCode: "USD",
            currentBalance: 50,
            billAmount: 80,
            feePercentage: 0,
            reserve: 0
        )
        XCTAssertTrue(hold)
    }

    func testSkipsNonUSDAndPaidBills() {
        XCTAssertFalse(AutoPayShortfall.wouldHold(
            autoPay: true,
            isPaid: false,
            currencyCode: "BTC",
            currentBalance: 0,
            billAmount: 100,
            feePercentage: 0,
            reserve: 0
        ))
        XCTAssertFalse(AutoPayShortfall.wouldHold(
            autoPay: true,
            isPaid: true,
            currencyCode: "USD",
            currentBalance: 10,
            billAmount: 100,
            feePercentage: 0,
            reserve: 0
        ))
        XCTAssertFalse(AutoPayShortfall.wouldHold(
            autoPay: false,
            isPaid: false,
            currencyCode: "USD",
            currentBalance: 10,
            billAmount: 100,
            feePercentage: 0,
            reserve: 0
        ))
    }

    func testNotificationIdentifierIsStableAndDistinctFromBillId() {
        let id = UUID()
        XCTAssertEqual(AutoPayShortfall.notificationIdentifier(billId: id), "shortfall-\(id.uuidString)")
        XCTAssertNotEqual(AutoPayShortfall.notificationIdentifier(billId: id), id.uuidString)
    }

    func testNotificationBodyMentionsReserve() {
        let body = AutoPayShortfall.notificationBody(billName: "Rent", accountName: "Checking", reserve: 500)
        XCTAssertTrue(body.contains("Rent"))
        XCTAssertTrue(body.contains("Checking"))
        XCTAssertTrue(body.contains("$500.00"))
    }
}

final class AutoPayProcessingTests: XCTestCase {
    override func setUp() {
        AutoPaySkipStore.resetForTests()
    }

    override func tearDown() {
        AutoPaySkipStore.resetForTests()
    }

    func testProcessesDueUnpaidAutoPayBill() {
        let now = Date()
        XCTAssertTrue(AutoPayProcessing.shouldProcess(
            autoPay: true,
            isPaid: false,
            hasAccount: true,
            createdAt: now.addingTimeInterval(-60),
            processingDate: now.addingTimeInterval(-86_400),
            isSkipped: false,
            now: now
        ))
    }

    func testSkipsWhenUserUnmarkedThisDueDate() {
        let now = Date()
        XCTAssertFalse(AutoPayProcessing.shouldProcess(
            autoPay: true,
            isPaid: false,
            hasAccount: true,
            createdAt: now.addingTimeInterval(-60),
            processingDate: now,
            isSkipped: true,
            now: now
        ))
    }

    func testSkipsNewlyCreatedBills() {
        let now = Date()
        XCTAssertFalse(AutoPayProcessing.shouldProcess(
            autoPay: true,
            isPaid: false,
            hasAccount: true,
            createdAt: now,
            processingDate: now,
            isSkipped: false,
            now: now
        ))
    }

    func testSkipStoreSurvivesSameOccurrence() {
        let id = UUID()
        let due = Date()
        XCTAssertFalse(AutoPaySkipStore.isSkipped(billId: id, dueDate: due))
        AutoPaySkipStore.skip(billId: id, dueDate: due)
        XCTAssertTrue(AutoPaySkipStore.isSkipped(billId: id, dueDate: due))
        AutoPaySkipStore.clear(billId: id, dueDate: due)
        XCTAssertFalse(AutoPaySkipStore.isSkipped(billId: id, dueDate: due))
    }
}

@MainActor
final class TransactionSuggestionTests: XCTestCase {
    var persistence: PersistenceController!
    var viewModel: AccountViewModel!

    override func setUp() async throws {
        persistence = PersistenceController(inMemory: true)
        viewModel = AccountViewModel(context: persistence.container.viewContext)
    }

    private func makeAccount(_ name: String = "Checking") -> Account {
        viewModel.addAccount(name: name, type: "checking", startingBalance: 1000)
    }

    @discardableResult
    private func addEntry(
        to account: Account,
        title: String,
        category: String?,
        amount: Decimal = -12,
        date: Date = Date()
    ) -> LedgerEntry {
        viewModel.addManualEntry(
            to: account,
            title: title,
            btcAmount: nil,
            usdAmount: amount,
            btcPriceAtTransaction: nil,
            date: date,
            notes: nil,
            isReconciled: true,
            category: category,
            isCreditOverride: amount >= 0
        )
    }

    func testSuggestedTitlesMatchPrefixMostRecentFirstAndDedupeCase() {
        let account = makeAccount()
        addEntry(to: account, title: "Starbucks", category: "Food & Dining", date: Date().addingTimeInterval(-86_400))
        addEntry(to: account, title: "starbucks", category: "Food & Dining", date: Date().addingTimeInterval(-3_600))
        addEntry(to: account, title: "Strike", category: "Investments")

        let suggestions = viewModel.suggestedTitles(prefix: "St")
        XCTAssertEqual(suggestions.first, "Strike")
        XCTAssertEqual(suggestions.filter { $0.lowercased() == "starbucks" }.count, 1)
    }

    func testSuggestedCategoryUsesLatestExactTitleAndIgnoresAmount() {
        let account = makeAccount()
        addEntry(to: account, title: "Starbucks", category: "Shopping", amount: -8, date: Date().addingTimeInterval(-86_400))
        addEntry(to: account, title: "Starbucks", category: "Food & Dining", amount: -14)

        XCTAssertEqual(viewModel.suggestedCategory(forTitle: "Starbucks"), "Food & Dining")
        XCTAssertEqual(viewModel.suggestedCategory(forTitle: "Star"), "Food & Dining")
        XCTAssertEqual(
            CategorySuggester.suggest(for: "Starbucks", priorCategory: viewModel.suggestedCategory(forTitle: "Starbucks")),
            "Food & Dining"
        )
    }

    func testSuggestedTitlesAreSharedAcrossAccounts() {
        let checking = makeAccount("Checking")
        let card = viewModel.addAccount(name: "Card", type: "credit", startingBalance: 0)
        addEntry(to: checking, title: "Netflix", category: "Subscriptions")

        XCTAssertEqual(viewModel.suggestedTitles(prefix: "Net", account: card), [])
        XCTAssertEqual(viewModel.suggestedTitles(prefix: "Net"), ["Netflix"])
        XCTAssertEqual(viewModel.suggestedCategory(forTitle: "Netflix"), "Subscriptions")
    }

    func testBulkSetCategoryLeavesOtherCategoriesAlone() {
        let account = makeAccount()
        addEntry(to: account, title: "Starbucks", category: nil)
        addEntry(to: account, title: "Starbucks", category: nil)
        addEntry(to: account, title: "Starbucks", category: "Shopping")

        XCTAssertEqual(viewModel.bulkSetCategory("Housing", forTitle: "Starbucks"), 2)

        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "title ==[cd] %@", "Starbucks")
        let entries = (try? persistence.container.viewContext.fetch(request)) ?? []
        let categories = entries.compactMap(\.category).sorted()
        XCTAssertEqual(categories, ["Housing", "Housing", "Shopping"])
    }

    func testBulkClearCategoryOnlyRemovesThatPayee() {
        let account = makeAccount()
        addEntry(to: account, title: "Starbucks", category: "Housing")
        addEntry(to: account, title: "Starbucks", category: "Housing")
        addEntry(to: account, title: "Mortgage", category: "Housing")

        XCTAssertEqual(viewModel.countEntries(withTitle: "Starbucks", category: "Housing"), 2)
        XCTAssertEqual(
            viewModel.bulkSetCategory(nil, forTitle: "Starbucks", matchingCategory: "Housing"),
            2
        )

        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        let entries = (try? persistence.container.viewContext.fetch(request)) ?? []
        let starbucks = entries.filter { ($0.title ?? "").localizedCaseInsensitiveCompare("Starbucks") == .orderedSame }
        let mortgage = entries.first { ($0.title ?? "") == "Mortgage" }
        XCTAssertTrue(starbucks.allSatisfy { $0.category == nil || $0.category?.isEmpty == true })
        XCTAssertEqual(mortgage?.category, "Housing")
    }
}

