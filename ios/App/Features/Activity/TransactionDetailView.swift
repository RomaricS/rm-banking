import SwiftUI
import AkweKit

/// 2.3 Transaction detail — category, payment method, include in stats, rule suggestion, split, note.
struct TransactionDetailView: View {
    @Environment(AppModel.self) private var app
    let id: UUID
    @State private var picking = false
    @State private var splitting = false
    @State private var editingNote = false
    @State private var renaming = false
    @State private var note = ""
    @State private var newName = ""
    @State private var ruleKey: String?
    @State private var ruleResult: Int?

    var body: some View {
        if let tx = app.transactions.first(where: { $0.id == id }) {
            content(tx)
        } else {
            EmptyState(icon: "questionmark", title: tr("tx.missing"), message: "")
        }
    }

    private func content(_ tx: Transaction) -> some View {
        let ledger = app.ledger
        let cat = ledger.category(tx.categoryId)
        let pocket = ledger.pocket(cat?.pocketId)
        let account = app.accounts.first { $0.id == tx.accountId }
        let color = Color(hexString: pocket?.color ?? "#8B8B96")
        let key = MerchantNormalizer.key(tx.title)
        let history = app.transactions.filter { MerchantNormalizer.key($0.title) == key && $0.kind == .spend }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        AmountText(amount: tx.amount, currency: tx.currency, font: .system(size: 40, weight: .heavy), cents: true, signed: tx.amount > 0)
                        if tx.currency != app.currency {
                            Text("≈ \(money(ledger.value(tx), app.currency, cents: true))").font(.system(size: 14)).foregroundStyle(Palette.text2)
                        }
                        Button { newName = tx.title; renaming = true } label: {
                            HStack(spacing: 6) { Text(tx.title).font(.system(size: 17, weight: .semibold)); Image(systemName: "pencil").font(.system(size: 12)) }
                        }
                        .buttonStyle(.row)
                        Text("\(tx.date.long)\(tx.pending ? " · " + tr("tx.pending") : "")").font(.system(size: 14)).foregroundStyle(Palette.text2)
                    }
                    Spacer()
                    IconTile(systemName: cat?.icon ?? "questionmark", color: color, size: 64, radius: 22)
                }
                .padding(.top, 8)

                HStack(spacing: 6) {
                    Tag(text: tx.paymentMethod.label, color: Palette.iris)
                    if let badge = tx.kind.badge { Tag(text: badge) }
                    if let ch = tx.paymentChannel, ch != "other" { Tag(text: tr("channel.\(ch == "in store" ? "inStore" : "online")")) }
                    Tag(text: tx.currency)
                }

                HStack(spacing: 8) {
                    if tx.kind == .spend && tx.splitParentId == nil {
                        Button { splitting = true } label: { Label(tr("tx.split"), systemImage: "divide") }.buttonStyle(SecondaryButtonStyle())
                    }
                    Button { note = tx.note ?? ""; editingNote = true } label: { Label(tr("tx.note"), systemImage: "note.text") }.buttonStyle(SecondaryButtonStyle())
                }

                if let ruleKey, let cat {
                    RuleSuggestion(merchant: tx.title, category: cat.name, matches: app.transactions.filter { MerchantNormalizer.key($0.title) == ruleKey && $0.categorySource != .user }.count) {
                        Task {
                            ruleResult = await app.createRule(merchantKey: ruleKey, categoryId: cat.id)
                            Haptics.success()
                            withAnimation(Motion.bouncy) { self.ruleKey = nil }
                        }
                    } onDismiss: { withAnimation(Motion.smooth) { self.ruleKey = nil } }
                    .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .opacity))
                }
                if let ruleResult {
                    Label(tr("tx.ruleCreated", ruleResult), systemImage: "checkmark")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.positive)
                        .card(padding: 12, radius: 16, fill: Palette.positive.opacity(0.12))
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Button { picking = true } label: {
                        row(tr("tx.category")) {
                            HStack(spacing: 8) {
                                Circle().fill(color).frame(width: 8, height: 8)
                                Text(cat?.name ?? tr("tx.uncategorized")).fontWeight(.semibold)
                                if let pocket { Text("· \(pocket.name)").foregroundStyle(Palette.text2) }
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text3)
                            }
                        }
                    }
                    .buttonStyle(.row)
                    .disabled(!tx.canCategorize)
                    Divider().overlay(Palette.stroke)
                    row(tr("tx.account")) { Text("\(account?.displayName ?? "") ··\(account?.mask ?? "")").fontWeight(.semibold) }
                    Divider().overlay(Palette.stroke)
                    row(tr("tx.bankLabel")) { Text(tx.rawName).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.text2).lineLimit(1) }
                    Divider().overlay(Palette.stroke)
                    row(tr("tx.countInStats")) {
                        Toggle("", isOn: Binding(get: { !tx.excluded }, set: { v in Task { await app.setExcluded(tx, !v) } }))
                            .labelsHidden().tint(Palette.positive)
                    }
                }
                .padding(.horizontal, 14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if tx.isOneSidedTransfer {
                    // e.g. an Interac e-Transfer to the landlord: Plaid calls it a transfer, but the money left your world.
                    Label(tr(tx.amount < 0 ? "tx.transferHintOut" : "tx.transferHintIn"), systemImage: "info.circle")
                        .font(.system(size: 13)).foregroundStyle(Palette.text2)
                        .padding(.horizontal, 4)
                }

                if let note = tx.note, !note.isEmpty {
                    Text(note).font(.system(size: 15)).card(padding: 14, radius: 18)
                }

                if history.count > 1 {
                    MerchantHistory(transactions: history, color: color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            CategoryPicker(tx: tx) { key in withAnimation(Motion.bouncy) { ruleKey = key } }
        }
        .sheet(isPresented: $splitting) { SplitView(tx: tx) }
        .alert(tr("tx.note"), isPresented: $editingNote) {
            TextField(tr("tx.notePlaceholder"), text: $note)
            Button(tr("common.save")) { Task { await app.setNote(tx, note) } }
            Button(tr("common.cancel"), role: .cancel) {}
        }
        .alert(tr("tx.rename"), isPresented: $renaming) {
            TextField(tx.title, text: $newName)
            Button(tr("common.save")) { Task { await app.rename(tx, to: newName) } }
            Button(tr("common.cancel"), role: .cancel) {}
        }
    }

    private func row<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.text2)
            Spacer()
            value()
        }
        .font(.system(size: 15))
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

