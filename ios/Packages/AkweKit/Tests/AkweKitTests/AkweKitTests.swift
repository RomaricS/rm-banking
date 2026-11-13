import XCTest
@testable import AkweKit

final class DayAndPeriodTests: XCTestCase {
    func testDayMath() {
        XCTAssertEqual(Day("2026-11-13")!.adding(days: 8).description, "2026-11-21")
        XCTAssertEqual(Day(2026, 2, 28).adding(days: 1), Day(2026, 3, 1))
        XCTAssertEqual(Day(2026, 11, 7).days(until: Day(2026, 11, 20)), 13)
        XCTAssertEqual(Day.clamped(2026, 2, 31), Day(2026, 2, 28))
        XCTAssertEqual(Day.clamped(2026, 13, 5), Day(2027, 1, 5))
        XCTAssertEqual(Day.clamped(2026, 0, 31), Day(2025, 12, 31))
    }

    func testPayPeriodsMatchBackend() {
        let bi = PaySchedule(frequency: .biweekly, anchorDate: Day(2026, 11, 7))
        XCTAssertEqual(bi.period(containing: Day(2026, 11, 13)), DayRange(start: Day(2026, 11, 7), end: Day(2026, 11, 20)))
        XCTAssertEqual(bi.period(containing: Day(2026, 11, 6)), DayRange(start: Day(2026, 10, 24), end: Day(2026, 11, 6)))
        XCTAssertEqual(bi.period(containing: Day(2026, 11, 13), offset: -1).start, Day(2026, 10, 24))
        XCTAssertEqual(bi.nextPayday(after: Day(2026, 11, 13)), Day(2026, 11, 21))

        let semi = PaySchedule(frequency: .semimonthly, anchorDate: Day(2026, 11, 1), semimonthlyDays: [1, 15])
        XCTAssertEqual(semi.period(containing: Day(2026, 11, 13)), DayRange(start: Day(2026, 11, 1), end: Day(2026, 11, 14)))
        XCTAssertEqual(semi.period(containing: Day(2026, 11, 20)), DayRange(start: Day(2026, 11, 15), end: Day(2026, 11, 30)))

        let mo = PaySchedule(frequency: .monthly, anchorDate: Day(2026, 1, 31))
        XCTAssertEqual(mo.period(containing: Day(2026, 2, 28)), DayRange(start: Day(2026, 2, 28), end: Day(2026, 3, 30)))
        XCTAssertEqual(mo.period(containing: Day(2026, 2, 10)), DayRange(start: Day(2026, 1, 31), end: Day(2026, 2, 27)))
    }

    func testCalendarPeriods() {
        XCTAssertEqual(Periods.month(containing: Day(2026, 2, 10)), DayRange(start: Day(2026, 2, 1), end: Day(2026, 2, 28)))
        XCTAssertEqual(Periods.week(containing: Day(2026, 11, 13)).start, Day(2026, 11, 9)) // Monday
        let s = PaySchedule(frequency: .monthly, anchorDate: Day(2026, 1, 1))
        XCTAssertEqual(Periods.range(.month, containing: Day(2026, 1, 15), schedule: s, offset: -1).start, Day(2025, 12, 1))
    }

    func testScheduleDetection() {
        XCTAssertEqual(Periods.detectSchedule(paydays: ["2026-10-10", "2026-10-24", "2026-11-07", "2026-11-21"].map { Day($0)! })?.frequency, .biweekly)
        XCTAssertEqual(Periods.detectSchedule(paydays: ["2026-09-01", "2026-09-15", "2026-10-01", "2026-10-15", "2026-11-01"].map { Day($0)! })?.frequency, .semimonthly)
        XCTAssertEqual(Periods.detectSchedule(paydays: ["2026-08-28", "2026-09-28", "2026-10-28"].map { Day($0)! })?.frequency, .monthly)
        XCTAssertNil(Periods.detectSchedule(paydays: [Day(2026, 11, 1)]))
    }
}

