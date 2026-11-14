import SwiftUI
import AkweKit

/// 3.4 Bills & subscriptions: everything that comes back, at a glance; add what the bank missed.
struct RecurringView: View {
    @Environment(AppModel.self) private var app
    @State private var segment: Segment = .subscriptions
    @State private var editing: RecurringStream?
    @State private var showHidden = false

    enum Segment: Hashable { case subscriptions, bills }

    var body: some View {
        let today = Day.today()
        let live = app.upcomingRecurring(today: today)
        let subs = live.filter { app.isSubscription($0) }
        let bills = live.filter { !app.isSubscription($0) }
        let shown = segment == .subscriptions ? subs : bills
        let hidden = app.recurring.filter { $0.isOutflow && $0.isHidden }
        let safe = app.ledger.safeToSpend()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(subs: subs, bills: bills)
                weekStrip(live, today: today)
                dueBeforePayday(safe)

                PillSegments(options: [Segment.subscriptions, .bills], selection: $segment.animation(Motion.snappy)) {
                    $0 == .subscriptions ? tr("bills.subsTab", subs.count) : tr("bills.billsTab", bills.count)
                }

                ForEach(shown.filter { $0.priceIncrease != nil }) { s in
                    Label {
                        Text(tr("bills.priceUp", s.title, money(s.priceIncrease!, s.currency, cents: true), money(s.lastAmount, s.currency, cents: true)))
                    } icon: { Image(systemName: "arrow.up.right").foregroundStyle(Palette.over) }
                    .font(.system(size: 14))
                    .card(padding: 12, radius: 16, fill: Palette.over.opacity(0.12))
                }

                if shown.isEmpty {
                    EmptyState(icon: segment == .subscriptions ? "repeat" : "doc.text",
                               title: tr(segment == .subscriptions ? "bills.noSubs" : "bills.noBills"),
                               message: tr("bills.addHint"))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                            if i > 0 { Divider().overlay(Palette.stroke).padding(.leading, 52) }
                            Button { editing = r } label: { RecurringRow(stream: r) }.buttonStyle(.row)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }

                Button { editing = newEntry() } label: {
                    Label(tr(segment == .subscriptions ? "bills.addSub" : "bills.addBill"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                if !hidden.isEmpty {
                    DisclosureGroup(isExpanded: $showHidden.animation(Motion.smooth)) {
                        VStack(spacing: 0) {
                            ForEach(hidden) { r in
                                Button { editing = r } label: { RecurringRow(stream: r).leftOutContent(true) }.buttonStyle(.row)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label(tr("bills.hiddenSection", hidden.count), systemImage: "eye.slash")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text2)
                    }
                    .tint(Palette.text2)
                    .card(padding: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("bills.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = newEntry() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(tr("bills.add"))
            }
        }
        .sheet(item: $editing) { r in RecurringEditor(stream: r) }
    }

    private func newEntry() -> RecurringStream {
        RecurringStream(accountId: nil, description: "", averageAmount: 0, lastAmount: 0, currency: app.currency,
                        predictedNextDate: .today(), source: "manual", kind: segment == .subscriptions ? "subscription" : "bill")
    }

    private func header(subs: [RecurringStream], bills: [RecurringStream]) -> some View {
        let total = app.monthlyTotal(subs + bills)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("bills.everyMonth")).font(.system(size: 15)).foregroundStyle(Palette.text2)
            AmountText(amount: total, currency: app.currency, font: .system(size: 40, weight: .heavy), cents: false)
            HStack(spacing: 14) {
                legend(tr("bills.subscriptions"), app.monthlyTotal(subs), Palette.iris)
                legend(tr("bills.billsLabel"), app.monthlyTotal(bills), Palette.text2)
            }
        }
        .padding(.top, 8)
    }

    private func legend(_ label: String, _ amount: Decimal, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(money(amount, app.currency, cents: false))").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
        }
    }

    private func weekStrip(_ live: [RecurringStream], today: Day) -> some View {
        HStack(spacing: 6) {
            ForEach((0..<7).map { today.adding(days: $0) }, id: \.self) { d in
                let dots = live.filter { $0.predictedNextDate == d }
                VStack(spacing: 4) {
                    Text(d.localDate().formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, weight: .semibold)).opacity(0.75)
                    Text("\(d.day)").font(.system(size: 17, weight: .bold))
                    HStack(spacing: 3) {
                        ForEach(dots.prefix(3)) { r in Circle().fill(app.recurringColor(r)).frame(width: 6, height: 6) }
                    }
                    .frame(height: 6)
                }
                .foregroundStyle(d == today ? Palette.onInverse : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(d == today ? Palette.inverse : Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func dueBeforePayday(_ safe: SafeToSpend) -> some View {
        let cashAccount = app.accounts.filter { $0.type == "depository" && $0.subtype == "checking" && !$0.isHidden }
            .max { ($0.availableBalance ?? 0) < ($1.availableBalance ?? 0) }
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("bills.dueBefore", safe.range.end.adding(days: 1).medium)).font(.system(size: 14)).foregroundStyle(Palette.text2)
                if let a = cashAccount, let bal = a.availableBalance ?? a.currentBalance, safe.billsDue > 0 {
                    let covered = app.rates.convert(bal, from: a.currency, to: app.currency) >= safe.billsDue
                    Text(covered ? tr("bills.covered", a.displayName, money(bal, a.currency, cents: false)) : tr("bills.short", a.displayName))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(covered ? Palette.positive : Palette.over)
                }
            }
            Spacer()
            AmountText(amount: safe.billsDue, currency: app.currency, font: .system(size: 20, weight: .heavy), cents: false)
        }
        .card(padding: 14)
    }
}

/// One bill / subscription: icon, name, cadence + next date, amount.
struct RecurringRow: View {
    @Environment(AppModel.self) private var app
    let stream: RecurringStream
    var compact = false

    var body: some View {
        let cat = app.ledger.category(stream.categoryId)
        HStack(spacing: 12) {
            IconTile(systemName: cat?.icon ?? (app.isSubscription(stream) ? "repeat" : "doc.text"), color: app.recurringColor(stream), size: compact ? 34 : 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stream.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if stream.isManual && !compact { Tag(text: tr("bills.manual")) }
                }
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.text2).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: stream.lastAmount, currency: stream.currency, font: .system(size: 15, weight: .semibold), cents: true)
                if !compact && stream.frequency.uppercased() != "MONTHLY" {
                    Text(tr("bills.perMonth", money(stream.monthlyAmount, stream.currency, cents: false))).font(.system(size: 12)).foregroundStyle(Palette.text3)
                }
            }
            .fixedSize()
        }
        .frame(minHeight: compact ? 48 : 60)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [RecurringFrequency(stream.frequency).label]
        if let next = stream.predictedNextDate {
            let today = Day.today()
            parts.append(next == today ? tr("bills.dueToday") : next == today.adding(days: 1) ? tr("bills.dueTomorrow") : tr("bills.nextOn", next.medium))
        }
        return parts.joined(separator: " · ")
    }
}

