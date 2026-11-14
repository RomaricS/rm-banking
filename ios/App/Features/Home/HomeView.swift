import SwiftUI
import AkweKit

/// 2.1 Home
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Binding var tab: AppTab

    var body: some View {
        let ledger = app.ledger
        let safe = ledger.safeToSpend()
        let recent = Array(app.transactions.filter { $0.splitParentId == nil }.prefix(4))

        ScrollView {
            ZStack(alignment: .top) {
                VStack(spacing: 22) {
                    topBar
                    hero(ledger: ledger, safe: safe)
                    if let broken = app.itemsNeedingAttention.first { reauthBanner(broken) }
                    payPeriodCard(safe).rise(1)
                    accountsStrip.rise(2)
                    recentCard(recent).rise(3)
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
                AuroraBackground()
            }
            .ignoresSafeArea()
        }
        .refreshable { await app.sync() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.settings) {
                Text(String((app.profile?.displayName ?? "A").prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                    .frame(width: 40, height: 40).background(Palette.text.opacity(0.16), in: Circle())
            }
            .accessibilityLabel(tr("settings.title"))
            Button { withAnimation(Motion.snappy) { tab = .activity } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(tr("common.search"))
                    Spacer()
                }
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text2)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Palette.text.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            CircleIconButton(systemName: app.hideBalances ? "eye.slash" : "eye", label: tr("home.hideBalances"), fill: Palette.text.opacity(0.12)) {
                withAnimation(Motion.smooth) { app.hideBalances.toggle() }
            }
            NavigationLink(value: Route.alerts) {
                Image(systemName: "bell").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    .frame(width: 40, height: 40).background(Palette.text.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(tr("alerts.title"))
        }
        .padding(.top, 8)
    }

    private func hero(ledger: Ledger, safe: SafeToSpend) -> some View {
        VStack(spacing: 8) {
            Text(tr("home.totalBalance", app.accounts.filter(\.includeInTotals).count))
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text2)
            HeroAmount(amount: ledger.totalBalance, currency: app.currency)
                .onLongPressGesture { withAnimation(Motion.smooth) { app.hideBalances.toggle() }; Haptics.light() }
            Button { withAnimation(Motion.snappy) { tab = .insights } } label: {
                HStack(spacing: 6) {
                    Text(tr("home.safeToSpend"))
                    AmountText(amount: safe.perDay.rounded(0), currency: app.currency, font: .system(size: 14, weight: .semibold), cents: false)
                    Text(tr("home.perDay"))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Palette.text.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
        .rise(0)
    }

    private func reauthBanner(_ item: BankItem) -> some View {
        NavigationLink(value: Route.accounts) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.over)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("home.reconnect", item.institutionName)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(tr("home.reconnectHint")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
            }
            .card(padding: 14, radius: 18, fill: Palette.over.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    private func payPeriodCard(_ safe: SafeToSpend) -> some View {
        Button { withAnimation(Motion.snappy) { tab = .insights } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("home.payPeriod")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(safe.range.label) · \(tr("home.dayOf", safe.dayIndex, safe.range.length))")
                        .font(.system(size: 13)).foregroundStyle(Palette.text2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AmountText(amount: safe.spent, currency: app.currency, font: .system(size: 26, weight: .bold), cents: false)
                    Text(tr("home.spentOfPlan", money(safe.plan, app.currency, cents: false))).font(.system(size: 14)).foregroundStyle(Palette.text2)
                }
                PayPeriodBar(spent: safe.spent, bills: safe.billsDue, plan: safe.plan, elapsed: Double(safe.dayIndex) / Double(safe.range.length))
                HStack {
                    if let pace = safe.paceDelta {
                        Text(pace >= 0 ? tr("home.underPace", money(pace, app.currency, cents: false)) : tr("home.overPace", money(-pace, app.currency, cents: false)))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(pace >= 0 ? Palette.positive : Palette.warning)
                    }
                    Spacer()
                    if safe.billsDue > 0 {
                        Text(tr("home.billsDue", money(safe.billsDue, app.currency, cents: false))).font(.system(size: 13)).foregroundStyle(Palette.text2)
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("home.accounts")).font(.system(size: 17, weight: .bold))
                Spacer()
                NavigationLink(tr("home.banksCount", app.items.count, 4), value: Route.accounts)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    // Counted accounts first; left-out ones follow as dashed "ghost" cards.
                    ForEach(app.accounts.filter { !$0.isHidden }.sorted { ($0.includeInTotals ? 0 : 1, $0.sort) < ($1.includeInTotals ? 0 : 1, $1.sort) }) { a in
                        NavigationLink(value: Route.accounts) {
                            VStack(alignment: .leading) {
                                HStack(spacing: 8) {
                                    BankBadge(name: app.item(for: a)?.institutionName ?? a.name, color: app.accountColor(a), size: 24)
                                    Text("\(a.displayName)\(a.mask.map { " ··\($0)" } ?? "")").font(.system(size: 13)).foregroundStyle(Palette.text2).lineLimit(1)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    AmountText(amount: a.currentBalance ?? 0, currency: a.currency, font: .system(size: 17, weight: .bold), cents: false)
                                    if !a.includeInTotals {
                                        Image(systemName: "minus.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text3)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 140, height: 92, alignment: .leading)
                            .countedStyle(a.includeInTotals, fill: Palette.card, radius: Radius.tile)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(a.includeInTotals ? "" : tr("totals.leftOut"))
                    }
                    let hiddenCount = app.accounts.filter(\.isHidden).count
                    if hiddenCount > 0 {
                        NavigationLink(value: Route.accounts) {
                            VStack(spacing: 6) {
                                Image(systemName: "eye.slash").font(.system(size: 18, weight: .semibold))
                                Text(tr("home.hiddenCount", hiddenCount)).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Palette.text2)
                            .frame(width: 92, height: 92)
                            .background(Palette.text.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func recentCard(_ recent: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tr("home.recent")).font(.system(size: 17, weight: .bold))
                Spacer()
                Button(tr("common.seeAll")) { withAnimation(Motion.snappy) { tab = .activity } }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
            }
            .padding(.top, 6)
            if recent.isEmpty {
                EmptyState(icon: "tray", title: tr("home.noTx"), message: tr("home.noTxHint"))
            }
            ForEach(recent) { t in
                NavigationLink(value: Route.transaction(t.id)) { TransactionRow(tx: t) }.buttonStyle(.plain)
            }
        }
        .card(padding: 16)
    }
}

/// Spent (solid) + bills still due (striped) + pace marker.
struct PayPeriodBar: View {
    let spent: Decimal
    let bills: Decimal
    let plan: Decimal
    let elapsed: Double
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(plan, spent + bills, 1)
            let sw = w * (spent / total).doubleValue
            let bw = w * (bills / total).doubleValue
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.text.opacity(0.08))
                HStack(spacing: 0) {
                    Rectangle().fill(spent > plan ? Palette.over : Palette.text).frame(width: shown ? sw : 0)
                    Rectangle().fill(Palette.text.opacity(0.25)).frame(width: shown ? bw : 0)
                        .overlay(StripePattern().foregroundStyle(Palette.text.opacity(0.18)))
                }
                .clipShape(Capsule())
                RoundedRectangle(cornerRadius: 1).fill(Palette.positive).frame(width: 2, height: 18).offset(x: w * elapsed - 1)
            }
        }
        .frame(height: 10)
        .onAppear { withAnimation(Motion.smooth.delay(0.35)) { shown = true } }
        .accessibilityElement()
        .accessibilityLabel(tr("a11y.payPeriodBar"))
    }
}

struct StripePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.height))
            p.addLine(to: CGPoint(x: x + rect.height, y: 0))
            p.addLine(to: CGPoint(x: x + rect.height + 3, y: 0))
            p.addLine(to: CGPoint(x: x + 3, y: rect.height))
            p.closeSubpath()
            x += 8
        }
        return p
    }
}

/// One transaction line (Home, Activity, pocket detail…).
struct TransactionRow: View {
    @Environment(AppModel.self) private var app
    let tx: Transaction
    var showAccount = true

    var body: some View {
        let ledger = app.ledger
        let cat = ledger.category(tx.categoryId)
        let pocket = ledger.pocket(cat?.pocketId)
        let color = tx.kind.countsInStats ? Color(hexString: pocket?.color ?? "#8B8B96") : Palette.text3
        let icon = tx.kind == .transfer || tx.kind == .cardPayment || tx.kind == .cardSettlement ? "arrow.left.arrow.right" : (cat?.icon ?? "questionmark")
        let account = app.accounts.first { $0.id == tx.accountId }

        HStack(spacing: 12) {
            IconTile(systemName: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: the merchant gets the width; "pending" is a compact clock, not a pill.
                HStack(spacing: 5) {
                    Text(tx.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if tx.pending {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.text3)
                            .accessibilityLabel(tr("tx.pending"))
                    }
                }
                // Line 2: kind / excluded tags never wrap; the subtitle truncates instead.
                HStack(spacing: 6) {
                    if let badge = tx.kind.badge { Tag(text: badge) }
                    if tx.excluded { Tag(text: tr("tx.excluded"), color: Palette.text3) }
                    Text(subtitle(cat: cat, account: account)).font(.system(size: 13)).foregroundStyle(Palette.text2).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: tx.amount, currency: tx.currency, font: .system(size: 15, weight: .semibold), cents: true, signed: tx.amount > 0,
                           color: tx.amount > 0 && tx.kind == .income ? Palette.positive : (tx.kind.countsInStats ? Palette.text : Palette.text3))
                    .strikethrough(tx.excluded)
                if tx.currency != app.currency {
                    AmountText(amount: app.ledger.value(tx), currency: app.currency, font: .system(size: 12), cents: true, color: Palette.text3)
                }
            }
            .fixedSize()
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func subtitle(cat: AkweKit.TxCategory?, account: Account?) -> String {
        var parts: [String] = []
        if tx.kind.countsInStats { parts.append(cat?.name ?? tr("tx.uncategorized")) }
        if showAccount, let a = account {
            // Transfers / card payments already carry a kind tag, so name the account rather than repeat "Transfer".
            let useAccountName = tx.paymentMethod == .other || tx.kind.badge != nil
            parts.append("\(useAccountName ? a.displayName : tx.paymentMethod.label) ··\(a.mask ?? "")")
        }
        return parts.joined(separator: " · ")
    }
}
