import SwiftUI
import Charts
import AkweKit

/// 3.2 Pocket detail — budget ring, last 6 periods, categories, merchants, transactions.
struct PocketDetailView: View {
    @Environment(AppModel.self) private var app
    let pocketId: UUID
    @State private var editingBudget = false

    var body: some View {
        if let pocket = app.pockets.first(where: { $0.id == pocketId }) {
            content(pocket)
        }
    }

    private func content(_ pocket: Pocket) -> some View {
        let ledger = app.ledger
        let color = Color(hexString: pocket.color)
        let range = app.schedule.period(containing: .today())
        let s = ledger.summary(range, today: .today())
        let total = s.byPocket.first { $0.pocket.id == pocket.id }?.amount ?? 0
        let budget = app.budgets.first { $0.pocketId == pocket.id }
        let status = budget.map { ledger.budgetStatus($0) }
        let hist = ledger.history(.payPeriod, count: 6, pocketId: pocket.id)
        let avg = hist.dropLast().map(\.spent).reduce(0, +) / Decimal(max(1, hist.count - 1))
        let cats = s.byCategory.filter { $0.category.pocketId == pocket.id }
        let txs = ledger.statTransactions(in: range).filter { ledger.category($0.categoryId)?.pocketId == pocket.id }.sorted { $0.date > $1.date }

        return ScrollView {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 18) {
                        ZStack {
                            RingProgress(fraction: status?.fraction ?? 0, color: status?.state == .over ? Palette.over : color, lineWidth: 12)
                            VStack(spacing: 0) {
                                Text(status.map { "\(Int(($0.fraction * 100).rounded()))%" } ?? "—").font(.system(size: 24, weight: .heavy))
                                Text(tr("pocket.ofBudget")).font(.system(size: 12)).foregroundStyle(Palette.text2)
                            }
                        }
                        .frame(width: 124, height: 124)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pocket.name).font(.system(size: 15, weight: .semibold))
                            AmountText(amount: total, currency: app.currency, font: .system(size: 36, weight: .heavy), cents: false)
                            if let status {
                                Text(tr("pocket.leftPerDay", money(status.limit, status.budget.currency, cents: false), money(status.remaining, status.budget.currency, cents: false), money(status.perDayLeft, status.budget.currency, cents: false)))
                                    .font(.system(size: 14)).foregroundStyle(Palette.text2)
                            }
                            if avg > 0 {
                                let pct = Int((((total / avg) - 1).doubleValue * 100).rounded())
                                Text(pct > 0 ? tr("pocket.hot", pct) : tr("pocket.cool", -pct))
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(pct > 0 ? Palette.warning : Palette.positive)
                            }
                        }
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(tr("pocket.lastPeriods")).font(.system(size: 15, weight: .bold))
                            Spacer()
                            Text(tr("pocket.avg", money(avg, app.currency, cents: false))).font(.system(size: 13)).foregroundStyle(Palette.text2)
                        }
                        Chart {
                            ForEach(Array(hist.enumerated()), id: \.offset) { i, h in
                                BarMark(x: .value("Period", h.range.start.short), y: .value("Spent", h.spent.doubleValue))
                                    .foregroundStyle(i == hist.count - 1 ? color : Palette.text.opacity(0.14))
                                    .cornerRadius(7)
                            }
                            if avg > 0 {
                                RuleMark(y: .value("Average", avg.doubleValue)).foregroundStyle(Palette.text.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 120)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(cats) { c in
                            let catBudget = app.budgets.first { $0.categoryId == c.category.id }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(c.category.name).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    AmountText(amount: c.amount, currency: app.currency, font: .system(size: 15, weight: .semibold), cents: false)
                                    if let catBudget { Text("/ \(money(catBudget.amount, catBudget.currency, cents: false))").font(.system(size: 14)).foregroundStyle(Palette.text2) }
                                }
                                ProgressBar(fraction: catBudget.map { (c.amount / $0.amount).doubleValue } ?? (total > 0 ? (c.amount / total).doubleValue : 0), color: color, height: 6)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .card()

                    if !txs.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tr("pocket.transactions")).font(.system(size: 15, weight: .bold)).padding(.vertical, 6)
                            ForEach(txs.prefix(20)) { t in
                                NavigationLink(value: Route.transaction(t.id)) { TransactionRow(tx: t) }.buttonStyle(.plain)
                            }
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarClearance)
            }
        }
        .scrollIndicators(.hidden)
        // Full-bleed: the aurora runs under the status bar / Dynamic Island instead of leaving a dark band.
        .background {
            ZStack(alignment: .top) {
                Palette.ground
                AuroraBackground(tint: color, secondary: color.opacity(0.5), height: 420)
            }
            .ignoresSafeArea()
        }
        .navigationTitle(pocket.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(budget == nil ? tr("budget.set") : tr("budget.edit")) { editingBudget = true }
            }
        }
        .sheet(isPresented: $editingBudget) {
            BudgetEditor(title: pocket.name, pocketId: pocket.id, categoryId: nil, current: budget?.amount)
        }
    }
}

/// Set / change / remove a spending limit.
struct BudgetEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let title: String
    let pocketId: UUID?
    let categoryId: UUID?
    let current: Decimal?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(tr("budget.prompt", title)).font(.system(size: 15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MoneyFormat.symbol(for: app.currency)).font(.system(size: 40, weight: .heavy)).foregroundStyle(Palette.text2)
                    TextField("0", text: $text).keyboardType(.decimalPad).font(.system(size: 52, weight: .heavy)).focused($focused).fixedSize()
                }
                Text(tr("budget.alertsNote")).font(.system(size: 13)).foregroundStyle(Palette.text3).multilineTextAlignment(.center)
                Spacer()
                Button(tr("common.save")) {
                    let v = Decimal(string: text.replacingOccurrences(of: ",", with: "."))
                    Task { await app.setBudget(pocketId: pocketId, categoryId: categoryId, amount: v); Haptics.success(); dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                if current != nil {
                    Button(tr("budget.remove"), role: .destructive) {
                        Task { await app.setBudget(pocketId: pocketId, categoryId: categoryId, amount: nil); dismiss() }
                    }
                }
            }
            .padding(20)
            .navigationTitle(tr("budget.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } } }
            .onAppear { text = current.map { "\($0)" } ?? ""; focused = true }
        }
        .presentationDetents([.medium])
    }
}
