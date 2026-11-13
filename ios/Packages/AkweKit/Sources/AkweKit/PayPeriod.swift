import Foundation

/// Pay period math. Mirrors backend/supabase/functions/_shared/payPeriod.ts — keep both in sync.
public enum PeriodKind: String, CaseIterable, Codable, Sendable {
    case payPeriod, month, week, year
}

public extension PaySchedule {
    func period(containing date: Day) -> DayRange {
        switch frequency {
        case .weekly, .biweekly:
            let len = frequency == .weekly ? 7 : 14
            let diff = anchorDate.days(until: date)
            let k = Int(floor(Double(diff) / Double(len)))
            let start = anchorDate.adding(days: k * len)
            return DayRange(start: start, end: start.adding(days: len - 1))

        case .semimonthly:
            let days = (semimonthlyDays.count == 2 ? semimonthlyDays : [1, 15]).sorted()
            let y = date.year, m = date.month
            let candidates = [
                Day.clamped(y, m - 1, days[1]), Day.clamped(y, m, days[0]),
                Day.clamped(y, m, days[1]), Day.clamped(y, m + 1, days[0]),
            ]
            for i in stride(from: candidates.count - 2, through: 0, by: -1) where candidates[i] <= date {
                return DayRange(start: candidates[i], end: candidates[i + 1].adding(days: -1))
            }
            return DayRange(start: candidates[0], end: candidates[1].adding(days: -1))

        case .monthly:
            let anchorDay = anchorDate.day
            var start = Day.clamped(date.year, date.month, anchorDay)
            if start > date { start = Day.clamped(date.year, date.month - 1, anchorDay) }
            let next = Day.clamped(start.year, start.month + 1, anchorDay)
            return DayRange(start: start, end: next.adding(days: -1))
        }
    }

    /// The period `offset` steps away (−1 = previous).
    func period(containing date: Day, offset: Int) -> DayRange {
        var p = period(containing: date)
        if offset < 0 { for _ in 0..<(-offset) { p = period(containing: p.start.adding(days: -1)) } }
        if offset > 0 { for _ in 0..<offset { p = period(containing: p.end.adding(days: 1)) } }
        return p
    }

    func nextPayday(after today: Day) -> Day { period(containing: today).end.adding(days: 1) }
}

public enum Periods {
    public static func month(containing d: Day) -> DayRange {
        DayRange(start: Day(d.year, d.month, 1), end: Day(d.year, d.month, Day.daysInMonth(d.year, d.month)))
    }

    /// ISO-ish week starting Monday.
    public static func week(containing d: Day) -> DayRange {
        let back = (d.weekday + 5) % 7 // Monday → 0
        let start = d.adding(days: -back)
        return DayRange(start: start, end: start.adding(days: 6))
    }

    public static func year(containing d: Day) -> DayRange {
        DayRange(start: Day(d.year, 1, 1), end: Day(d.year, 12, 31))
    }

    public static func range(_ kind: PeriodKind, containing d: Day, schedule: PaySchedule, offset: Int = 0) -> DayRange {
        switch kind {
        case .payPeriod:
            return schedule.period(containing: d, offset: offset)
        case .month:
            var r = month(containing: d)
            if offset != 0 {
                let target = Day.clamped(d.year, d.month + offset, 1)
                r = month(containing: target)
            }
            return r
        case .week:
            return week(containing: d.adding(days: 7 * offset))
        case .year:
            return year(containing: Day(d.year + offset, 1, 1))
        }
    }

    /// Detect a pay schedule from paycheck dates (mirror of detectSchedule in TS).
    public static func detectSchedule(paydays: [Day]) -> PaySchedule? {
        let ds = Array(Set(paydays)).sorted()
        guard ds.count >= 3, let last = ds.last else { return nil }
        let gaps = zip(ds, ds.dropFirst()).map { $0.days(until: $1) }
        let median = gaps.sorted()[gaps.count / 2]
        switch median {
        case 6...8: return PaySchedule(frequency: .weekly, anchorDate: last, detected: true)
        case 26...33: return PaySchedule(frequency: .monthly, anchorDate: last, detected: true)
        case 12...17:
            var clusters: [[Int]] = []
            for d in ds.map(\.day).sorted() {
                if let i = clusters.firstIndex(where: { abs($0[0] - d) <= 3 }) { clusters[i].append(d) } else { clusters.append([d]) }
            }
            let exactTwoWeeks = gaps.filter { $0 == 14 }.count >= Int((Double(gaps.count) * 0.6).rounded(.up))
            if !exactTwoWeeks && clusters.count == 2 {
                let days = clusters.map { $0.min()! }.sorted()
                return PaySchedule(frequency: .semimonthly, anchorDate: last, semimonthlyDays: days, detected: true)
            }
            return PaySchedule(frequency: .biweekly, anchorDate: last, detected: true)
        default: return nil
        }
    }
}