struct RuleSuggestion: View {
    let merchant: String
    let category: String
    let matches: Int
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Palette.iris)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("rule.question", merchant, category)).font(.system(size: 15, weight: .semibold))
                    Text(tr("rule.hint", matches)).font(.system(size: 13)).foregroundStyle(Palette.iris)
                }
            }
            HStack(spacing: 8) {
                Button(tr("rule.create"), action: onCreate).buttonStyle(PrimaryButtonStyle()).frame(height: 44)
                Button(tr("common.notNow"), action: onDismiss).buttonStyle(SecondaryButtonStyle())
            }
        }
        .card(padding: 14, radius: 20, fill: Palette.iris.opacity(0.14))
    }
}

/// Bars of what you spent at this merchant per pay period.
struct MerchantHistory: View {
    @Environment(AppModel.self) private var app
    let transactions: [Transaction]
    let color: Color

    var body: some View {
        let ledger = app.ledger
        let bars = (0..<6).reversed().map { i -> (DayRange, Decimal, Int) in
            let r = app.schedule.period(containing: .today(), offset: -i)
            let txs = transactions.filter { r.contains($0.date) }
            return (r, txs.reduce(0) { $0 - ledger.value($1) }, txs.count)
        }
        let maxV = max(bars.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("tx.perPeriod", transactions.first?.title ?? "")).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let now = bars.last { Text(tr("tx.nowCount", now.2, money(now.1, app.currency, cents: false))).font(.system(size: 13)).foregroundStyle(Palette.text2) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6).fill(i == bars.count - 1 ? color : Palette.text.opacity(0.14))
                            .frame(height: max(4, 60 * (b.1 / maxV).doubleValue))
                        Text(i == bars.count - 1 ? tr("common.now") : b.0.start.short).font(.system(size: 10)).foregroundStyle(Palette.text3).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80, alignment: .bottom)
        }
        .card(padding: 14, radius: 20)
    }
}

/// Category picker grouped by pocket.
struct CategoryPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction
    var onRuleSuggestion: ((String) -> Void)?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.pockets.filter { $0.isIncome == (tx.amount > 0) || tx.kind == .refund }) { p in
                    let cats = app.categories.filter { $0.pocketId == p.id && !$0.archived && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                    if !cats.isEmpty {
                        Section(p.name) {
                            ForEach(cats) { c in
                                Button {
                                    Task {
                                        let key = await app.setCategory(tx, to: c.id)
                                        Haptics.selection()
                                        dismiss()
                                        if let key { onRuleSuggestion?(key) }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        IconTile(systemName: c.icon, color: Color(hexString: p.color), size: 32, radius: 10)
                                        Text(c.name).foregroundStyle(Palette.text)
                                        Spacer()
                                        if c.id == tx.categoryId { Image(systemName: "checkmark").foregroundStyle(Palette.iris) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(tr("tx.chooseCategory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Split one purchase across categories (e.g. Costco = groceries + household).
struct SplitView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction
    struct Part: Identifiable { let id = UUID(); var category: UUID?; var amount: String }
    @State private var parts: [Part] = []

    private var total: Decimal { tx.amount.abs }
    private var allocated: Decimal { parts.reduce(0) { $0 + (Decimal(string: $1.amount.replacingOccurrences(of: ",", with: ".")) ?? 0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Text(tx.title); Spacer(); Text(money(total, tx.currency, cents: true)).fontWeight(.semibold) }
                }
                Section(tr("split.parts")) {
                    ForEach($parts) { $p in
                        HStack {
                            Picker("", selection: $p.category) {
                                Text(tr("split.choose")).tag(UUID?.none)
                                ForEach(app.spendingCategories) { c in Text(c.name).tag(UUID?.some(c.id)) }
                            }
                            .labelsHidden()
                            TextField("0", text: $p.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                        }
                    }
                    Button(tr("split.addPart")) { parts.append(Part(category: nil, amount: "")) }
                }
                Section {
                    HStack {
                        Text(tr("split.left"))
                        Spacer()
                        Text(money(total - allocated, tx.currency, cents: true)).foregroundStyle(total - allocated == 0 ? Palette.positive : Palette.over)
                    }
                }
            }
            .navigationTitle(tr("tx.split"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common.save")) {
                        let valid = parts.compactMap { p -> (UUID, Decimal)? in
                            guard let c = p.category, let a = Decimal(string: p.amount.replacingOccurrences(of: ",", with: ".")), a > 0 else { return nil }
                            return (c, a)
                        }
                        Task { await app.split(tx, parts: valid); dismiss() }
                    }
                    .disabled(total - allocated != 0 || parts.count < 2)
                }
            }
            .onAppear {
                if parts.isEmpty { parts = [Part(category: tx.categoryId, amount: "\(total)"), Part(category: nil, amount: "")] }
            }
        }
    }
}