final class NormalizerTests: XCTestCase {
    // Same cases as backend tests/shared_test.ts — rules created on device must match server keys.
    func testMerchantKeysMatchBackend() {
        XCTAssertEqual(MerchantNormalizer.key("ACHAT CB MONOPRIX 12/11 CARTE 9910"), "monoprix")
        XCTAssertEqual(MerchantNormalizer.key("SQ *BLUE BOTTLE COFFEE 0423"), "blue bottle coffee")
        XCTAssertEqual(MerchantNormalizer.key("PRLV SEPA EDF"), "edf")
        XCTAssertEqual(MerchantNormalizer.key("Uber"), MerchantNormalizer.key("UBER"))
        XCTAssertEqual(MerchantNormalizer.key("Café Pouchkine"), "cafe pouchkine")
    }
}

final class MoneyTests: XCTestCase {
    func testRateBookUsesDateRate() {
        let book = RateBook(rates: [
            FXRate(date: Day(2026, 11, 1), quote: "USD", rate: 1.10),
            FXRate(date: Day(2026, 11, 10), quote: "USD", rate: 1.05),
            FXRate(date: Day(2026, 11, 10), quote: "CAD", rate: 1.50),
        ])
        XCTAssertEqual(book.convert(100, from: "EUR", to: "USD", on: Day(2026, 11, 5)), 110)
        XCTAssertEqual(book.convert(100, from: "EUR", to: "USD", on: Day(2026, 11, 12)), 105)
        XCTAssertEqual(book.convert(100, from: "EUR", to: "USD"), 105) // latest
        XCTAssertEqual(book.convert(150, from: "CAD", to: "EUR"), 100)
        XCTAssertEqual(book.convert(42, from: "XXX", to: "USD"), 42)    // unknown → unchanged
    }

    func testFormatting() {
        let us = Locale(identifier: "en_US"), fr = Locale(identifier: "fr_FR")
        XCTAssertEqual(MoneyFormat.string(1148, currency: "USD", locale: us), "$1,148")
        XCTAssertEqual(MoneyFormat.string(6.4, currency: "USD", locale: us), "$6.40")
        XCTAssertTrue(MoneyFormat.string(12480.32, currency: "EUR", locale: fr, cents: true).hasSuffix("€"))
        XCTAssertEqual(MoneyFormat.string(3250, currency: "USD", locale: us, signed: true), "+$3,250")
    }
}

// MARK: - Fixtures

enum Fixture {
    static let home = Pocket(id: UUID(), key: "home", name: "Home", color: "#7C9CFF", sort: 1)
    static let food = Pocket(id: UUID(), key: "food", name: "Food", color: "#FF9F5A", sort: 2)
    static let income = Pocket(id: UUID(), key: "income", name: "Income", isIncome: true, sort: 9)
    static let groceries = TxCategory(id: UUID(), pocketId: food.id, key: "groceries", name: "Groceries")
    static let coffee = TxCategory(id: UUID(), pocketId: food.id, key: "coffee", name: "Coffee")
    static let utilities = TxCategory(id: UUID(), pocketId: home.id, key: "utilities", name: "Utilities")
    static let paycheck = TxCategory(id: UUID(), pocketId: income.id, key: "paycheck", name: "Paycheck")
    static let checking = Account(id: UUID(), itemId: UUID(), name: "Checking", type: "depository", subtype: "checking", currency: "USD", currentBalance: 4212.18)
    static let savings = Account(id: UUID(), itemId: UUID(), name: "Savings", type: "depository", subtype: "savings", currency: "USD", currentBalance: 6950)
    static let card = Account(id: UUID(), itemId: UUID(), name: "Card", type: "credit", currency: "USD", currentBalance: -842.40)
    static let lbp = Account(id: UUID(), itemId: UUID(), name: "Compte", type: "depository", currency: "EUR", currentBalance: 1000)
    static let schedule = PaySchedule(frequency: .biweekly, anchorDate: Day(2026, 11, 7), typicalAmount: 3250)
    static let today = Day(2026, 11, 13)

    static func tx(_ amount: Decimal, _ cat: TxCategory?, _ date: Day, kind: TxKind = .spend, account: Account = checking, name: String = "Shop", currency: String = "USD") -> Transaction {
        Transaction(accountId: account.id, amount: amount, currency: currency, date: date, rawName: name, kind: kind, categoryId: cat?.id)
    }

