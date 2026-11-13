import Foundation
import AkweKit

/// Sample data used when no backend is configured (and for SwiftUI previews).
/// Generated relative to today so the demo always looks "current".
enum DemoData {
    static let userId = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    static let partnerId = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!

    struct Bundle {
        var profile: Profile
        var schedule: PaySchedule
        var items: [BankItem]
        var accounts: [Account]
        var pockets: [Pocket]
        var categories: [TxCategory]
        var transactions: [Transaction]
        var recurring: [RecurringStream]
        var budgets: [Budget]
        var goals: [Goal]
        var members: [GoalMember]
        var events: [GoalEvent]
        var rates: [FXRate]
    }

    static func make(today: Day = .today()) -> Bundle {
        // Pay schedule: every other Friday, anchored so that today is mid-period.
        let anchor = today.adding(days: -6)
        let schedule = PaySchedule(frequency: .biweekly, anchorDate: anchor, incomeSource: "ACME CORP PAYROLL", typicalAmount: 3250, detected: true)

        let northwind = BankItem(id: UUID(), institutionName: "Northwind Bank", country: "US", lastSyncedAt: Date().addingTimeInterval(-180))
        let harbor = BankItem(id: UUID(), institutionName: "Harbor Credit", country: "CA", lastSyncedAt: Date().addingTimeInterval(-180))
        let lbp = BankItem(id: UUID(), institutionName: "La Banque Postale", country: "FR", lastSyncedAt: Date().addingTimeInterval(-600))

        let checking = Account(id: UUID(), itemId: northwind.id, name: "Checking", mask: "21", type: "depository", subtype: "checking", currency: "USD", currentBalance: 4212.18, availableBalance: 4212.18, cardKind: .debit, color: "#A99FFF", sort: 0)
        let savings = Account(id: UUID(), itemId: northwind.id, name: "Savings", mask: "12", type: "depository", subtype: "savings", currency: "USD", currentBalance: 6950, cardKind: nil, color: "#A99FFF", sort: 1)
        let card = Account(id: UUID(), itemId: harbor.id, name: "Mastercard", mask: "3307", type: "credit", subtype: "credit card", currency: "USD", currentBalance: -842.40, creditLimit: 5000, cardKind: .credit, hidden: true, color: "#FFB86B", sort: 2)
        let compte = Account(id: UUID(), itemId: lbp.id, name: "Compte courant", mask: "40", type: "depository", subtype: "checking", currency: "EUR", currentBalance: 1980, cardKind: .deferred, includeInTotals: false, color: "#C084FC", sort: 3)

        func pocket(_ key: String, _ name: String, _ icon: String, _ color: String, _ sort: Int, income: Bool = false) -> Pocket {
            Pocket(id: UUID(), key: key, name: name, icon: icon, color: color, isIncome: income, sort: sort)
        }
        let home = pocket("home", "Home", "house.fill", "#7C9CFF", 1)
        let food = pocket("food", "Food", "fork.knife", "#FF9F5A", 2)
        let move = pocket("getting_around", "Getting around", "car.fill", "#3DDC97", 3)
        let life = pocket("lifestyle", "Lifestyle", "bag.fill", "#C084FC", 4)
        let health = pocket("health", "Health", "heart.fill", "#FF7EB6", 5)
        let other = pocket("other", "Other", "ellipsis", "#8B8B96", 6)
        let income = pocket("income", "Income", "arrow.down.left", "#3DDC97", 7, income: true)

        func cat(_ p: Pocket, _ key: String, _ name: String, _ icon: String, _ sort: Int) -> TxCategory {
            TxCategory(id: UUID(), pocketId: p.id, key: key, name: name, icon: icon, sort: sort)
        }
        let rent = cat(home, "rent", "Rent", "key.fill", 1)
        let utilities = cat(home, "utilities", "Utilities", "bolt.fill", 2)
        let internet = cat(home, "internet_phone", "Internet & phone", "wifi", 3)
        let groceries = cat(food, "groceries", "Groceries", "cart.fill", 1)
        let restaurants = cat(food, "restaurants", "Restaurants", "fork.knife", 2)
        let coffee = cat(food, "coffee", "Coffee", "cup.and.saucer.fill", 3)
        let gas = cat(move, "gas", "Gas", "fuelpump.fill", 1)
        let rideshare = cat(move, "rideshare", "Rideshare & taxi", "car.side.fill", 2)
        let shopping = cat(life, "shopping", "Shopping", "bag.fill", 1)
        let entertainment = cat(life, "entertainment", "Entertainment", "ticket.fill", 2)
        let subscriptions = cat(life, "subscriptions", "Subscriptions", "repeat", 3)
        let fitness = cat(health, "fitness", "Fitness", "figure.run", 1)
        let uncategorized = cat(other, "uncategorized", "Other", "questionmark", 9)
        let paycheck = cat(income, "paycheck", "Paycheck", "briefcase.fill", 1)
        let categories = [rent, utilities, internet, groceries, restaurants, coffee, gas, rideshare, shopping, entertainment, subscriptions, fitness, uncategorized, paycheck]

        var rng = SeededRandom(seed: 42)
        var txs: [Transaction] = []
        func add(_ amount: Decimal, _ name: String, _ c: TxCategory?, _ d: Day, _ a: Account, method: PaymentMethod = .debitCard, kind: TxKind = .spend, review: Bool = false, pending: Bool = false, currency: String? = nil) {
            txs.append(Transaction(accountId: a.id, pending: pending, amount: amount, currency: currency ?? a.currency, date: d, rawName: name.uppercased(), merchantName: name, paymentMethod: method, kind: kind, categoryId: c?.id, categorySource: .plaid, needsReview: review))
        }

        // ~16 weeks of history
        for back in 0..<112 {
            let d = today.adding(days: -back)
            if rng.next() < 0.75 { add(-Decimal(Int(rng.next() * 400 + 380)) / 100, "Blue Door Coffee", coffee, d, checking) }
            if d.weekday == 7 || d.weekday == 4 { add(-Decimal(Int(rng.next() * 6000 + 4500)) / 100, "Whole Foods", groceries, d, checking) }
            if rng.next() < 0.22 { add(-Decimal(Int(rng.next() * 3500 + 1500)) / 100, ["Taqueria Sol", "Noodle Bar", "Le Petit Bistro"][Int(rng.next() * 3)], restaurants, d, card, method: .creditCard) }
            if rng.next() < 0.2 { add(-Decimal(Int(rng.next() * 1800 + 900)) / 100, "Uber", rideshare, d, card, method: .creditCard) }
            if d.day == 3 || d.day == 18 { add(-Decimal(Int(rng.next() * 2000 + 4000)) / 100, "Shell", gas, d, card, method: .creditCard) }
            if rng.next() < 0.12 { add(-Decimal(Int(rng.next() * 9000 + 1500)) / 100, "Amazon", shopping, d, card, method: .creditCard) }
            if rng.next() < 0.08 { add(-Decimal(Int(rng.next() * 3000 + 1200)) / 100, "Monoprix", groceries, d, compte, method: .deferredCard) }
            if d.day == 1 { add(-850, "Rent (my share)", rent, d, checking, method: .transfer) }
            if d.day == 9 { add(-112.40, "Electric Co.", utilities, d, checking, method: .directDebit) }
            if d.day == 17 { add(-64, "Phone", internet, d, card, method: .creditCard) }
            if d.day == 18 { add(-15.49, "Netflix", subscriptions, d, card, method: .creditCard) }
            if d.day == 11 { add(-11.99, "Spotify", subscriptions, d, card, method: .creditCard) }
            if d.day == 17 { add(-45, "Gym", fitness, d, card, method: .creditCard) }
            if rng.next() < 0.05 { add(-28, "Cinema 8", entertainment, d, card, method: .creditCard) }
            // paydays
            if schedule.period(containing: d).start == d { add(3250, "Acme Corp Payroll", paycheck, d, checking, method: .transfer, kind: .income) }
        }
        // transfers & card payment (not spending)
        add(-500, "To Savings ··12", nil, today.adding(days: -1), checking, method: .transfer, kind: .transfer)
        add(500, "From Checking ··21", nil, today.adding(days: -1), savings, method: .transfer, kind: .transfer)
        add(-842.40, "Harbor Card payment", nil, today.adding(days: -10), checking, method: .transfer, kind: .cardPayment)
        // things to review
        add(-41.99, "Amazon", shopping, today.adding(days: -1), card, method: .creditCard, review: true)
        add(-23.75, "Corner Market", groceries, today.adding(days: -1), checking, review: true)
        add(-12, "City Parking", uncategorized, today.adding(days: -2), checking, review: true)
        add(-60, "Venmo · Alex", uncategorized, today.adding(days: -3), checking, method: .transfer, review: true)
        add(-6.40, "Blue Door Coffee", coffee, today, checking, pending: true)
        add(-18.20, "Uber", rideshare, today, card, method: .creditCard)

        let recurring = [
            RecurringStream(accountId: checking.id, description: "Rent (my share)", averageAmount: 850, lastAmount: 850, currency: "USD", predictedNextDate: today.adding(days: 1)),
            RecurringStream(accountId: card.id, description: "Phone", averageAmount: 64, lastAmount: 64, currency: "USD", predictedNextDate: today.adding(days: 4)),
            RecurringStream(accountId: card.id, description: "Gym", averageAmount: 45, lastAmount: 45, currency: "USD", predictedNextDate: today.adding(days: 4)),
            RecurringStream(accountId: card.id, description: "Netflix", averageAmount: 15.49, lastAmount: 15.49, previousAmount: 13.49, currency: "USD", predictedNextDate: today.adding(days: 5)),
            RecurringStream(accountId: card.id, description: "Spotify", averageAmount: 11.99, lastAmount: 11.99, currency: "USD", predictedNextDate: today.adding(days: 28)),
            RecurringStream(accountId: checking.id, description: "Electric Co.", averageAmount: 112.4, lastAmount: 112.4, currency: "USD", predictedNextDate: today.adding(days: 26)),
        ]
        let budgets = [
            Budget(pocketId: food.id, amount: 800, currency: "USD"),
            Budget(categoryId: coffee.id, amount: 80, currency: "USD"),
            Budget(pocketId: life.id, amount: 450, currency: "USD"),
        ]

        var japan = Goal(ownerId: userId, name: "Japan trip", icon: "airplane", color: "#7C9CFF", targetAmount: 6000, currency: "USD", targetDate: today.adding(days: 200), lastMilestone: 50)
        japan.createdAt = today.adding(days: -190).date
        var emergency = Goal(ownerId: userId, name: "Emergency fund", icon: "shield.fill", color: "#3DDC97", targetAmount: 10000, currency: "USD", targetDate: today.adding(days: 300), lastMilestone: 25)
        emergency.createdAt = today.adding(days: -200).date
        let apartment = Goal(ownerId: userId, name: "New apartment", icon: "house.fill", color: "#FF7EB6", targetAmount: 20000, currency: "USD", targetDate: today.adding(days: 640), lastMilestone: 25)
        let members = [
            GoalMember(goalId: japan.id, userId: userId, funding: .earmark, currentAmount: 3400),
            GoalMember(goalId: emergency.id, userId: userId, funding: .earmark, currentAmount: 3550),
            GoalMember(goalId: apartment.id, userId: userId, displayName: "You", funding: .manual, currentAmount: 5200, sharePct: 26),
            GoalMember(goalId: apartment.id, userId: partnerId, role: "partner", displayName: "Sam", funding: .manual, currentAmount: 3800, sharePct: 19),
        ]
        let events = [
            GoalEvent(goalId: apartment.id, userId: partnerId, kind: "contribution", amount: 400, createdAt: Date()),
            GoalEvent(goalId: apartment.id, userId: userId, kind: "contribution", amount: 220, createdAt: Date().addingTimeInterval(-6 * 86400)),
            GoalEvent(goalId: apartment.id, userId: userId, kind: "milestone", amount: 25, createdAt: Date().addingTimeInterval(-20 * 86400)),
        ]
        let rates = (0..<120).flatMap { i -> [FXRate] in
            let d = today.adding(days: -i)
            return [FXRate(date: d, quote: "USD", rate: 1.08), FXRate(date: d, quote: "CAD", rate: 1.5), FXRate(date: d, quote: "GBP", rate: 0.85), FXRate(date: d, quote: "CHF", rate: 0.95)]
        }

        return Bundle(
            profile: Profile(id: userId, displayName: "You", displayCurrency: "USD", onboardedAt: Date()),
            schedule: schedule, items: [northwind, harbor, lbp], accounts: [checking, savings, card, compte],
            pockets: [home, food, move, life, health, other, income], categories: categories,
            transactions: txs.sorted { $0.date > $1.date }, recurring: recurring, budgets: budgets,
            goals: [japan, emergency, apartment], members: members, events: events, rates: rates
        )
    }
}

/// Deterministic generator so the demo looks the same on every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 1_000_000) / 1_000_000
    }
}