/// Frequencies offered for manual entries (Plaid's names, so detected and manual streams share the math).
enum RecurringFrequency: String, CaseIterable, Identifiable {
    case weekly = "WEEKLY", biweekly = "BIWEEKLY", monthly = "MONTHLY", annually = "ANNUALLY"
    var id: String { rawValue }
    init(_ raw: String) { self = RecurringFrequency(rawValue: raw.uppercased()) ?? (raw.uppercased() == "SEMI_MONTHLY" ? .biweekly : .monthly) }
    var label: String { tr("freq.\(rawValue.lowercased())") }
}

extension AppModel {
    func recurringColor(_ r: RecurringStream) -> Color {
        Color(hexString: ledger.pocket(ledger.category(r.categoryId)?.pocketId)?.color ?? "#8B8B96")
    }
}

/// Add or edit a bill / subscription. Detected ones: name, type, category and hide; the bank sync owns amount and dates.
struct RecurringEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var stream: RecurringStream
    @State private var amountText = ""
    @State private var confirmDelete = false

    var body: some View {
        let manual = stream.isManual
        let isNew = !app.recurring.contains { $0.id == stream.id }
        NavigationStack {
            Form {
                Section {
                    TextField(tr("bills.name"), text: Binding(get: { stream.merchantName ?? stream.description },
                                                            set: { stream.merchantName = $0; if manual { stream.description = $0 } }))
                        .textInputAutocapitalization(.words)
                    Picker(tr("bills.type"), selection: Binding(get: { stream.kind ?? (app.isSubscription(stream) ? "subscription" : "bill") },
                                                                set: { stream.kind = $0 })) {
                        Text(tr("bills.subscriptionOne")).tag("subscription")
                        Text(tr("bills.billOne")).tag("bill")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if manual {
                        HStack {
                            Text(tr("bills.amount"))
                            Spacer()
                            TextField("0", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
                            Menu(stream.currency) {
                                ForEach(currencyChoices, id: \.self) { c in Button(c) { stream.currency = c } }
                            }
                        }
                        Picker(tr("bills.frequency"), selection: Binding(get: { RecurringFrequency(stream.frequency) }, set: { stream.frequency = $0.rawValue })) {
                            ForEach(RecurringFrequency.allCases) { Text($0.label).tag($0) }
                        }
                        DatePicker(tr("bills.nextPayment"), selection: Binding(get: { (stream.predictedNextDate ?? .today()).localDate() },
                                                                                set: { stream.predictedNextDate = Day(date: $0) }),
                                   displayedComponents: .date)
                    } else {
                        LabeledContent(tr("bills.amount"), value: money(stream.lastAmount, stream.currency, cents: true))
                        LabeledContent(tr("bills.frequency"), value: RecurringFrequency(stream.frequency).label)
                        if let next = stream.nextDue(onOrAfter: .today()) { LabeledContent(tr("bills.nextPayment"), value: next.medium) }
                    }
                } footer: {
                    if !manual { Text(tr("bills.detectedFooter")) }
                }

                Section {
                    Picker(tr("tx.category"), selection: $stream.categoryId) {
                        Text(tr("tx.uncategorized")).tag(UUID?.none)
                        ForEach(app.pockets.filter { !$0.isIncome }) { p in
                            Section(p.name) {
                                ForEach(app.categories.filter { $0.pocketId == p.id && !$0.archived }) { c in
                                    Label(c.name, systemImage: c.icon).tag(UUID?.some(c.id))
                                }
                            }
                        }
                    }
                    if manual {
                        Picker(tr("bills.paidFrom"), selection: $stream.accountId) {
                            Text(tr("bills.noAccount")).tag(UUID?.none)
                            ForEach(app.accounts.filter { !$0.isHidden }) { a in
                                Text("\(a.displayName)\(a.mask.map { " ··\($0)" } ?? "")").tag(UUID?.some(a.id))
                            }
                        }
                    }
                } footer: {
                    Text(tr("bills.categoryFooter"))
                }

                if !isNew {
                    Section {
                        if manual {
                            Button(tr("common.delete"), role: .destructive) { confirmDelete = true }
                        } else {
                            Button(stream.isHidden ? tr("bills.unhide") : tr("bills.hide")) {
                                stream.hidden = !stream.isHidden
                                save()
                            }
                        }
                    } footer: {
                        if !manual && !stream.isHidden { Text(tr("bills.hideFooter")) }
                    }
                }
            }
            .navigationTitle(isNew ? tr("bills.add") : stream.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common.save")) { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .confirmationDialog(tr("bills.deleteConfirm", stream.title), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(tr("common.delete"), role: .destructive) {
                    Task { await app.deleteRecurring(stream) }
                    dismiss()
                }
            }
            .onAppear {
                if stream.isManual && stream.lastAmount > 0 { amountText = "\(stream.lastAmount)" }
                if stream.isManual && stream.currency.isEmpty { stream.currency = app.currency }
            }
        }
        .presentationDetents([.large])
    }

    private var currencyChoices: [String] {
        Array(Set([app.currency] + app.accounts.map(\.currency) + ["USD", "CAD", "EUR"])).sorted()
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        let name = (stream.merchantName ?? stream.description).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        return !stream.isManual || (parsedAmount ?? 0) > 0
    }

    private func save() {
        var s = stream
        if s.isManual, let a = parsedAmount {
            s.averageAmount = a; s.lastAmount = a
        }
        let name = (s.merchantName ?? s.description).trimmingCharacters(in: .whitespaces)
        s.merchantName = name
        if s.isManual { s.description = name }
        Task { await app.saveRecurring(s) }
        dismiss()
    }
}

/// Home: bills & subscriptions at a glance (monthly total + what's next).
struct BillsGlanceCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let live = app.upcomingRecurring()
        let next = Array(live.prefix(3))
        let subs = live.filter { app.isSubscription($0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("bills.title")).font(.system(size: 17, weight: .bold))
                Spacer()
                NavigationLink(tr("common.seeAll"), value: Route.recurring)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
            }
            if live.isEmpty {
                NavigationLink(value: Route.recurring) {
                    Label(tr("bills.glanceEmpty"), systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                .buttonStyle(.row)
            } else {
                Text(tr("bills.glanceSummary", money(app.monthlyTotal(live), app.currency, cents: false), subs.count, live.count - subs.count))
                    .font(.system(size: 13)).foregroundStyle(Palette.text2)
                    .padding(.bottom, 2)
                ForEach(next) { r in
                    NavigationLink(value: Route.recurring) { RecurringRow(stream: r, compact: true) }.buttonStyle(.row)
                }
            }
        }
        .card(padding: 16)
    }
}
