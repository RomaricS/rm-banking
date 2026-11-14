import SwiftUI
import AkweKit

/// 6.3 Accounts & cards — banks, card type (debit / credit / deferred), totals, unlink.
struct AccountsView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: Account?
    @State private var removing: BankItem?
    @State private var linking = false
    @State private var showHidden = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let nw = app.ledger.netWorth
                TotalCompositionCard()
                HStack {
                    stat(tr("accounts.assets"), nw.assets, Palette.text)
                    stat(tr("accounts.liabilities"), nw.liabilities, Palette.over)
                }

                ForEach(Array(app.items.enumerated()), id: \.element.id) { i, item in
                    bankCard(item).rise(i)
                }

                hiddenSection

                if app.items.count < 4 && !app.isDemo {
                    Button { linking = true } label: {
                        Label(tr("link.addAnother"), systemImage: "plus").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.iris.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.row)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("accounts.methodsTitle")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2)
                    FlowTags(tags: PaymentMethod.allCases.filter { $0 != .other }.map(\.label))
                }
                .card(padding: 12, radius: 18, fill: Palette.text.opacity(0.04))
            }
            .padding(.horizontal, 16).padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("accounts.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.sync() }
        .sheet(item: $editing) { a in AccountEditor(account: a) }
        .sheet(isPresented: $linking) { NavigationStack { LinkBanksView() } }
        .confirmationDialog(tr("accounts.unlinkConfirm", removing?.institutionName ?? ""), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(tr("accounts.unlink"), role: .destructive) { if let r = removing { Task { await app.removeItem(r) } } }
        } message: { Text(tr("accounts.unlinkHint")) }
    }

    private func stat(_ label: String, _ v: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.text2)
            AmountText(amount: v, currency: app.currency, font: .system(size: 20, weight: .bold), cents: false, color: color)
        }
        .card(padding: 12, radius: Radius.tile)
    }

    private func bankCard(_ item: BankItem) -> some View {
        let accounts = app.accounts.filter { $0.itemId == item.id && !$0.isHidden }.sorted { $0.sort < $1.sort }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BankBadge(name: item.institutionName, color: accounts.first.map(app.accountColor) ?? Palette.iris)
                Text(item.institutionName).font(.system(size: 15, weight: .bold))
                Spacer()
                if let c = item.country { Text(c).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2) }
                Menu {
                    Button { Task { await app.sync(itemId: item.id) } } label: { Label(tr("accounts.syncNow"), systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { removing = item } label: { Label(tr("accounts.unlink"), systemImage: "link.badge.plus") }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
            }
            if item.status.needsAttention {
                BankRow(item: item, accounts: accounts)
            }
            ForEach(accounts) { a in accountRow(a) }
            let hiddenHere = app.accounts.filter { $0.itemId == item.id && $0.isHidden }.count
            if hiddenHere > 0 {
                Button { withAnimation(Motion.snappy) { showHidden = true } } label: {
                    Label(tr("accounts.hiddenInBank", hiddenHere), systemImage: "eye.slash")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.row)
            }
            if let synced = item.lastSyncedAt {
                Text(tr("accounts.synced", synced.formatted(.relative(presentation: .named)))).font(.system(size: 12)).foregroundStyle(Palette.text3)
            }
        }
        .card(padding: 14)
    }

    private func accountRow(_ a: Account) -> some View {
        let kind = a.cardKind
        let (tag, tint): (String?, Color) = {
            switch kind {
            case .debit: (tr("card.debit"), Color(hex: 0x7C9CFF))
            case .credit: (tr("card.credit"), Palette.warning)
            case .deferred: (tr("card.deferred"), Color(hex: 0xC084FC))
            case nil: (nil, Palette.text2)
            }
        }()
        let cycle = kind == .deferred ? deferredCycle(a) : nil
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.8)).frame(width: 44, height: 30)
                    .overlay(alignment: .bottomLeading) { Capsule().fill(.white.opacity(0.8)).frame(width: 12, height: 3).padding(6) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(a.displayName)\(a.mask.map { " ··\($0)" } ?? "")").font(.system(size: 14, weight: .semibold))
                    if let tag { Tag(text: tag, color: tint) }
                }
                Spacer()
                AmountText(amount: a.currentBalance ?? 0, currency: a.currency, font: .system(size: 15, weight: .bold), cents: false)
            }
            if a.isCredit, let limit = a.creditLimit, limit > 0 {
                let owed = -(a.currentBalance ?? 0)
                ProgressBar(fraction: (owed / limit).doubleValue, color: Palette.warning, height: 6)
                Text(tr("card.utilization", Int(((owed / limit).doubleValue * 100).rounded()), money(limit, a.currency, cents: false))).font(.system(size: 12)).foregroundStyle(Palette.text2)
            }
            if let cycle {
                ProgressBar(fraction: min(1, cycle.fraction), color: Color(hex: 0xC084FC), height: 6)
                Text(tr("card.deferredCycle", money(cycle.total, a.currency, cents: false), cycle.debitDay.short)).font(.system(size: 12)).foregroundStyle(Palette.text2)
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            Button { editing = a } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.row)
                .leftOutContent(!a.includeInTotals)
            HStack(spacing: 8) {
                InTotalToggle(isOn: a.includeInTotals) { update(a) { $0.includeInTotals.toggle() } }
                VisibilityToggle(isShown: !a.isHidden) { update(a) { $0.hidden = !$0.isHidden } }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 2)
        .countedBackground(a.includeInTotals, fill: Palette.text.opacity(0.04), radius: 16)
    }

    private func update(_ a: Account, _ change: (inout Account) -> Void) {
        Haptics.selection()
        var updated = a
        change(&updated)
        // Row styles animate on the flags (see countedBackground / leftOutContent).
        withAnimation(Motion.snappy) {
            if let i = app.accounts.firstIndex(where: { $0.id == a.id }) { app.accounts[i] = updated }
        }
        Task { await app.updateAccount(updated) }
    }

    /// Hidden accounts live here, out of the bank cards, so they're never lost.
    @ViewBuilder private var hiddenSection: some View {
        let hidden = app.accounts.filter(\.isHidden).sorted { $0.sort < $1.sort }
        if !hidden.isEmpty {
            DisclosureGroup(isExpanded: $showHidden) {
                VStack(spacing: 10) {
                    ForEach(hidden) { a in accountRow(a) }
                    Text(tr("accounts.hiddenHint")).font(.system(size: 12)).foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)
            } label: {
                Label(tr("accounts.hiddenSection", hidden.count), systemImage: "eye.slash")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
            }
            .tint(Palette.text2)
            .card(padding: 14)
        }
    }

    /// Deferred card: purchases since the 1st, debited on the last day of the month.
    private func deferredCycle(_ a: Account) -> (total: Decimal, fraction: Double, debitDay: Day)? {
        let month = Periods.month(containing: .today())
        let ops = app.transactions.filter { $0.accountId == a.id && $0.paymentMethod == .deferredCard && $0.kind == .spend && month.contains($0.date) }
        let total = ops.reduce(Decimal(0)) { $0 - $1.amount }
        let previous = Periods.range(.month, containing: .today(), schedule: app.schedule, offset: -1)
        let prevTotal = app.transactions.filter { $0.accountId == a.id && $0.paymentMethod == .deferredCard && $0.kind == .spend && previous.contains($0.date) }.reduce(Decimal(0)) { $0 - $1.amount }
        return (total, prevTotal > 0 ? (total / prevTotal).doubleValue : 0.5, month.end)
    }
}

