import Foundation

/// Everything the stats engine needs, in one value. Built by the app from the synced data.
public struct Ledger: Sendable {
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var categories: [TxCategory]
    public var pockets: [Pocket]
    public var budgets: [Budget]
    public var recurring: [RecurringStream]
    public var goals: [Goal]
    public var members: [GoalMember]
    public var rates: RateBook
    public var currency: String
    public var schedule: PaySchedule

    public init(accounts: [Account] = [], transactions: [Transaction] = [], categories: [TxCategory] = [], pockets: [Pocket] = [], budgets: [Budget] = [], recurring: [RecurringStream] = [], goals: [Goal] = [], members: [GoalMember] = [], rates: RateBook = RateBook(), currency: String = "USD", schedule: PaySchedule = PaySchedule(frequency: .monthly, anchorDate: Day(2026, 1, 1))) {
        self.accounts = accounts; self.transactions = transactions; self.categories = categories; self.pockets = pockets
        self.budgets = budgets; self.recurring = recurring; self.goals = goals; self.members = members
        self.rates = rates; self.currency = currency; self.schedule = schedule
    }

    // MARK: lookups
    public func category(_ id: UUID?) -> TxCategory? { id.flatMap { cid in categories.first { $0.id == cid } } }
    public func pocket(_ id: UUID?) -> Pocket? { id.flatMap { pid in pockets.first { $0.id == pid } } }
    public func pocket(for tx: Transaction) -> Pocket? { pocket(category(tx.categoryId)?.pocketId) }
    public func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }

    /// Transaction amount in the display currency (rate of its own date).
    public func value(_ tx: Transaction) -> Decimal {
        rates.convert(tx.amount, from: tx.currency, to: currency, on: tx.date)
    }

    /// Total of included accounts (assets − liabilities), today's rates.
    public var totalBalance: Decimal {
        accounts.filter(\.includeInTotals).reduce(0) { sum, a in
            sum + rates.convert(a.currentBalance ?? 0, from: a.currency, to: currency)
        }
    }

    public var netWorth: (assets: Decimal, liabilities: Decimal) {
        var assets: Decimal = 0, liabilities: Decimal = 0
        for a in accounts where a.includeInTotals {
            let v = rates.convert(a.currentBalance ?? 0, from: a.currency, to: currency)
            if v < 0 { liabilities += -v } else { assets += v }
        }
        return (assets, liabilities)
    }

    /// Transactions that count in stats inside a range (splits replace their parent).
    public func statTransactions(in range: DayRange) -> [Transaction] {
        let parentsWithSplits = Set(transactions.compactMap(\.splitParentId))
        return transactions.filter { range.contains($0.date) && $0.countsInStats && !parentsWithSplits.contains($0.id) }
    }

    public var needsReview: [Transaction] {
        transactions.filter { $0.needsReview && $0.kind == .spend && !$0.excluded }.sorted { $0.date > $1.date }
    }
}
