import Foundation
import AkweKit

/// Looks up a key in Localizable.strings (en / fr). Keys are dotted ids; the English and French
/// texts live in tools/strings.py, which generates both .strings files.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}

/// Money in the user's locale.
func money(_ amount: Decimal, _ currency: String, cents: Bool? = nil, signed: Bool = false) -> String {
    MoneyFormat.string(amount, currency: currency, locale: .current, cents: cents, signed: signed)
}

extension Day {
    /// "Nov 13" / "13 nov."
    var short: String { localDate().formatted(.dateTime.month(.abbreviated).day()) }
    /// "Thursday, November 13"
    var long: String { localDate().formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    /// "Fri, Nov 21"
    var medium: String { localDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    /// "June 2027"
    var monthYear: String { localDate().formatted(.dateTime.month(.wide).year()) }
    /// "Jun 1, 2027"
    var full: String { localDate().formatted(date: .abbreviated, time: .omitted) }

    /// "Today", "Yesterday", or "Fri, Nov 7"
    func relativeLabel(today: Day = .today()) -> String {
        if self == today { return tr("common.today") }
        if self == today.adding(days: -1) { return tr("common.yesterday") }
        return medium
    }
}

extension DayRange {
    /// "Nov 7 – Nov 20"
    var label: String { "\(start.short) – \(end.short)" }
}

extension PaymentMethod {
    var label: String { tr("method.\(rawValue)") }
    var icon: String {
        switch self {
        case .debitCard: "creditcard"
        case .creditCard: "creditcard.fill"
        case .deferredCard: "calendar.badge.clock"
        case .directDebit: "arrow.triangle.2.circlepath"
        case .transfer: "arrow.left.arrow.right"
        case .atm: "banknote"
        case .check: "doc.text"
        case .other: "circle.dashed"
        }
    }
}

extension TxKind {
    var badge: String? {
        switch self {
        case .transfer: tr("kind.transfer")
        case .cardPayment: tr("kind.cardPayment")
        case .cardSettlement: tr("kind.cardSettlement")
        case .refund: tr("kind.refund")
        default: nil
        }
    }
}

extension PayFrequency {
    var label: String { tr("pay.\(rawValue)") }
}