    static func ledger(_ txs: [Transaction], budgets: [Budget] = [], goals: [Goal] = [], members: [GoalMember] = [], recurring: [RecurringStream] = []) -> Ledger {
        Ledger(accounts: [checking, savings, card, lbp], transactions: txs, categories: [groceries, coffee, utilities, paycheck],
               pockets: [home, food, income], budgets: budgets, recurring: recurring, goals: goals, members: members,
               rates: RateBook(rates: [FXRate(date: Day(2026, 11, 1), quote: "USD", rate: 1.08)]), currency: "USD", schedule: schedule)
    }
}

final class StatsTests: XCTestCase {
    func testSummaryExcludesTransfersAndCountsRefunds() {
        let d = Day(2026, 11, 10)
        let l = Fixture.ledger([
            Fixture.tx(-100, Fixture.groceries, d),
            Fixture.tx(-6.4, Fixture.coffee, d),
            Fixture.tx(10, Fixture.groceries, d, kind: .refund),
            Fixture.tx(-500, nil, d, kind: .transfer),
            Fixture.tx(-842.4, nil, d, kind: .cardPayment),
            Fixture.tx(3250, Fixture.paycheck, Day(2026, 11, 7), kind: .income),
            Fixture.tx(-50, Fixture.utilities, Day(2026, 11, 1)),                    // previous period
            { var t = Fixture.tx(-999, Fixture.groceries, d); t.excluded = true; return t }(),
        ])
        let range = Fixture.schedule.period(containing: Fixture.today)
        let s = l.summary(range, previous: Fixture.schedule.period(containing: Fixture.today, offset: -1), today: Fixture.today)
        XCTAssertEqual(s.spent, Decimal(96.4))
        XCTAssertEqual(s.income, 3250)
        XCTAssertEqual(s.byPocket.first?.pocket.name, "Food")
        XCTAssertEqual(s.byPocket.first?.amount, Decimal(96.4))
        XCTAssertEqual(s.byPocket.first { $0.pocket.name == "Home" }?.previous, 50)
        XCTAssertEqual(s.cumulative.count, 7)        // Nov 7…13
        XCTAssertEqual(s.cumulative.last, Decimal(96.4))
        XCTAssertEqual(s.savingsRate!, (3250 - 96.4) / 3250, accuracy: 0.0001)
    }

    func testForeignCurrencyConvertedAtTransactionDate() {
        let l = Fixture.ledger([Fixture.tx(-100, Fixture.groceries, Day(2026, 11, 10), account: Fixture.lbp, currency: "EUR")])
        XCTAssertEqual(l.summary(Fixture.schedule.period(containing: Fixture.today), today: Fixture.today).spent, 108)
    }

    func testTotalBalanceAssetsMinusLiabilities() {
        let l = Fixture.ledger([])
        XCTAssertEqual(l.totalBalance, Decimal(4212.18) + 6950 - Decimal(842.40) + 1080)
    }
}

final class PlanningTests: XCTestCase {
    func testBudgetStates() {
        let b = Budget(pocketId: Fixture.food.id, amount: 100, currency: "USD")
        let under = Fixture.ledger([Fixture.tx(-20, Fixture.groceries, Day(2026, 11, 8))], budgets: [b])
        XCTAssertEqual(under.budgetStatus(b, today: Fixture.today).state, .onTrack)
        let close = Fixture.ledger([Fixture.tx(-85, Fixture.coffee, Day(2026, 11, 8))], budgets: [b])
        XCTAssertEqual(close.budgetStatus(b, today: Fixture.today).state, .atRisk)
        let over = Fixture.ledger([Fixture.tx(-130, Fixture.groceries, Day(2026, 11, 8))], budgets: [b])
        let st = over.budgetStatus(b, today: Fixture.today)
        XCTAssertEqual(st.state, .over)
        XCTAssertEqual(st.daysLeft, 8)
    }

