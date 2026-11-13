import Foundation

// Mirrors of the Supabase tables (decoded with .convertFromSnakeCase).
// Unknown enum values from the server decode to a safe fallback instead of failing.

public protocol FallbackEnum: RawRepresentable, Codable where RawValue == String {
    static var fallback: Self { get }
}
public extension FallbackEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

public enum PayFrequency: String, FallbackEnum, CaseIterable, Sendable {
    case weekly, biweekly, semimonthly, monthly
    public static let fallback = PayFrequency.monthly
}

public enum ItemStatus: String, FallbackEnum, Sendable {
    case ok, loginRequired = "login_required", pendingExpiration = "pending_expiration", error, revoked
    public static let fallback = ItemStatus.error
    public var needsAttention: Bool { self != .ok }
}

public enum CardKind: String, FallbackEnum, CaseIterable, Sendable {
    case debit, credit, deferred
    public static let fallback = CardKind.debit
}

public enum PaymentMethod: String, FallbackEnum, CaseIterable, Sendable {
    case debitCard = "debit_card", creditCard = "credit_card", deferredCard = "deferred_card"
    case directDebit = "direct_debit", transfer, atm, check, other
    public static let fallback = PaymentMethod.other
}

public enum TxKind: String, FallbackEnum, CaseIterable, Sendable {
    case spend, income, transfer, cardPayment = "card_payment", cardSettlement = "card_settlement", refund
    public static let fallback = TxKind.spend
    /// Counts in spending / income stats (money really leaving or entering your world).
    public var countsInStats: Bool { self == .spend || self == .income || self == .refund }
}

public enum CategorySource: String, FallbackEnum, Sendable {
    case plaid, rule, user, `default`
    public static let fallback = CategorySource.default
}

public enum BudgetPeriod: String, FallbackEnum, CaseIterable, Sendable {
    case payPeriod = "pay_period", month
    public static let fallback = BudgetPeriod.payPeriod
}

public enum GoalFunding: String, FallbackEnum, CaseIterable, Sendable {
    case account, earmark, manual
    public static let fallback = GoalFunding.manual
}

public enum Appearance: String, FallbackEnum, CaseIterable, Sendable {
    case system, light, dark
    public static let fallback = Appearance.system
}

public struct Profile: Codable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String?
    public var displayCurrency: String
    public var appearance: Appearance
    public var countryCodes: [String]
    public var onboardedAt: Date?
    public init(id: UUID, displayName: String? = nil, displayCurrency: String = "USD", appearance: Appearance = .system, countryCodes: [String] = ["US", "CA", "FR"], onboardedAt: Date? = nil) {
        self.id = id; self.displayName = displayName; self.displayCurrency = displayCurrency
        self.appearance = appearance; self.countryCodes = countryCodes; self.onboardedAt = onboardedAt
    }
}

public struct PaySchedule: Codable, Hashable, Sendable {
    public var frequency: PayFrequency
    public var anchorDate: Day
    public var semimonthlyDays: [Int]
    public var incomeSource: String?
    public var typicalAmount: Decimal?
    public var detected: Bool
    public init(frequency: PayFrequency, anchorDate: Day, semimonthlyDays: [Int] = [1, 15], incomeSource: String? = nil, typicalAmount: Decimal? = nil, detected: Bool = false) {
        self.frequency = frequency; self.anchorDate = anchorDate; self.semimonthlyDays = semimonthlyDays
        self.incomeSource = incomeSource; self.typicalAmount = typicalAmount; self.detected = detected
    }
}

public struct BankItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var institutionName: String
    public var institutionId: String?
    public var country: String?
    public var status: ItemStatus
    public var lastSyncedAt: Date?
    public init(id: UUID, institutionName: String, institutionId: String? = nil, country: String? = nil, status: ItemStatus = .ok, lastSyncedAt: Date? = nil) {
        self.id = id; self.institutionName = institutionName; self.institutionId = institutionId
        self.country = country; self.status = status; self.lastSyncedAt = lastSyncedAt
    }
}

public struct Account: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var itemId: UUID
    public var name: String
    public var nickname: String?
    public var mask: String?
    public var type: String
    public var subtype: String?
    public var currency: String
    public var currentBalance: Decimal?
    public var availableBalance: Decimal?
    public var creditLimit: Decimal?
    public var cardKind: CardKind?
    public var includeInTotals: Bool
    public var color: String?
    public var sort: Int

    public init(id: UUID, itemId: UUID, name: String, nickname: String? = nil, mask: String? = nil, type: String, subtype: String? = nil, currency: String, currentBalance: Decimal? = nil, availableBalance: Decimal? = nil, creditLimit: Decimal? = nil, cardKind: CardKind? = nil, includeInTotals: Bool = true, color: String? = nil, sort: Int = 0) {
        self.id = id; self.itemId = itemId; self.name = name; self.nickname = nickname; self.mask = mask
        self.type = type; self.subtype = subtype; self.currency = currency; self.currentBalance = currentBalance
        self.availableBalance = availableBalance; self.creditLimit = creditLimit; self.cardKind = cardKind
        self.includeInTotals = includeInTotals; self.color = color; self.sort = sort
    }

    public var displayName: String { nickname ?? name }
    public var isCredit: Bool { type == "credit" }
    public var isLiability: Bool { type == "credit" || type == "loan" }
}

