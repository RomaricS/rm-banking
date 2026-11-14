import SwiftUI
import Charts
import AkweKit

/// 3.1 Insights
struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @State private var kind: PeriodKind = .payPeriod
    @State private var offset = 0

    var body: some View {
        let ledger = app.ledger
        let today = Day.today()
        let range = Periods.range(kind, containing: today, schedule: app.schedule, offset: offset)
        let prev = Periods.range(kind, containing: today, schedule: app.schedule, offset: offset - 1)
        let s = ledger.summary(range, previous: prev, today: offset == 0 ? today : range.end)
        let prevSpent = ledger.summary(prev, today: prev.end).spent
        let avg = offset == 0 ? ledger.averageCumulative(kind, today: today) : []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(tr("tab.insights")).font(.system(size: 32, weight: .heavy)).tracking(-0.8)
                    Spacer()
                    NavigationLink(value: Route.recurring) {
                        Label(tr("insights.bills"), systemImage: "calendar").font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 8)

                PillSegments(options: [PeriodKind.payPeriod, .month, .week, .year], selection: $kind) { tr("period.\($0.rawValue)") }
                    .onChange(of: kind) { _, _ in offset = 0 }

                HStack(alignment: .center) {
                    Button { withAnimation(Motion.smooth) { offset -= 1 } } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(tr("insights.previous"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(range.label).font(.system(size: 14)).foregroundStyle(Palette.text2)
                        // Amount and "vs. last" side by side when they fit; otherwise the delta drops below.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                AmountText(amount: s.spent, currency: app.currency, font: .system(size: 40, weight: .heavy), cents: false).fixedSize()
                                DeltaLabel(current: s.spent, previous: prevSpent, currency: app.currency).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                AmountText(amount: s.spent, currency: app.currency, font: .system(size: 40, weight: .heavy), cents: false)
                                DeltaLabel(current: s.spent, previous: prevSpent, currency: app.currency)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    Button { withAnimation(Motion.smooth) { offset += 1 } } label: { Image(systemName: "chevron.right") }
                        .disabled(offset >= 0)
                        .accessibilityLabel(tr("insights.next"))
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text2)
                .contentTransition(.numericText())

                SpendCurve(range: range, cumulative: s.cumulative, average: avg, plan: kind == .payPeriod && offset == 0 ? ledger.spendingPlan() : nil, currency: app.currency)
                    .frame(height: 170)
                    .id("\(kind)-\(offset)")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    tile(tr("insights.income"), money(s.income, app.currency, cents: false), Palette.text, 0)
                    tile(tr("insights.net"), money(s.net, app.currency, cents: false, signed: true), s.net >= 0 ? Palette.positive : Palette.over, 1)
                    tile(tr("insights.savingsRate"), s.savingsRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", Palette.text, 2)
                }

                pocketsCard(s)

                if !app.budgets.isEmpty { budgetsCard(ledger) }

                if !s.topMerchants.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("insights.topMerchants")).font(.system(size: 17, weight: .bold)).padding(.bottom, 6)
                        ForEach(s.topMerchants) { m in
                            HStack {
                                Text(m.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(tr("insights.visits", m.count)).font(.system(size: 13)).foregroundStyle(Palette.text2)
                                AmountText(amount: m.amount, currency: app.currency, font: .system(size: 15, weight: .semibold), cents: false).frame(minWidth: 70, alignment: .trailing)
                            }
                            .frame(minHeight: 40)
                        }
                    }
                    .card()
                }

                if s.byMethod.count > 1 { methodCard(s) }

                WeekdayHeatmap(values: ledger.weekdayPattern(DayRange(start: today.adding(days: -90), end: today)), currency: app.currency)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .refreshable { await app.sync() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func tile(_ label: String, _ value: String, _ color: Color, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.text2)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(color).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
                .blur(radius: app.hideBalances ? 8 : 0)
        }
        .card(padding: 12, radius: Radius.tile)
        .rise(i)
    }

    private func pocketsCard(_ s: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("insights.byPocket")).font(.system(size: 17, weight: .bold))
                Spacer()
                NavigationLink(tr("common.manage"), value: Route.managePockets).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(s.byPocket.filter { $0.amount > 0 }.enumerated()), id: \.element.id) { i, p in
                        RoundedRectangle(cornerRadius: 4).fill(Color(hexString: p.pocket.color))
                            .frame(width: max(4, (geo.size.width - CGFloat(s.byPocket.count) * 3) * p.share))
                            .rise(i)
                    }
                }
            }
            .frame(height: 12)
            if s.byPocket.isEmpty { Text(tr("insights.noSpend")).font(.system(size: 14)).foregroundStyle(Palette.text2) }
            ForEach(s.byPocket) { p in
                NavigationLink(value: Route.pocket(p.pocket.id, kind, offset: offset)) {
                    HStack(spacing: 12) {
                        IconTile(systemName: p.pocket.icon, color: Color(hexString: p.pocket.color), size: 32, radius: 11)
                        Text(p.pocket.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        if let c = p.change {
                            Text("\(c >= 0 ? "↑" : "↓") \(Int(abs(c * 100).rounded()))%")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(c > 0 ? Palette.over : Palette.positive)
                        }
                        AmountText(amount: p.amount, currency: app.currency, font: .system(size: 15, weight: .semibold), cents: false)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.row)
            }
        }
        .card()
    }

    private func budgetsCard(_ ledger: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("insights.limits")).font(.system(size: 17, weight: .bold))
            ForEach(ledger.budgetStatuses) { b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(b.name).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(money(b.spent, b.budget.currency, cents: false)) / \(money(b.limit, b.budget.currency, cents: false))")
                            .font(.system(size: 14)).foregroundStyle(Palette.text2).monospacedDigit()
                    }
                    ProgressBar(fraction: b.fraction, color: b.state == .over ? Palette.over : (b.state == .atRisk ? Palette.warning : Color(hexString: b.color)), height: 6, marker: b.elapsed)
                    Text(b.state == .over ? tr("budget.over", money(-b.remaining, b.budget.currency, cents: false)) : tr("budget.left", money(b.remaining, b.budget.currency, cents: false), money(b.perDayLeft, b.budget.currency, cents: false)))
                        .font(.system(size: 12)).foregroundStyle(b.state == .over ? Palette.over : Palette.text2)
                }
            }
        }
        .card()
    }

    private func methodCard(_ s: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("insights.howYouPaid")).font(.system(size: 17, weight: .bold))
            ForEach(s.byMethod.filter { $0.amount > 0 }, id: \.method) { m in
                HStack(spacing: 10) {
                    Image(systemName: m.method.icon).frame(width: 22).foregroundStyle(Palette.iris)
                    Text(m.method.label).font(.system(size: 15))
                    Spacer()
                    Text("\(Int(((m.amount / max(s.spent, 1)).doubleValue * 100).rounded()))%").font(.system(size: 13)).foregroundStyle(Palette.text2)
                    AmountText(amount: m.amount, currency: app.currency, font: .system(size: 15, weight: .semibold), cents: false).frame(minWidth: 64, alignment: .trailing)
                }
            }
        }
        .card()
    }
}

