import Foundation

/// A calendar day without time or timezone ("2026-11-13"). All money math works on days,
/// which avoids the classic off-by-one bugs of `Date` + timezones.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int   // 1...12
    public let day: Int     // 1...31

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init?(_ string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }

    /// Today in the user's current timezone.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return Day(c.year!, c.month!, c.day!)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Noon UTC on this day (safe for formatting in any timezone).
    public var date: Date {
        Day.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Midnight local time — for display in the user's calendar.
    public func localDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    public func adding(days n: Int) -> Day {
        Day(date: Day.utc.date(byAdding: .day, value: n, to: date)!, calendar: Day.utc)
    }

    public func days(until other: Day) -> Int {
        Day.utc.dateComponents([.day], from: date, to: other.date).day!
    }

    public var weekday: Int { Day.utc.component(.weekday, from: date) } // 1 = Sunday

    public static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        let y = year + Int(floor(Double(month - 1) / 12))
        let m = ((month - 1) % 12 + 12) % 12 + 1
        return utc.range(of: .day, in: .month, for: utc.date(from: DateComponents(year: y, month: m, day: 1))!)!.count
    }

    /// Builds a day, normalising month overflow and clamping the day to the month length (31 → 28 in Feb).
    public static func clamped(_ year: Int, _ month: Int, _ day: Int) -> Day {
        let y = year + Int(floor(Double(month - 1) / 12))
        let m = ((month - 1) % 12 + 12) % 12 + 1
        return Day(y, m, min(day, daysInMonth(y, m)))
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // Codable as "YYYY-MM-DD"
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = Day(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Inclusive range of days.
public struct DayRange: Hashable, Codable, Sendable {
    public let start: Day
    public let end: Day
    public init(start: Day, end: Day) { self.start = start; self.end = end }
    public func contains(_ d: Day) -> Bool { d >= start && d <= end }
    public var length: Int { start.days(until: end) + 1 }
    public var days: [Day] { (0..<length).map { start.adding(days: $0) } }
}
