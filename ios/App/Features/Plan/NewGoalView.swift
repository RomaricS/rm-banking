import SwiftUI
import AkweKit

/// 4.3 New goal
struct NewGoalView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "airplane"
    @State private var color = "#7C9CFF"
    @State private var amountText = ""
    @State private var dateChoice = 1
    @State private var customDate = Calendar.current.date(byAdding: .month, value: 18, to: Date())!
    @State private var funding: GoalFunding = .earmark
    @State private var accountId: UUID?
    @State private var earmarkText = ""
    @State private var saving = false

    private let icons = ["airplane", "house.fill", "shield.fill", "laptopcomputer", "car.fill", "gift.fill", "graduationcap.fill", "heart.fill", "star.fill"]
    private let colors = ["#7C9CFF", "#3DDC97", "#C084FC", "#FF9F5A", "#FF7EB6", "#FFB86B"]

    private var target: Decimal { Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var start: Decimal {
        switch funding {
        case .earmark: Decimal(string: earmarkText.replacingOccurrences(of: ",", with: ".")) ?? 0
        case .account: app.accounts.first { $0.id == accountId }.flatMap(\.currentBalance) ?? 0
        case .manual: 0
        }
    }
    private var deadline: Day? {
        let today = Day.today()
        switch dateChoice {
        case 0: return today.adding(days: 182)
        case 1: return today.adding(days: 365)
        case 2: return Day(date: customDate)
        default: return nil
        }
    }
    private var perPeriod: Decimal? {
        guard let deadline, target > start else { return nil }
        let n = app.ledger.payPeriods(from: .today(), to: deadline)
        return ((target - start) / Decimal(max(1, n))).rounded(0, .up)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(icons, id: \.self) { i in Button { icon = i } label: { Label(i, systemImage: i) } }
                        } label: { IconTile(systemName: icon, color: Color(hexString: color), size: 44) }
                        TextField(tr("goal.namePlaceholder"), text: $name).font(.system(size: 18, weight: .bold))
                    }
                    .card(padding: 12, radius: 18, fill: Palette.raised)

                    HStack(spacing: 10) {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hexString: c)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Palette.text, lineWidth: color == c ? 2 : 0).padding(-3))
                                .onTapGesture { color = c; Haptics.selection() }
                                .accessibilityAddTraits(.isButton)
                        }
                    }

                    VStack(spacing: 4) {
                        Text(tr("goal.targetAmount")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(MoneyFormat.symbol(for: app.currency)).font(.system(size: 40, weight: .heavy)).foregroundStyle(Palette.text2)
                            TextField("0", text: $amountText).keyboardType(.decimalPad).font(.system(size: 52, weight: .heavy)).fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("goal.reachBy")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
                        HStack(spacing: 8) {
                            choice(tr("goal.6months"), 0)
                            choice(tr("goal.1year"), 1)
                            choice(tr("goal.pickDate"), 2)
                            choice(tr("goal.noDate"), 3)
                        }
                        if dateChoice == 2 {
                            DatePicker("", selection: $customDate, in: Date()..., displayedComponents: .date).labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("goal.howTrack")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text2)
                        ForEach([GoalFunding.account, .earmark, .manual], id: \.self) { f in
                            Button { withAnimation(Motion.snappy) { funding = f } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tr("goal.funding.\(f.rawValue).option")).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                                        Text(tr("goal.funding.\(f.rawValue).hint")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                                    }
                                    Spacer()
                                    Image(systemName: funding == f ? "largecircle.fill.circle" : "circle").foregroundStyle(funding == f ? Palette.iris : Palette.text3)
                                }
                                .padding(14)
                                .background(funding == f ? Palette.iris.opacity(0.14) : Palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(funding == f ? Palette.iris : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                        if funding == .account {
                            Picker(tr("goal.account"), selection: $accountId) {
                                Text(tr("goal.chooseAccount")).tag(UUID?.none)
                                ForEach(app.accounts.filter { $0.type == "depository" }) { a in Text("\(a.displayName) ··\(a.mask ?? "")").tag(UUID?.some(a.id)) }
                            }
                        }
                        if funding == .earmark {
                            TextField(tr("goal.alreadySetAside"), text: $earmarkText).keyboardType(.decimalPad)
                                .padding(14).background(Palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    if let perPeriod {
                        HStack {
                            Text(tr("goal.everyPeriod")).font(.system(size: 14)).foregroundStyle(Palette.text2)
                            Spacer()
                            Text(money(perPeriod, app.currency, cents: false)).font(.system(size: 22, weight: .heavy)).foregroundStyle(Palette.positive)
                                .contentTransition(.numericText(value: perPeriod.doubleValue)).animation(Motion.numbers, value: perPeriod)
                        }
                        .card(padding: 14, radius: 18, fill: Palette.positive.opacity(0.1))
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.sheet)
            .navigationTitle(tr("goal.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(tr("goal.create")) {
                    saving = true
                    Task {
                        _ = await app.createGoal(name: name, icon: icon, color: color, target: target, date: deadline, funding: funding,
                                                 accountId: funding == .account ? accountId : nil, earmark: funding == .earmark ? start : nil)
                        Haptics.success()
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.isEmpty || target <= 0 || saving || (funding == .account && accountId == nil))
                .padding(16)
            }
        }
    }

    private func choice(_ label: String, _ i: Int) -> some View {
        Button { withAnimation(Motion.snappy) { dateChoice = i } } label: {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(dateChoice == i ? Palette.iris.opacity(0.16) : Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(dateChoice == i ? Palette.iris : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