public struct Pocket: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var key: String?
    public var name: String
    public var icon: String
    public var color: String
    public var isIncome: Bool
    public var sort: Int
    public init(id: UUID, key: String? = nil, name: String, icon: String = "circle", color: String = "#8B8B96", isIncome: Bool = false, sort: Int = 0) {
        self.id = id; self.key = key; self.name = name; self.icon = icon; self.color = color; self.isIncome = isIncome; self.sort = sort
    }
}

public struct Category: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var pocketId: UUID
    public var key: String?
    public var name: String
    public var icon: String
    public var sort: Int
    public var archived: Bool
    public init(id: UUID, pocketId: UUID, key: String? = nil, name: String, icon: String = "circle", sort: Int = 0, archived: Bool = false) {
        self.id = id; self.pocketId = pocketId; self.key = key; self.name = name; self.icon = icon; self.sort = sort; self.archived = archived
    }
}

public struct Transaction: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var accountId: UUID
    public var pending: Bool
    public var amount: Decimal          // signed: negative = money out
    public var currency: String
    public var date: Day
    public var rawName: String
    public var merchantName: String?
    public var logoUrl: String?
    public var paymentMethod: PaymentMethod
    public var kind: TxKind
    public var categoryId: UUID?
    public var categorySource: CategorySource
    public var needsReview: Bool
    public var transferPairId: UUID?
    public var excluded: Bool
    public var note: String?
    public var tags: [String]
    public var splitParentId: UUID?
    public var paymentChannel: String?

    public init(id: UUID = UUID(), accountId: UUID, pending: Bool = false, amount: Decimal, currency: String, date: Day, rawName: String, merchantName: String? = nil, logoUrl: String? = nil, paymentMethod: PaymentMethod = .other, kind: TxKind = .spend, categoryId: UUID? = nil, categorySource: CategorySource = .default, needsReview: Bool = false, transferPairId: UUID? = nil, excluded: Bool = false, note: String? = nil, tags: [String] = [], splitParentId: UUID? = nil, paymentChannel: String? = nil) {
        self.id = id; self.accountId = accountId; self.pending = pending; self.amount = amount; self.currency = currency
        self.date = date; self.rawName = rawName; self.merchantName = merchantName; self.logoUrl = logoUrl
        self.paymentMethod = paymentMethod; self.kind = kind; self.categoryId = categoryId; self.categorySource = categorySource
        self.needsReview = needsReview; self.transferPairId = transferPairId; self.excluded = excluded; self.note = note
        self.tags = tags; self.splitParentId = splitParentId; self.paymentChannel = paymentChannel
    }

    public var title: String { merchantName ?? rawName }
    /// Included in spending/income totals.
    public var countsInStats: Bool { !excluded && kind.countsInStats }
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var merchantKey: String
    public var accountId: UUID?
    public var categoryId: UUID
    public var renameTo: String?
    public init(id: UUID = UUID(), merchantKey: String, accountId: UUID? = nil, categoryId: UUID, renameTo: String? = nil) {
        self.id = id; self.merchantKey = merchantKey; self.accountId = accountId; self.categoryId = categoryId; self.renameTo = renameTo
    }
}

public struct RecurringStream: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var accountId: UUID
    public var direction: String
    public var description: String
    public var merchantName: String?
    public var frequency: String
    public var averageAmount: Decimal
    public var lastAmount: Decimal
    public var previousAmount: Decimal?
    public var currency: String
    public var lastDate: Day?
    public var predictedNextDate: Day?
    public var isActive: Bool
    public var categoryId: UUID?
    public init(id: UUID = UUID(), accountId: UUID, direction: String = "outflow", description: String, merchantName: String? = nil, frequency: String = "MONTHLY", averageAmount: Decimal, lastAmount: Decimal, previousAmount: Decimal? = nil, currency: String, lastDate: Day? = nil, predictedNextDate: Day? = nil, isActive: Bool = true, categoryId: UUID? = nil) {
        self.id = id; self.accountId = accountId; self.direction = direction; self.description = description
        self.merchantName = merchantName; self.frequency = frequency; self.averageAmount = averageAmount
        self.lastAmount = lastAmount; self.previousAmount = previousAmount; self.currency = currency
        self.lastDate = lastDate; self.predictedNextDate = predictedNextDate; self.isActive = isActive; self.categoryId = categoryId
    }
    public var title: String { merchantName ?? description }
    public var isOutflow: Bool { direction == "outflow" }
    public var priceIncrease: Decimal? {
        guard let prev = previousAmount, lastAmount > prev else { return nil }
        return lastAmount - prev
    }
    /// Monthly equivalent cost (Plaid frequencies: WEEKLY, BIWEEKLY, SEMI_MONTHLY, MONTHLY, ANNUALLY).
    public var monthlyAmount: Decimal {
        switch frequency.uppercased() {
        case "WEEKLY": return averageAmount * 52 / 12
        case "BIWEEKLY": return averageAmount * 26 / 12
        case "SEMI_MONTHLY": return averageAmount * 2
        case "ANNUALLY": return averageAmount / 12
        default: return averageAmount
        }
    }
}

