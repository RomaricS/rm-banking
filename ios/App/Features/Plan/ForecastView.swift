import SwiftUI
import Charts
import AkweKit

/// 4.4 Forecast & what-if
struct ForecastView: View {
    @Environment(AppModel.self) private var app
    @State private var cut: Double = 30
    @State private var categoryId: UUID?
    @State private var goalId: UUID?

    var body: some View {
        let ledger = app.ledger
        let safe = ledger.safeToSpend()
        let today = Day.today()
        let payday = safe.range.end.adding(days: 1)
        let cash = app.accounts.filter { $0.type == "depository" && $0.includeInTotals }
            .reduce(Decimal(0)) { $0 + app.rates.convert($1.currentBalance ?? 0, from: $1.currency, to: app.currency) }
        let dailySpend = safe.daysLeft > 0 ? max(0, safe.plan - safe.spent - safe.billsDue) / Decimal(safe.daysLeft) : 0
        let income = app.schedule.typicalAmount.map { app.rates.convert($0, from: app.accounts.first?.currency ?? app.currency, to: app.currency) } ?? 0
        let points = projection(today: today, payday: payday, cash: cash, daily: dailySpend, bills: safe.bills, income: income)
        let projected = points.last?.1 ?? cash

        let cats = app.spendingCategories
        let cat = cats.first { $0.id == categoryId } ?? cats.first { $0.key == "restaurants" } ?? cats.first
        let goals = ledger.goals.filter { ledger.goalProgress($0).remaining > 0 }
        let goal = goals.first { $0.id == goalId } ?? goals.first

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("forecast.onPayday", payday.medium)).font(.system(size: 14)).foregroundStyle(Palette.text2)
                AmountText(amount: projected, currency: app.currency, font: .system(size: 32, weight: .heavy), cents: false)
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Day", p.0.date), y: .value("Balance", p.1.doubleValue))
                            .foregroundStyle(p.0 <= today ? Palette.text : Palette.iris)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.stepEnd)
                    }
                    RuleMark(x: .value("Payday", payday.date)).foregroundStyle(Palette.positive.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .annotation(position: .bottom, alignment: .trailing) { Text(tr("forecast.payday")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.positive) }
                }
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 130)
            }
            .card()

            if let cat, let goal {
                let p = ledger.goalProgress(goal)
                let avg = ledger.averagePerPeriod(categoryId: cat.id)
                let base = p.requiredPerPeriod ?? max(1, p.remaining / 12)
                let boosted = base + avg * Decimal(cut / 100)
                let arrival = ledger.arrival(remaining: p.remaining, perPeriod: boosted)
                let baseline = ledger.arrival(remaining: p.remaining, perPeriod: base)
                let weeks = (arrival.flatMap { a in baseline.map { a.days(until: $0) / 7 } }) ?? 0

                VStack(alignment: .leading, spacing: 14) {
                    Label(tr("forecast.whatIf"), systemImage: "sparkles").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                    HStack {
                        Menu { ForEach(cats) { c in Button(c.name) { categoryId = c.id } } } label: { chip(cat.name) }
                        Text(tr("forecast.cutBy")).font(.system(size: 15))
                        Spacer()
                        Text("\(Int(cut))%").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.iris).monospacedDigit()
                            .contentTransition(.numericText(value: cut))
                    }
                    Slider(value: $cut, in: 0...50, step: 5).tint(Palette.iris)
                        .onChange(of: cut) { _, v in if Int(v) % 10 == 0 { Haptics.selection() } }
                    Text(tr("forecast.avg", money(avg, app.currency, cents: false))).font(.system(size: 12)).foregroundStyle(Palette.text3)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Menu { ForEach(goals) { g in Button(g.name) { goalId = g.id } } } label: {
                                Text(tr("forecast.goalArrives", goal.name)).font(.system(size: 13)).foregroundStyle(Palette.text2)
                                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(Palette.text2)
                            }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(arrival?.monthYear ?? "—").font(.system(size: 24, weight: .heavy)).contentTransition(.numericText())
                            Spacer()
                            Text(weeks > 0 ? tr("forecast.sooner", weeks) : tr("forecast.same")).font(.system(size: 14, weight: .bold)).foregroundStyle(weeks > 0 ? Palette.positive : Palette.text2)
                        }
                        .animation(Motion.numbers, value: cut)
                        Text(tr("forecast.saving", money(boosted, app.currency, cents: false), money(base, app.currency, cents: false))).font(.system(size: 13)).foregroundStyle(Palette.text2)
                    }
                    .card(padding: 14, radius: 16, fill: Color(hex: 0x7C9CFF).opacity(0.12))

                    Button(tr("forecast.apply", cat.name)) {
                        let newLimit = (avg * Decimal(1 - cut / 100)).rounded(0)
                        Task { await app.setBudget(pocketId: nil, categoryId: cat.id, amount: newLimit); app.showToast("gauge.with.dots.needle.33percent", tr("forecast.applied")) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(cut == 0 || avg == 0)
                }
                .card()
            }
        }
    }

    /// Day-by-day balance until payday: steady daily spend + known bills, then the paycheck.
    private func projection(today: Day, payday: Day, cash: Decimal, daily: Decimal, bills: [RecurringStream], income: Decimal) -> [(Day, Decimal)] {
        var out: [(Day, Decimal)] = [(today, cash)]
        var bal = cash
        var d = today
        while d < payday {
            d = d.adding(days: 1)
            bal -= daily
            for b in bills where b.predictedNextDate == d { bal -= app.rates.convert(b.lastAmount, from: b.currency, to: app.currency) }
            if d == payday { bal += income }
            out.append((d, bal))
        }
        return out
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) { Text(text); Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            .padding(.horizontal, 12).frame(height: 32).background(Palette.raised, in: Capsule())
    }
}
