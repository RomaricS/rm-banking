import SwiftUI
import AkweKit

/// 2.2 Activity — unified feed with search, filters and swipe actions.
struct ActivityView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var accountFilter: UUID?
    @State private var pocketFilter: UUID?
    @State private var methodFilter: PaymentMethod?
    @State private var categorizing: Transaction?
    @State private var limit = 150

    private var filtered: [Transaction] {
        let ledger = app.ledger
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return app.transactions.filter { t in
            guard t.splitParentId == nil else { return false }
            if let a = accountFilter, t.accountId != a { return false }
            if let m = methodFilter, t.paymentMethod != m { return false }
            if let p = pocketFilter, ledger.category(t.categoryId)?.pocketId != p { return false }
            if !q.isEmpty {
                let amount = "\(t.amount.abs)"
                let hay = "\(t.title) \(t.rawName) \(t.note ?? "") \(ledger.category(t.categoryId)?.name ?? "") \(amount)".lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    var body: some View {
        let list = filtered
        let days = Dictionary(grouping: list.prefix(limit), by: \.date).sorted { $0.key > $1.key }
        let reviewCount = app.ledger.needsReview.count

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                Text(tr("tab.activity")).font(.system(size: 32, weight: .heavy)).tracking(-0.8).padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.text2)
                    TextField(tr("activity.searchPlaceholder"), text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.text3) }
                            .accessibilityLabel(tr("common.clear"))
                    }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Palette.raised, in: Capsule())

                filters

                if reviewCount > 0 {
                    NavigationLink(value: Route.review) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Color(hex: 0x7C6CFF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("activity.toReview", reviewCount)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Text(tr("activity.toReviewHint")).font(.system(size: 13)).foregroundStyle(Palette.iris)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.text2)
                        }
                        .card(padding: 12, radius: 18, fill: Palette.iris.opacity(0.14))
                    }
                    .buttonStyle(.row)
                    .rise(0)
                }

                if list.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: tr("activity.emptyTitle"), message: tr("activity.emptyHint"))
                }

                ForEach(days, id: \.key) { entry in
                    let day = entry.key
                    let txs = entry.value
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(day.relativeLabel()).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
                            Spacer()
                            let total = txs.filter(\.countsInStats).reduce(Decimal(0)) { $0 + app.ledger.value($1) }
                            AmountText(amount: total, currency: app.currency, font: .system(size: 13, weight: .semibold), cents: true, signed: total > 0, color: Palette.text2)
                        }
                        .padding(.horizontal, 2)
                        VStack(spacing: 0) {
                            ForEach(txs) { t in
                                NavigationLink(value: Route.transaction(t.id)) {
                                    TransactionRow(tx: t).padding(.horizontal, 14)
                                }
                                .buttonStyle(.row)
                                .contextMenu {
                                    Button { categorizing = t } label: { Label(tr("tx.changeCategory"), systemImage: "tag") }
                                    Button { Task { await app.setExcluded(t, !t.excluded) } } label: {
                                        Label(t.excluded ? tr("tx.include") : tr("tx.exclude"), systemImage: t.excluded ? "eye" : "eye.slash")
                                    }
                                }
                            }
                        }
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                if list.count > limit {
                    Button(tr("activity.loadMore")) { limit += 200 }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.ground)
        .refreshable { await app.sync() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $categorizing) { t in CategoryPicker(tx: t) }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Button(tr("activity.allAccounts")) { accountFilter = nil }
                    ForEach(app.accounts.filter { !$0.isHidden }) { a in Button("\(a.displayName) ··\(a.mask ?? "")") { accountFilter = a.id } }
                } label: { chip(accountFilter.flatMap { id in app.accounts.first { $0.id == id }?.displayName } ?? tr("activity.allAccounts"), active: accountFilter != nil) }

                Menu {
                    Button(tr("activity.anyPocket")) { pocketFilter = nil }
                    ForEach(app.pockets) { p in Button(p.name) { pocketFilter = p.id } }
                } label: { chip(pocketFilter.flatMap { id in app.pockets.first { $0.id == id }?.name } ?? tr("activity.pocket"), active: pocketFilter != nil) }

                Menu {
                    Button(tr("activity.anyMethod")) { methodFilter = nil }
                    ForEach(PaymentMethod.allCases, id: \.self) { m in Button { methodFilter = m } label: { Label(m.label, systemImage: m.icon) } }
                } label: { chip(methodFilter?.label ?? tr("activity.method"), active: methodFilter != nil) }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(active ? Palette.onInverse : Palette.text)
        .padding(.horizontal, 12).frame(height: 34)
        .background(active ? AnyShapeStyle(Palette.inverse) : AnyShapeStyle(Color.clear), in: Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : Palette.text.opacity(0.16)))
    }
}