struct AccountEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var account: Account

    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("accounts.nickname"), text: Binding(get: { account.nickname ?? "" }, set: { account.nickname = $0.isEmpty ? nil : $0 }), prompt: Text(account.name))
                Section {
                    Toggle(tr("accounts.includeInTotals"), isOn: $account.includeInTotals).tint(Palette.positive)
                    Toggle(tr("accounts.showOnHome"), isOn: Binding(get: { !account.isHidden }, set: { account.hidden = !$0 })).tint(Palette.iris)
                } footer: { Text(tr("accounts.flagsFooter")) }
                if account.type == "depository" {
                    Section {
                        Picker(tr("accounts.cardType"), selection: Binding(get: { account.cardKind ?? .debit }, set: { account.cardKind = $0 })) {
                            Text(tr("card.debit")).tag(CardKind.debit)
                            Text(tr("card.deferred")).tag(CardKind.deferred)
                        }
                    } footer: { Text(tr("accounts.cardTypeHint")) }
                }
            }
            .navigationTitle(account.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("common.save")) { Task { await app.updateAccount(account); dismiss() } } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Simple wrapping row of tags.
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        ViewThatFits {
            HStack(spacing: 6) { ForEach(tags, id: \.self) { Tag(text: $0) } }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { ForEach(tags.prefix(4), id: \.self) { Tag(text: $0) } }
                HStack(spacing: 6) { ForEach(tags.dropFirst(4), id: \.self) { Tag(text: $0) } }
            }
        }
    }
}