    func testSafeToSpend() {
        let rent = RecurringStream(accountId: Fixture.checking.id, description: "Rent", averageAmount: 850, lastAmount: 850, currency: "USD", predictedNextDate: Day(2026, 11, 14))
        let later = RecurringStream(accountId: Fixture.checking.id, description: "Gym", averageAmount: 45, lastAmount: 45, currency: "USD", predictedNextDate: Day(2026, 11, 25))
        let l = Fixture.ledger([Fixture.tx(-1148, Fixture.groceries, Day(2026, 11, 9))], recurring: [rent, later])
        let s = l.safeToSpend(today: Fixture.today)
        XCTAssertEqual(s.plan, 3250)
        XCTAssertEqual(s.billsDue, 850)          // gym is after payday
        XCTAssertEqual(s.daysLeft, 8)
        XCTAssertEqual(s.left, 3250 - 1148 - 850)
        XCTAssertEqual(s.perDay, Decimal(1252) / 8)
    }

    func testGoalProgressAndWhatIf() {
        let owner = UUID()
        var goal = Goal(ownerId: owner, name: "Japan", targetAmount: 6000, currency: "USD", targetDate: Day(2027, 6, 1))
        goal.createdAt = Day(2026, 5, 1).date
        let members = [GoalMember(goalId: goal.id, userId: owner, currentAmount: 3400)]
        let l = Fixture.ledger([], goals: [goal], members: members)
        let p = l.goalProgress(goal, today: Fixture.today)
        XCTAssertEqual(p.saved, 3400)
        XCTAssertEqual(p.remaining, 2600)
        XCTAssertEqual(p.periodsLeft, 14)
        XCTAssertEqual(p.requiredPerPeriod, 186)  // 2600 / 14 rounded up
        XCTAssertEqual(p.status, .onTrack)
        // what-if: 256.8 / period → 11 periods
        let arrival = l.arrival(remaining: 2600, perPeriod: Decimal(256.8), today: Fixture.today)!
        XCTAssertEqual(arrival, Day(2027, 4, 10))
    }

    func testSharedGoalWithHiddenPartnerAmount() {
        let a = UUID(), b = UUID()
        let goal = Goal(ownerId: a, name: "Apartment", targetAmount: 20000, currency: "USD")
        let l = Fixture.ledger([], goals: [goal], members: [
            GoalMember(goalId: goal.id, userId: a, currentAmount: 5200, sharePct: 26),
            GoalMember(goalId: goal.id, userId: b, role: "partner", currentAmount: nil, sharePct: 19),
        ])
        let p = l.goalProgress(goal, today: Fixture.today)
        XCTAssertEqual(p.saved, 9000)
        XCTAssertTrue(p.isShared)
        XCTAssertEqual(p.status, .noDeadline)
    }

    func testWidgetSnapshot() {
        let l = Fixture.ledger([Fixture.tx(-412, Fixture.groceries, Day(2026, 11, 9))])
        let w = l.widgetSnapshot(hideBalances: false, today: Fixture.today)
        XCTAssertEqual(w.daysToPayday, 8)
        XCTAssertEqual(w.periodSpent, 412)
        XCTAssertEqual(w.pockets.first?.name, "Food")
        let data = try! JSONEncoder().encode(w)
        XCTAssertNoThrow(try JSONDecoder().decode(WidgetSnapshot.self, from: data))
    }

    func testDecodingServerRows() throws {
        let json = """
        {"id":"0b0f8e2a-1111-4c3b-9a55-1f2f3a4b5c6d","account_id":"0b0f8e2a-2222-4c3b-9a55-1f2f3a4b5c6d","pending":false,
         "amount":-6.4,"currency":"USD","date":"2026-11-13","raw_name":"SQ *BLUE DOOR","merchant_name":"Blue Door Coffee",
         "logo_url":null,"payment_method":"debit_card","kind":"spend","category_id":null,"category_source":"plaid",
         "needs_review":false,"transfer_pair_id":null,"excluded":false,"note":null,"tags":[],"split_parent_id":null,
         "payment_channel":"in store","some_future_column":1,"unknown_enum_test":"x"}
        """
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        let t = try d.decode(Transaction.self, from: Data(json.utf8))
        XCTAssertEqual(t.paymentMethod, .debitCard)
        XCTAssertEqual(t.date, Day(2026, 11, 13))
        let k = try d.decode(TxKind.self, from: Data("\"brand_new_kind\"".utf8))
        XCTAssertEqual(k, .spend)
    }
}
