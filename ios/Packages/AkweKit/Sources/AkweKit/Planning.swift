import Foundation

// MARK: - Budgets

public enum BudgetState: String, Sendable { case onTrack, atRisk, over }

public struct BudgetStatus: Sendable, Identifiable {
    public var id: UUID { budget.id }
    public let budget: Budget
    public let name: String
    public let color: String
    public let range: DayRange
    public let spent: Decimal       // budget currency
    public var limit: Decimal { budget.amount }
    public var remaining: Decimal { limit - spent }
    public var fraction: Double { limit > 0 ? (spent / limit).doubleValue : 0 }
    public let elapsed: Double      // share of the period elapsed
    public let daysLeft: Int
    public var perDayLeft: Decimal { daysLeft > 0 ? max(0, remaining) / Decimal(daysLeft) : 0 }
    public var state: BudgetState {
        if spent > limit { return .over }
        if fraction >= 0.8 || fraction > elapsed + 0.15 { return .atRisk }
        return .onTrack
    }
}

public extension Ledger {
    func budgetStatus(_ b: Budget, today: Day = .today()) -> BudgetStatus {
        let range = b.period == .month ? Periods.month(containing: today) : schedule.period(containing: today)
        let catIds: Set<UUID> = b.categoryId.map { [$0] } ?? Set(categories.filter { $0.pocketId == b.pocketId }.map(\.id))
        let spent = statTransactions(in: range)
            .filter { ($0.kind == .spend || $0.kind == .refund) && $0.categoryId.map(catIds.contains) == true }
            .reduce(Decimal(0)) { $0 - rates.convert($1.amount, from: $1.currency, to: b.currency, on: $1.date) }
        let name = b.categoryId.flatMap { category($0)?.name } ?? pocket(b.pocketId)?.name ?? ""
        let color = pocket(b.pocketId ?? category(b.categoryId)?.pocketId)?.color ?? "#8B8B96"
        let elapsedDays = range.start.days(until: today) + 1
        return BudgetStatus(budget: b, name: name, color: color, range: range, spent: spent,
                            elapsed: min(1, Double(elapsedDays) / Double(range.length)),
                            daysLeft: max(0, today.days(until: range.end) + 1))
    }

    var budgetStatuses: [BudgetStatus] { budgets.map { budgetStatus($0) } }
}

// MARK: - Safe to spend

public struct SafeToSpend: Sendable {
    public let range: DayRange
    public let plan: Decimal            // what you intend to spend this pay period
    public let spent: Decimal
    public let billsDue: Decimal        // recurring outflows predicted before payday
    public let bills: [RecurringStream]
    public let daysLeft: Int
    public let paceDelta: Decimal?      // positive = under your usual pace
    public var left: Decimal { plan - spent - billsDue }
    public var perDay: Decimal { daysLeft > 0 ? max(0, left) / Decimal(daysLeft) : 0 }
    public var dayIndex: Int { range.length - daysLeft + 1 }
}

public extension Ledger {
    /// The amount you plan to spend per pay period: typical paycheck − what goals need, else recent average spend.
    func spendingPlan(today: Day = .today()) -> Decimal {
        let goalsNeed = goals.filter { $0.archivedAt == nil && $0.reachedAt == nil }
            .map { goalProgress($0, today: today).requiredPerPeriod ?? 0 }.reduce(0, +)
        if let income = schedule.typicalAmount, income > 0 {
            let base = rates.convert(income, from: accounts.first?.currency ?? currency, to: currency)
            return max(0, base - goalsNeed)
        }
        let hist = history(.payPeriod, today: today, count: 4).dropLast().map(\.spent).filter { $0 > 0 }
        if !hist.isEmpty { return hist.reduce(0, +) / Decimal(hist.count) }
        return budgets.filter { $0.period == .payPeriod }.reduce(0) { $0 + rates.convert($1.amount, from: $1.currency, to: currency) }
    }

    func safeToSpend(today: Day = .today()) -> SafeToSpend {
        let range = schedule.period(containing: today)
        let s = summary(range, today: today)
        let upcoming = recurring.filter { r in
            guard r.isActive, r.isOutflow, let next = r.predictedNextDate else { return false }
            return next > today && next <= range.end
        }
        let bills = upcoming.reduce(Decimal(0)) { $0 + rates.convert($1.lastAmount, from: $1.currency, to: currency) }
        let avg = averageCumulative(.payPeriod, today: today)
        let idx = range.start.days(until: today)
        let pace: Decimal? = avg.indices.contains(idx) ? avg[idx] - s.spent : nil
        return SafeToSpend(range: range, plan: spendingPlan(today: today), spent: s.spent, billsDue: bills,
                           bills: upcoming.sorted { ($0.predictedNextDate ?? today) < ($1.predictedNextDate ?? today) },
                           daysLeft: today.days(until: range.end) + 1, paceDelta: pace)
    }
}

