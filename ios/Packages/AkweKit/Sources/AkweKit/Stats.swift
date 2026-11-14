import Foundation

public struct PocketTotal: Hashable, Identifiable, Sendable {
    public var id: UUID { pocket.id }
    public let pocket: Pocket
    public let amount: Decimal          // positive = spent
    public let share: Double            // of total spending
    public let previous: Decimal?
    public var change: Double? {
        guard let p = previous, p > 0 else { return nil }
        return ((amount - p) / p).doubleValue
    }
}

public struct CategoryTotal: Hashable, Identifiable, Sendable {
    public var id: UUID { category.id }
    public let category: TxCategory
    public let amount: Decimal
    public let count: Int
}

public struct MerchantTotal: Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let amount: Decimal
    public let count: Int
}

public struct PeriodSummary: Sendable {
    public let range: DayRange
    public let spent: Decimal            // positive
    public let income: Decimal           // positive
    public var net: Decimal { income - spent }
    public var savingsRate: Double? { income > 0 ? max(-1, (income - spent) / income).doubleValue : nil }
    public let byPocket: [PocketTotal]
    public let byCategory: [CategoryTotal]
    public let topMerchants: [MerchantTotal]
    public let byAccount: [(account: Account, amount: Decimal)]
    public let byMethod: [(method: PaymentMethod, amount: Decimal)]
    public let cumulative: [Decimal]     // spend so far, one value per day of the range (up to today)
    public let daily: [Decimal]          // spend per day
    public let transactionCount: Int
    public let largest: [Transaction]
}

public extension Ledger {
    /// Spending (positive) of one transaction: spends add, refunds subtract, income ignored.
    private func spendValue(_ t: Transaction) -> Decimal {
        switch t.kind {
        case .spend, .refund: return -value(t)
        default: return 0
        }
    }

    func summary(_ range: DayRange, previous: DayRange? = nil, today: Day = .today()) -> PeriodSummary {
        let txs = statTransactions(in: range)
        var spent: Decimal = 0, income: Decimal = 0
        var byPocket: [UUID: Decimal] = [:], byCat: [UUID: (Decimal, Int)] = [:]
        var byMerchant: [String: (Decimal, Int)] = [:], byAccount: [UUID: Decimal] = [:], byMethod: [PaymentMethod: Decimal] = [:]
        var daily = [Decimal](repeating: 0, count: range.length)

        for t in txs {
            if t.kind == .income { income += value(t); continue }
            let v = spendValue(t)
            spent += v
            if let c = category(t.categoryId) {
                byPocket[c.pocketId, default: 0] += v
                byCat[c.id, default: (0, 0)].0 += v
                byCat[c.id, default: (0, 0)].1 += 1
            }
            byMerchant[t.title, default: (0, 0)].0 += v
            byMerchant[t.title, default: (0, 0)].1 += 1
            byAccount[t.accountId, default: 0] += v
            byMethod[t.paymentMethod, default: 0] += v
            let idx = range.start.days(until: t.date)
            if idx >= 0 && idx < daily.count { daily[idx] += v }
        }

        var prevByPocket: [UUID: Decimal] = [:]
        if let previous {
            for t in statTransactions(in: previous) where t.kind != .income {
                if let c = category(t.categoryId) { prevByPocket[c.pocketId, default: 0] += spendValue(t) }
            }
        }

        let pocketTotals = pockets.filter { !$0.isIncome }.compactMap { p -> PocketTotal? in
            let amt = byPocket[p.id] ?? 0
            guard amt != 0 || (prevByPocket[p.id] ?? 0) != 0 else { return nil }
            return PocketTotal(pocket: p, amount: amt, share: spent > 0 ? (amt / spent).doubleValue : 0, previous: previous == nil ? nil : (prevByPocket[p.id] ?? 0))
        }.sorted { $0.amount > $1.amount }

        let lastIndex = min(range.length - 1, max(-1, range.start.days(until: today)))
        var cumulative: [Decimal] = []
        var running: Decimal = 0
        if lastIndex >= 0 {
            for i in 0...lastIndex { running += daily[i]; cumulative.append(running) }
        }

        return PeriodSummary(
            range: range, spent: spent, income: income,
            byPocket: pocketTotals,
            byCategory: byCat.compactMap { id, v in category(id).map { CategoryTotal(category: $0, amount: v.0, count: v.1) } }.sorted { $0.amount > $1.amount },
            topMerchants: byMerchant.map { MerchantTotal(name: $0.key, amount: $0.value.0, count: $0.value.1) }.sorted { $0.amount > $1.amount }.prefix(5).map { $0 },
            byAccount: byAccount.compactMap { id, v in account(id).map { ($0, v) } }.sorted { $0.1 > $1.1 },
            byMethod: byMethod.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 },
            cumulative: cumulative, daily: daily,
            transactionCount: txs.count,
            largest: txs.filter { $0.kind == .spend }.sorted { value($0) < value($1) }.prefix(3).map { $0 }
        )
    }

    /// Average cumulative spending curve over the last `count` complete periods of the same kind, by day index.
    func averageCumulative(_ kind: PeriodKind, today: Day = .today(), count: Int = 6) -> [Decimal] {
        let current = Periods.range(kind, containing: today, schedule: schedule)
        var curves: [[Decimal]] = []
        for i in 1...count {
            let r = Periods.range(kind, containing: today, schedule: schedule, offset: -i)
            guard transactions.contains(where: { r.contains($0.date) }) else { continue }
            curves.append(summary(r, today: r.end).cumulative)
        }
        guard !curves.isEmpty else { return [] }
        return (0..<current.length).map { i in
            let vals = curves.map { $0.isEmpty ? 0 : $0[min(i, $0.count - 1)] }
            return vals.reduce(0, +) / Decimal(vals.count)
        }
    }

    /// Spending for the last `count` periods (oldest first), for bar charts.
    /// The `count` periods ending with the one `offset` periods from now (0 = current).
    func history(_ kind: PeriodKind, today: Day = .today(), count: Int = 6, offset: Int = 0, pocketId: UUID? = nil) -> [(range: DayRange, spent: Decimal)] {
        (0..<count).reversed().map { i in
            let r = Periods.range(kind, containing: today, schedule: schedule, offset: offset - i)
            let s = summary(r, today: today)
            let v = pocketId.map { pid in s.byPocket.first { $0.pocket.id == pid }?.amount ?? 0 } ?? s.spent
            return (r, v)
        }
    }

    /// Spend per weekday (1 = Sunday … 7 = Saturday) over a range, for the heatmap.
    func weekdayPattern(_ range: DayRange) -> [Int: Decimal] {
        var out: [Int: Decimal] = [:]
        for t in statTransactions(in: range) where t.kind == .spend { out[t.date.weekday, default: 0] += -value(t) }
        return out
    }
}
