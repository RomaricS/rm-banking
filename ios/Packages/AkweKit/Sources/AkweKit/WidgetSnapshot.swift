import Foundation

/// Small, pre-computed summary written by the app into the App Group and read by widgets.
public struct WidgetSnapshot: Codable, Sendable {
    public struct PocketSlice: Codable, Sendable, Hashable { public var name: String; public var color: String; public var amount: Decimal }
    public struct GoalSlice: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID; public var name: String; public var color: String
        public var saved: Decimal; public var target: Decimal; public var currency: String; public var status: String
        public var fraction: Double { target > 0 ? min(1, (saved / target).doubleValue) : 0 }
    }

    public var updatedAt: Date
    public var currency: String
    public var hideBalances: Bool
    public var totalBalance: Decimal
    public var safePerDay: Decimal
    public var daysToPayday: Int
    public var periodSpent: Decimal
    public var periodPlan: Decimal
    public var leftAfterBills: Decimal
    public var periodFraction: Double
    public var onPace: Bool
    public var pockets: [PocketSlice]
    public var goals: [GoalSlice]

    public static let placeholder = WidgetSnapshot(
        updatedAt: Date(), currency: "USD", hideBalances: false, totalBalance: 12480, safePerDay: 64, daysToPayday: 8,
        periodSpent: 1148, periodPlan: 2600, leftAfterBills: 448, periodFraction: 0.5, onPace: true,
        pockets: [.init(name: "Food", color: "#FF9F5A", amount: 412), .init(name: "Lifestyle", color: "#C084FC", amount: 268), .init(name: "Home", color: "#7C9CFF", amount: 186)],
        goals: [.init(id: UUID(), name: "Japan trip", color: "#7C9CFF", saved: 3400, target: 6000, currency: "USD", status: "onTrack")]
    )
}

public extension Ledger {
    func widgetSnapshot(hideBalances: Bool, today: Day = .today()) -> WidgetSnapshot {
        let safe = safeToSpend(today: today)
        let s = summary(safe.range, today: today)
        return WidgetSnapshot(
            updatedAt: Date(), currency: currency, hideBalances: hideBalances, totalBalance: totalBalance,
            safePerDay: safe.perDay, daysToPayday: safe.daysLeft, periodSpent: s.spent, periodPlan: safe.plan,
            leftAfterBills: safe.left, periodFraction: Double(safe.dayIndex) / Double(safe.range.length),
            onPace: (safe.paceDelta ?? 0) >= 0,
            pockets: s.byPocket.prefix(5).map { .init(name: $0.pocket.name, color: $0.pocket.color, amount: $0.amount) },
            goals: goals.filter { $0.archivedAt == nil }.map { g in
                let p = goalProgress(g, today: today)
                let status: String = { switch p.status { case .reached: "reached"; case .onTrack: "onTrack"; case .behind: "behind"; case .noDeadline: "open" } }()
                return .init(id: g.id, name: g.name, color: g.color, saved: p.saved, target: g.targetAmount, currency: g.currency, status: status)
            }
        )
    }
}

public enum AppGroup {
    public static let identifier = "group.com.akwe.app"
    public static var containerURL: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #else
        nil
        #endif
    }
    public static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }

    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