// MARK: - Goals

public enum GoalStatus: Sendable, Equatable { case reached, onTrack, behind(extraPerPeriod: Decimal), noDeadline }

public struct GoalProgress: Sendable {
    public let goal: Goal
    public let saved: Decimal
    public let members: [GoalMember]
    public var target: Decimal { goal.targetAmount }
    public var fraction: Double { target > 0 ? min(1, (saved / target).doubleValue) : 0 }
    public var remaining: Decimal { max(0, target - saved) }
    public let periodsLeft: Int?
    public let requiredPerPeriod: Decimal?
    public let status: GoalStatus
    public var isShared: Bool { members.count > 1 }
    public var milestones: [(value: Int, reached: Bool)] { [25, 50, 75, 100].map { ($0, fraction * 100 >= Double($0)) } }
}

public extension Ledger {
    func goalProgress(_ goal: Goal, today: Day = .today()) -> GoalProgress {
        let ms = members.filter { $0.goalId == goal.id }
        let saved = ms.reduce(Decimal(0)) { sum, m in
            sum + (m.currentAmount ?? ((m.sharePct ?? 0) / 100 * goal.targetAmount))
        }
        let remaining = max(0, goal.targetAmount - saved)
        guard remaining > 0 else {
            return GoalProgress(goal: goal, saved: saved, members: ms, periodsLeft: 0, requiredPerPeriod: 0, status: .reached)
        }
        guard let deadline = goal.targetDate, deadline > today else {
            return GoalProgress(goal: goal, saved: saved, members: ms, periodsLeft: nil, requiredPerPeriod: nil, status: .noDeadline)
        }
        let periods = max(1, payPeriods(from: today, to: deadline))
        let required = (remaining / Decimal(periods)).rounded(0, .up)

        // On track if saved ≥ the straight line from creation to deadline (5 % tolerance).
        let start = Day(date: goal.createdAt)
        let total = max(1, start.days(until: deadline))
        let elapsed = max(0, start.days(until: today))
        let expected = goal.targetAmount * Decimal(elapsed) / Decimal(total)
        let status: GoalStatus
        if saved >= expected * Decimal(0.95) {
            status = .onTrack
        } else {
            let periodsElapsed = max(1, payPeriods(from: start, to: today))
            let actualPace = saved / Decimal(periodsElapsed)
            status = .behind(extraPerPeriod: max(0, required - actualPace).rounded(0, .up))
        }
        return GoalProgress(goal: goal, saved: saved, members: ms, periodsLeft: periods, requiredPerPeriod: required, status: status)
    }

    /// Number of paydays strictly after `from` up to and including `to`.
    func payPeriods(from: Day, to: Day) -> Int {
        guard to > from else { return 0 }
        var n = 0
        var p = schedule.period(containing: from)
        while p.end < to && n < 1000 { n += 1; p = schedule.period(containing: p.end.adding(days: 1)) }
        return max(1, n)
    }

    /// What-if: when would the goal be reached saving `perPeriod` every pay period from now?
    func arrival(remaining: Decimal, perPeriod: Decimal, today: Day = .today()) -> Day? {
        guard perPeriod > 0 else { return nil }
        let periods = Int(((remaining / perPeriod).doubleValue).rounded(.up))
        var p = schedule.period(containing: today)
        for _ in 0..<max(0, periods) { p = schedule.period(containing: p.end.adding(days: 1)) }
        return p.start
    }

    /// Average spend per pay period in a category (for the what-if slider).
    func averagePerPeriod(categoryId: UUID, today: Day = .today(), count: Int = 4) -> Decimal {
        var total: Decimal = 0
        for i in 1...count {
            let r = schedule.period(containing: today, offset: -i)
            total += statTransactions(in: r).filter { $0.categoryId == categoryId && $0.kind == .spend }.reduce(0) { $0 - value($1) }
        }
        return (total / Decimal(count)).rounded(0)
    }
}
