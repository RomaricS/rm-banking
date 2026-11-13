import Foundation

/// ECB-based FX book. Rates are "units of quote per 1 EUR", per day.
/// Balances use the latest rate; transactions use the rate of their own date (or the closest earlier one).
public struct RateBook: Codable, Sendable {
    private var byDay: [Day: [String: Decimal]] = [:]
    private var sortedDays: [Day] = []

    public init(rates: [FXRate] = []) {
        for r in rates { byDay[r.date, default: [:]][r.quote] = r.rate }
        sortedDays = byDay.keys.sorted()
    }

    public var isEmpty: Bool { sortedDays.isEmpty }
    public var latestDay: Day? { sortedDays.last }

    private func table(on day: Day?) -> [String: Decimal]? {
        guard !sortedDays.isEmpty else { return nil }
        guard let day else { return byDay[sortedDays.last!] }
        // binary search: last day <= `day`
        var lo = 0, hi = sortedDays.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if sortedDays[mid] <= day { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return byDay[sortedDays[found >= 0 ? found : 0]]
    }

    /// Converts `amount` from one currency to another. Returns the amount unchanged if a rate is missing
    /// (the UI then shows the original currency rather than a wrong number).
    public func convert(_ amount: Decimal, from: String, to: String, on day: Day? = nil) -> Decimal {
        if from == to { return amount }
        guard let t = table(on: day) else { return amount }
        let rFrom: Decimal? = from == "EUR" ? 1 : t[from]
        let rTo: Decimal? = to == "EUR" ? 1 : t[to]
        guard let a = rFrom, let b = rTo, a != 0 else { return amount }
        return (amount / a * b).rounded(2)
    }

    public func canConvert(from: String, to: String) -> Bool {
        if from == to { return true }
        guard let t = table(on: nil) else { return false }
        return (from == "EUR" || t[from] != nil) && (to == "EUR" || t[to] != nil)
    }
}

public extension Decimal {
    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var x = self, r = Decimal()
        NSDecimalRound(&r, &x, scale, mode)
        return r
    }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
    var abs: Decimal { self < 0 ? -self : self }
}

/// Locale-aware money formatting ("$1,148", "1 148,00 €", "CA$64").
public enum MoneyFormat {
    public static func string(_ amount: Decimal, currency: String, locale: Locale = .current, cents: Bool? = nil, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currency
        let showCents = cents ?? (amount.abs < 1000 && amount.rounded(0) != amount)
        f.minimumFractionDigits = showCents ? 2 : 0
        f.maximumFractionDigits = showCents ? 2 : 0
        if signed { f.positivePrefix = "+" + f.positivePrefix }
        return f.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount) \(currency)"
    }

    /// Short form for charts and widgets: "$1.2k", "12 k€".
    public static func compact(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        let v = amount.doubleValue
        if Swift.abs(v) < 10_000 { return string(amount.rounded(0), currency: currency, locale: locale, cents: false) }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currency
        f.maximumFractionDigits = 1
        let s = f.string(from: NSNumber(value: v / 1000)) ?? "\(v / 1000)"
        // put the "k" right after the number, before a trailing symbol
        if let r = s.range(of: #"[\d.,\u{00A0}\u{202F}]+\d"#, options: .regularExpression) {
            return s.replacingCharacters(in: r, with: s[r] + "k")
        }
        return s + "k"
    }

    public static func symbol(for currency: String, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currency
        return f.currencySymbol ?? currency
    }
}

public let supportedDisplayCurrencies = ["USD", "CAD", "EUR", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "XOF", "JPY", "AUD"]