public struct Budget: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var pocketId: UUID?
    public var categoryId: UUID?
    public var amount: Decimal
    public var currency: String
    public var period: BudgetPeriod
    public init(id: UUID = UUID(), pocketId: UUID? = nil, categoryId: UUID? = nil, amount: Decimal, currency: String, period: BudgetPeriod = .payPeriod) {
        self.id = id; self.pocketId = pocketId; self.categoryId = categoryId; self.amount = amount; self.currency = currency; self.period = period
    }
}

public struct Goal: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var ownerId: UUID
    public var name: String
    public var icon: String
    public var color: String
    public var targetAmount: Decimal
    public var currency: String
    public var targetDate: Day?
    public var reachedAt: Date?
    public var lastMilestone: Int
    public var archivedAt: Date?
    public var createdAt: Date
    public init(id: UUID = UUID(), ownerId: UUID, name: String, icon: String = "target", color: String = "#7C9CFF", targetAmount: Decimal, currency: String, targetDate: Day? = nil, reachedAt: Date? = nil, lastMilestone: Int = 0, archivedAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.ownerId = ownerId; self.name = name; self.icon = icon; self.color = color
        self.targetAmount = targetAmount; self.currency = currency; self.targetDate = targetDate; self.reachedAt = reachedAt
        self.lastMilestone = lastMilestone; self.archivedAt = archivedAt; self.createdAt = createdAt
    }
}

/// Row of the `goal_member_progress` view.
public struct GoalMember: Codable, Hashable, Sendable {
    public var goalId: UUID
    public var userId: UUID
    public var role: String
    public var displayName: String?
    public var funding: GoalFunding
    public var currentAmount: Decimal?     // nil when the partner hides their amount
    public var sharePct: Decimal?
    public var shareActivity: Bool
    public init(goalId: UUID, userId: UUID, role: String = "owner", displayName: String? = nil, funding: GoalFunding = .manual, currentAmount: Decimal?, sharePct: Decimal? = nil, shareActivity: Bool = true) {
        self.goalId = goalId; self.userId = userId; self.role = role; self.displayName = displayName
        self.funding = funding; self.currentAmount = currentAmount; self.sharePct = sharePct; self.shareActivity = shareActivity
    }
}

/// Own funding settings (from `goal_members`, readable for your own row).
public struct GoalFundingSettings: Codable, Hashable, Sendable {
    public var goalId: UUID
    public var userId: UUID
    public var funding: GoalFunding
    public var accountId: UUID?
    public var earmarkAmount: Decimal?
    public var currentAmount: Decimal
    public init(goalId: UUID, userId: UUID, funding: GoalFunding, accountId: UUID? = nil, earmarkAmount: Decimal? = nil, currentAmount: Decimal = 0) {
        self.goalId = goalId; self.userId = userId; self.funding = funding
        self.accountId = accountId; self.earmarkAmount = earmarkAmount; self.currentAmount = currentAmount
    }
}

public struct GoalEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var goalId: UUID
    public var userId: UUID
    public var kind: String
    public var amount: Decimal?
    public var note: String?
    public var createdAt: Date
    public init(id: UUID = UUID(), goalId: UUID, userId: UUID, kind: String, amount: Decimal? = nil, note: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.goalId = goalId; self.userId = userId; self.kind = kind; self.amount = amount; self.note = note; self.createdAt = createdAt
    }
}

public struct FXRate: Codable, Hashable, Sendable {
    public var date: Day
    public var quote: String
    public var rate: Decimal
    public init(date: Day, quote: String, rate: Decimal) { self.date = date; self.quote = quote; self.rate = rate }
}

public struct NotificationPrefs: Codable, Hashable, Sendable {
    public var goalReached = true
    public var goalMilestones = true
    public var budgetWarning = true
    public var budgetExceeded = true
    public var billsDue = true
    public var paydaySummary = true
    public var reauth = true
    public init() {}
}
