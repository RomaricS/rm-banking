import SwiftUI
import AkweKit

/// 3.4 Bills & subscriptions
struct RecurringView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let ledger = app.ledger
        let safe = ledger.safeToSpend()
        let today = Day.today()
        let week = (0..<7).map { today.adding(days: $0) }
        let outflows = app.recurring.filter { $0.isActive && $0.isOutflow }
        let subs = outflows.filter { ["subscriptions", "internet_phone", "fitness"].contains(ledger.category($0.categoryId)?.key ?? "") || $0.frequency.uppercased() == "MONTHLY" && $0.averageAmount < 100 }
        let subsMonthly = subs.reduce(Decimal(0)) { $0 + app.rates.convert($1.monthlyAmount, from: $1.currency, to: app.currency) }
        let cashAccount = app.accounts.filter { $0.type == "depository" && $0.subtype == "checking" }.max { ($0.availableBalance ?? 0) < ($1.availableBalance ?? 0) }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("bills.dueBefore", safe.range.end.adding(days: 1).medium)).font(.system(size: 15)).foregroundStyle(Palette.text2)
                    AmountText(amount: safe.billsDue, currency: app.currency, font: .system(size: 40, weight: .heavy), cents: true)
                    if let a = cashAccount, let bal = a.availableBalance ?? a.currentBalance {
                        let covered = app.rates.convert(bal, from: a.currency, to: app.currency) >= safe.billsDue
                        Text(covered ? tr("bills.covered", a.displayName, money(bal, a.currency, cents: false)) : tr("bills.short", a.displayName))
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(covered ? Palette.positive : Palette.over)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { d in
                        let dots = outflows.filter { $0.predictedNextDate == d }
                        VStack(spacing: 4) {
                            Text(d.localDate().formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .semibold)).opacity(0.75)
                            Text("\(d.day)").font(.system(size: 17, weight: .bold))
                            HStack(spacing: 3) {
                                ForEach(dots.prefix(3)) { r in
                                    Circle().fill(Color(hexString: ledger.pocket(ledger.category(r.categoryId)?.pocketId)?.color ?? "#8B8B96")).frame(width: 6, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .foregroundStyle(d == today ? Palette.onInverse : Palette.text)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(d == today ? Palette.inverse : Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                if !safe.bills.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(safe.bills.enumerated()), id: \.element.id) { i, b in
                            billRow(b).rise(i)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                } else {
                    EmptyState(icon: "checkmark.circle", title: tr("bills.noneTitle"), message: tr("bills.noneHint"))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(tr("bills.subscriptions")).font(.system(size: 17, weight: .bold))
                        Spacer()
                        Text(tr("bills.subsSummary", subs.count, money(subsMonthly, app.currency, cents: false))).font(.system(size: 14)).foregroundStyle(Palette.text2)
                    }
                    ForEach(subs.filter { $0.priceIncrease != nil }) { s in
                        Label {
                            Text(tr("bills.priceUp", s.title, money(s.priceIncrease!, s.currency, cents: true), money(s.lastAmount, s.currency, cents: true)))
                        } icon: { Image(systemName: "arrow.up.right").foregroundStyle(Palette.over) }
                        .font(.system(size: 14))
                        .card(padding: 12, radius: 16, fill: Palette.over.opacity(0.12))
                    }
                    ForEach(subs.sorted { $0.monthlyAmount > $1.monthlyAmount }) { s in
                        HStack {
                            Text(s.title).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(tr("bills.perMonth", money(s.monthlyAmount, s.currency, cents: true))).font(.system(size: 14)).foregroundStyle(Palette.text2)
                        }
                        .frame(minHeight: 40)
                    }
                }
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("bills.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func billRow(_ b: RecurringStream) -> some View {
        let account = app.accounts.first { $0.id == b.accountId }
        let cat = app.ledger.category(b.categoryId)
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(b.predictedNextDate?.localDate().formatted(.dateTime.month(.abbreviated)).uppercased() ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text2)
                Text("\(b.predictedNextDate?.day ?? 0)").font(.system(size: 17, weight: .bold))
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.title).font(.system(size: 15, weight: .semibold))
                Text("\(cat?.name ?? "") · \(account?.displayName ?? "")").font(.system(size: 13)).foregroundStyle(Palette.text2)
            }
            Spacer()
            AmountText(amount: b.lastAmount, currency: b.currency, font: .system(size: 15, weight: .semibold), cents: true)
        }
        .frame(minHeight: 58)
    }
}
