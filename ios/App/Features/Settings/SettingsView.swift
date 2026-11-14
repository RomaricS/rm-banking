import SwiftUI
import AkweKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var editingSchedule = false
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        @Bindable var app = app
        List {
            Section {
                Button {
                    nameDraft = app.firstName ?? ""
                    editingName = true
                } label: {
                    HStack(spacing: 14) {
                        CowrieMark(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.firstName ?? tr("settings.addName"))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(app.firstName == nil ? Palette.text2 : Palette.text)
                            Text(app.isDemo ? tr("settings.demo") : tr("settings.signedInApple")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                        }
                        Spacer()
                        Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text3)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.row)
                .accessibilityHint(tr("settings.editName"))
            }

            Section(tr("settings.money")) {
                NavigationLink(value: Route.accounts) { row("building.columns.fill", tr("settings.accounts"), "\(app.items.count)/4") }
                Button { editingSchedule = true } label: { row("calendar", tr("settings.paySchedule"), app.schedule.frequency.label) }
                NavigationLink(value: Route.currency) { row("dollarsign.circle.fill", tr("settings.currency"), app.currency) }
                NavigationLink(value: Route.managePockets) { row("square.grid.2x2.fill", tr("pockets.title"), "\(app.pockets.count)") }
            }

            Section(tr("settings.app")) {
                NavigationLink(value: Route.alerts) { row("bell.badge.fill", tr("alerts.title"), "") }
                Picker(selection: $app.appearance) {
                    Text(tr("appearance.system")).tag(Appearance.system)
                    Text(tr("appearance.light")).tag(Appearance.light)
                    Text(tr("appearance.dark")).tag(Appearance.dark)
                } label: { row("circle.lefthalf.filled", tr("settings.appearance"), "") }
                Toggle(isOn: $app.faceIDEnabled) { row("faceid", tr("settings.faceID"), "") }.tint(Palette.positive)
                Toggle(isOn: $app.hideBalances) { row("eye.slash.fill", tr("home.hideBalances"), "") }.tint(Palette.positive)
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: {
                    row("globe", tr("settings.language"), Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en")?.capitalized ?? "")
                }
            }

            if !app.isDemo {
                Section {
                    Button(tr("settings.signOut")) { confirmSignOut = true }
                    Button(tr("settings.delete"), role: .destructive) { confirmDelete = true }
                } footer: {
                    Text(tr("settings.deleteHint")).font(.footnote)
                }
            }

            Section {
                Text("akwe · akwɛ = \(tr("settings.meaning"))").font(.footnote).foregroundStyle(Palette.text3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(tr("settings.editName"), isPresented: $editingName) {
            TextField(tr("settings.firstName"), text: $nameDraft)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
            Button(tr("common.cancel"), role: .cancel) {}
            Button(tr("common.save")) { Task { await app.setDisplayName(nameDraft) } }
        }
        .sheet(isPresented: $editingSchedule) { NavigationStack { PayScheduleView() } }
        .confirmationDialog(tr("settings.signOut"), isPresented: $confirmSignOut) {
            Button(tr("settings.signOut"), role: .destructive) { Task { await app.signOut() } }
        }
        .confirmationDialog(tr("settings.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("settings.delete"), role: .destructive) { Task { await app.deleteAccount() } }
        } message: { Text(tr("settings.deleteHint")) }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.iris).frame(width: 24)
            Text(title).foregroundStyle(Palette.text)
            Spacer()
            Text(value).foregroundStyle(Palette.text2)
        }
    }
}

/// 5.2 Alert settings
struct AlertSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.prefs
        List {
            Section(tr("alerts.goals")) {
                toggle("target", tr("alerts.goalReached"), tr("alerts.goalReachedHint"), p.goalReached) { $0.goalReached = $1 }
                toggle("flag.fill", tr("alerts.milestones"), tr("alerts.milestonesHint"), p.goalMilestones) { $0.goalMilestones = $1 }
            }
            Section(tr("alerts.limits")) {
                toggle("gauge.with.dots.needle.67percent", tr("alerts.warning"), tr("alerts.warningHint"), p.budgetWarning) { $0.budgetWarning = $1 }
                toggle("bolt.fill", tr("alerts.exceeded"), tr("alerts.exceededHint"), p.budgetExceeded) { $0.budgetExceeded = $1 }
            }
            Section(tr("alerts.money")) {
                toggle("calendar", tr("alerts.bills"), tr("alerts.billsHint"), p.billsDue) { $0.billsDue = $1 }
                toggle("arrow.down.left", tr("alerts.payday"), tr("alerts.paydayHint"), p.paydaySummary) { $0.paydaySummary = $1 }
                toggle("link", tr("alerts.reauth"), tr("alerts.reauthHint"), p.reauth) { $0.reauth = $1 }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("alerts.title"))
    }

    private func toggle(_ icon: String, _ title: String, _ hint: String, _ value: Bool, set: @escaping (inout NotificationPrefs, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { v in var np = app.prefs; set(&np, v); Task { await app.setPrefs(np) } })) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Palette.iris).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(hint).font(.system(size: 12)).foregroundStyle(Palette.text2)
                }
            }
        }
        .tint(Palette.positive)
    }
}

/// 6.5 Display currency
struct CurrencyView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let ledger = app.ledger
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("currency.subtitle")).font(.system(size: 15)).foregroundStyle(Palette.text2)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(supportedDisplayCurrencies.filter { app.rates.canConvert(from: "EUR", to: $0) || $0 == app.currency || app.rates.isEmpty }, id: \.self) { code in
                        Button {
                            Haptics.selection()
                            Task { await app.setCurrency(code) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(MoneyFormat.symbol(for: code)).font(.system(size: 20, weight: .heavy))
                                Text(code).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2)
                            }
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .background(app.currency == code ? Palette.iris.opacity(0.16) : Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.currency == code ? Palette.iris : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.row)
                        .accessibilityAddTraits(app.currency == code ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(tr("currency.totalBalance")).foregroundStyle(Palette.text2)
                        Spacer()
                        AmountText(amount: ledger.totalBalance, currency: app.currency, font: .system(size: 26, weight: .heavy), cents: true)
                    }
                    Divider()
                    ForEach(app.transactions.filter { $0.currency != app.currency }.prefix(4)) { t in
                        HStack {
                            Text(t.title).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                AmountText(amount: ledger.value(t), currency: app.currency, font: .system(size: 15, weight: .semibold), cents: true)
                                Text(money(t.amount, t.currency, cents: true)).font(.system(size: 12)).foregroundStyle(Palette.text2)
                            }
                        }
                    }
                }
                .card()

                Label(tr("currency.note"), systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.text2)
                    .card(padding: 12, radius: 16, fill: Palette.text.opacity(0.04))
            }
            .padding(.horizontal, 16).padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("settings.currency"))
    }
}
