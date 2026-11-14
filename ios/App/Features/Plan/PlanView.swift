import SwiftUI
import Charts
import AkweKit

/// 4.1 Plan — Goals / Forecast.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    enum Mode: String { case goals, forecast }
    @State private var mode: Mode = .goals
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(tr("tab.plan")).font(.system(size: 32, weight: .heavy)).tracking(-0.8)
                    Spacer()
                    Button { creating = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.onInverse)
                            .frame(width: 40, height: 40).background(Palette.inverse, in: Circle())
                    }
                    .accessibilityLabel(tr("goal.new"))
                }
                .padding(.top, 8)

                PillSegments(options: [Mode.goals, .forecast], selection: $mode) { tr("plan.\($0.rawValue)") }

                if mode == .goals { GoalsList(onCreate: { creating = true }) } else { ForecastView() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $creating) { NewGoalView() }
    }
}

struct GoalsList: View {
    @Environment(AppModel.self) private var app
    let onCreate: () -> Void

    var body: some View {
        let ledger = app.ledger
        let progress = ledger.goals.map { ledger.goalProgress($0) }
        let saved = progress.reduce(Decimal(0)) { $0 + app.rates.convert($1.saved, from: $1.goal.currency, to: app.currency) }
        let target = progress.reduce(Decimal(0)) { $0 + app.rates.convert($1.target, from: $1.goal.currency, to: app.currency) }

        VStack(alignment: .leading, spacing: 14) {
            if progress.isEmpty {
                VStack(spacing: 16) {
                    EmptyState(icon: "target", title: tr("goals.emptyTitle"), message: tr("goals.emptyHint"))
                    Button(tr("goal.new"), action: onCreate).buttonStyle(PrimaryButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("goals.setAside")).font(.system(size: 14)).foregroundStyle(Palette.text2)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        AmountText(amount: saved, currency: app.currency, font: .system(size: 36, weight: .heavy), cents: false)
                        Text(tr("goals.ofTarget", money(target, app.currency, cents: false))).font(.system(size: 14)).foregroundStyle(Palette.text2)
                    }
                    GeometryReader { geo in
                        HStack(spacing: 3) {
                            ForEach(progress, id: \.goal.id) { p in
                                RoundedRectangle(cornerRadius: 4).fill(Color(hexString: p.goal.color))
                                    .frame(width: max(2, geo.size.width * (p.saved / max(target, 1)).doubleValue))
                            }
                            RoundedRectangle(cornerRadius: 4).fill(Palette.text.opacity(0.08))
                        }
                    }
                    .frame(height: 8).padding(.top, 6)
                }

                ForEach(Array(progress.enumerated()), id: \.element.goal.id) { i, p in
                    NavigationLink(value: Route.goal(p.goal.id)) { GoalCard(progress: p) }
                        .buttonStyle(.row)
                        .rise(i)
                }

                if let tip = whatIfTip(ledger) {
                    Label { Text(tip) } icon: { Image(systemName: "sparkles").foregroundStyle(Palette.iris) }
                        .font(.system(size: 14, weight: .semibold))
                        .card(padding: 14, radius: 20, fill: Palette.iris.opacity(0.14))
                }
            }
        }
    }

    /// "Cut Restaurants 30% and Japan arrives 6 weeks sooner"
    private func whatIfTip(_ ledger: Ledger) -> String? {
        guard let goal = ledger.goals.first(where: { ledger.goalProgress($0).requiredPerPeriod ?? 0 > 0 }),
              let cat = app.categories.first(where: { $0.key == "restaurants" }) else { return nil }
        let p = ledger.goalProgress(goal)
        let avg = ledger.averagePerPeriod(categoryId: cat.id)
        guard avg > 0, let base = p.requiredPerPeriod,
              let now = ledger.arrival(remaining: p.remaining, perPeriod: base),
              let faster = ledger.arrival(remaining: p.remaining, perPeriod: base + avg * Decimal(0.3)) else { return nil }
        let weeks = faster.days(until: now) / 7
        return weeks > 0 ? tr("goals.tip", cat.name, goal.name, weeks) : nil
    }
}

struct GoalCard: View {
    @Environment(AppModel.self) private var app
    let progress: GoalProgress

    var body: some View {
        let g = progress.goal
        HStack(spacing: 14) {
            ZStack {
                RingProgress(fraction: progress.fraction, color: Color(hexString: g.color), lineWidth: 7)
                Text("\(Int((progress.fraction * 100).rounded()))%").font(.system(size: 14, weight: .bold))
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(g.name).font(.system(size: 17, weight: .bold))
                    if progress.isShared { Image(systemName: "person.2.fill").font(.system(size: 12)).foregroundStyle(Palette.partner) }
                }
                Text("\(money(progress.saved, g.currency, cents: false)) / \(money(g.targetAmount, g.currency, cents: false))")
                    .font(.system(size: 14)).foregroundStyle(Palette.text2).monospacedDigit()
                    .blur(radius: app.hideBalances ? 6 : 0)
                GoalStatusText(progress: progress)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
        }
        .card(padding: 14)
    }
}

struct GoalStatusText: View {
    let progress: GoalProgress
    var body: some View {
        switch progress.status {
        case .reached: Text(tr("goal.reached")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.positive)
        case .onTrack: Text(tr("goal.onTrack", progress.goal.targetDate?.monthYear ?? "")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.positive)
        case .behind(let extra): Text(tr("goal.behind", money(extra, progress.goal.currency, cents: false))).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.warning)
        case .noDeadline: Text(tr("goal.noDeadline")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
        }
    }
}
