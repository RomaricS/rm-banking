import WidgetKit
import SwiftUI
import AkweKit

// Widgets read a small snapshot the app writes into the App Group after each load/sync.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (AppGroup.read() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: AppGroup.read() ?? .placeholder)
        // The app reloads timelines after every sync; also refresh every hour so "days to payday" stays right.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

// MARK: - Shared bits

private enum W {
    static let indigo = Color(red: 0x6A / 255, green: 0x4B / 255, blue: 1)
    static let mint = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x97 / 255)
    static let card = Color(uiColor: .secondarySystemBackground)

    static func hex(_ s: String) -> Color {
        let v = UInt32(s.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8B8B96
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func money(_ v: Decimal, _ c: String, hidden: Bool) -> String {
        hidden ? "•••" : MoneyFormat.string(v, currency: c, cents: false)
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let f = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return args.isEmpty ? f : String(format: f, locale: .current, arguments: args)
    }
}

private struct Ring: View {
    let fraction: Double
    let color: Color
    var width: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, min(1, fraction))).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Safe to spend (small + lock screen)

struct SafeToSpendView: View {
    @Environment(\.widgetFamily) private var family
    let s: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(W.t("widget.perDay")).font(.system(size: 9, weight: .semibold)).textCase(.uppercase)
                    Text(W.money(s.safePerDay, s.currency, hidden: s.hideBalances)).font(.system(size: 15, weight: .heavy)).minimumScaleFactor(0.6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text(W.t("widget.paydayIn", s.daysToPayday)).font(.system(size: 12))
                ProgressView(value: s.periodFraction).tint(.primary)
                Text(W.t("widget.leftAfterBills", W.money(s.leftAfterBills, s.currency, hidden: s.hideBalances))).font(.system(size: 13, weight: .bold))
            }
        case .accessoryInline:
            Text(W.t("widget.inline", W.money(s.safePerDay, s.currency, hidden: s.hideBalances), s.daysToPayday))
        default:
            VStack(alignment: .leading) {
                Text(W.t("widget.safeToSpend")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Ring(fraction: s.periodFraction, color: s.onPace ? W.mint : .orange, width: 9).frame(width: 64, height: 64)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(W.money(s.safePerDay, s.currency, hidden: s.hideBalances)).font(.system(size: 24, weight: .heavy)).minimumScaleFactor(0.6)
                    Text(W.t("widget.dayShort", s.daysToPayday)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "akwe.safeToSpend", provider: SnapshotProvider()) { e in
            SafeToSpendView(s: e.snapshot)
                .containerBackground(for: .widget) { W.card }
                .widgetURL(URL(string: "akwe://home"))
        }
        .configurationDisplayName(W.t("widget.safeToSpend"))
        .description(W.t("widget.safeToSpendDesc"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Goal (small) & Goals (large)

struct GoalSmallView: View {
    let s: WidgetSnapshot
    var body: some View {
        if let g = s.goals.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(g.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int((g.fraction * 100).rounded()))%").font(.system(size: 28, weight: .heavy))
                ProgressView(value: g.fraction).tint(W.hex(g.color))
                Text("\(W.money(g.saved, g.currency, hidden: s.hideBalances)) / \(W.money(g.target, g.currency, hidden: s.hideBalances))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(W.t("widget.noGoals")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct GoalsLargeView: View {
    let s: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(W.t("widget.goals")).font(.system(size: 15, weight: .bold))
                Spacer()
                Text(W.money(s.goals.reduce(0) { $0 + $1.saved }, s.currency, hidden: s.hideBalances)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(s.goals.prefix(4)) { g in
                HStack(spacing: 12) {
                    Ring(fraction: g.fraction, color: W.hex(g.color), width: 6).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(W.t("widget.goalStatus.\(g.status)")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((g.fraction * 100).rounded()))%").font(.system(size: 15, weight: .bold))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "akwe.goal", provider: SnapshotProvider()) { e in
            GoalSmallView(s: e.snapshot)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [W.hex(e.snapshot.goals.first?.color ?? "#7C9CFF").opacity(0.35), W.card], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "akwe://plan"))
        }
        .configurationDisplayName(W.t("widget.goal"))
        .description(W.t("widget.goalDesc"))
        .supportedFamilies([.systemSmall])
    }
}

struct GoalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "akwe.goals", provider: SnapshotProvider()) { e in
            GoalsLargeView(s: e.snapshot).containerBackground(for: .widget) { W.card }.widgetURL(URL(string: "akwe://plan"))
        }
        .configurationDisplayName(W.t("widget.goals"))
        .description(W.t("widget.goalsDesc"))
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Pay period (medium)

struct PayPeriodView: View {
    let s: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(W.t("widget.paydayIn", s.daysToPayday)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(s.onPace ? W.t("widget.onPace") : W.t("widget.overPace")).font(.system(size: 12, weight: .semibold)).foregroundStyle(s.onPace ? W.mint : .orange)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(W.money(s.periodSpent, s.currency, hidden: s.hideBalances)).font(.system(size: 26, weight: .heavy))
                Text(W.t("widget.ofPlan", W.money(s.periodPlan, s.currency, hidden: s.hideBalances))).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let total = max(s.periodPlan, s.periodSpent, 1)
                HStack(spacing: 2) {
                    ForEach(s.pockets, id: \.self) { p in
                        RoundedRectangle(cornerRadius: 3).fill(W.hex(p.color)).frame(width: geo.size.width * (p.amount / total).doubleValue)
                    }
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                ForEach(s.pockets.prefix(3), id: \.self) { p in
                    Text("\(p.name) \(W.money(p.amount, s.currency, hidden: s.hideBalances))").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

struct PayPeriodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "akwe.payPeriod", provider: SnapshotProvider()) { e in
            PayPeriodView(s: e.snapshot).containerBackground(for: .widget) { W.card }.widgetURL(URL(string: "akwe://insights"))
        }
        .configurationDisplayName(W.t("widget.payPeriod"))
        .description(W.t("widget.payPeriodDesc"))
        .supportedFamilies([.systemMedium])
    }
}

@main
struct AkweWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafeToSpendWidget()
        PayPeriodWidget()
        GoalWidget()
        GoalsWidget()
    }
}