struct DeltaLabel: View {
    let current: Decimal
    let previous: Decimal
    let currency: String
    var body: some View {
        if previous > 0 {
            let diff = current - previous
            Text(diff <= 0 ? tr("insights.lessThanPrev", money(-diff, currency, cents: false)) : tr("insights.moreThanPrev", money(diff, currency, cents: false)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(diff <= 0 ? Palette.positive : Palette.over)
        }
    }
}

/// Cumulative spend this period vs. your average period, day by day.
struct SpendCurve: View {
    let range: DayRange
    let cumulative: [Decimal]
    let average: [Decimal]
    let plan: Decimal?
    let currency: String
    @State private var reveal: Double = 0

    var body: some View {
        Chart {
            ForEach(Array(average.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Day", i), y: .value("Average", v.doubleValue), series: .value("S", "avg"))
                    .foregroundStyle(Palette.text.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
            }
            ForEach(Array(cumulative.prefix(Int(Double(cumulative.count) * reveal)).enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Day", i), y: .value("Spent", v.doubleValue), series: .value("S", "now"))
                    .foregroundStyle(Palette.text)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if reveal >= 1, let last = cumulative.last {
                PointMark(x: .value("Day", cumulative.count - 1), y: .value("Spent", last.doubleValue))
                    .foregroundStyle(Palette.text).symbolSize(70)
            }
            if let plan, plan > 0 {
                RuleMark(y: .value("Plan", plan.doubleValue))
                    .foregroundStyle(Palette.text.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(tr("insights.plan", money(plan, currency, cents: false))).font(.system(size: 11)).foregroundStyle(Palette.text3)
                    }
            }
        }
        .chartXScale(domain: 0...max(1, range.length - 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 14) {
                legend(tr("insights.thisPeriod"), dashed: false)
                if !average.isEmpty { legend(tr("insights.average"), dashed: true) }
            }
            .offset(y: 20)
        }
        .padding(.bottom, 20)
        .onAppear { withAnimation(.smooth(duration: 0.9)) { reveal = 1 } }
        .accessibilityElement()
        .accessibilityLabel(tr("a11y.curve"))
    }

    private func legend(_ text: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(dashed ? Palette.text.opacity(0.4) : Palette.text).frame(width: 14, height: 3)
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.text2)
        }
    }
}

/// Which weekdays you spend the most on.
struct WeekdayHeatmap: View {
    let values: [Int: Decimal]
    let currency: String

    var body: some View {
        let maxV = max(values.values.max() ?? 1, 1)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        // Monday-first order
        let order = [2, 3, 4, 5, 6, 7, 1]
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("insights.weekdays")).font(.system(size: 17, weight: .bold))
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { wd in
                    let v = values[wd] ?? 0
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.iris.opacity(0.12 + 0.88 * (v / maxV).doubleValue))
                            .frame(height: 44)
                        Text(symbols[wd - 1]).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(Calendar.current.weekdaySymbols[wd - 1]): \(money(v, currency, cents: false))")
                }
            }
        }
        .card()
    }
}
