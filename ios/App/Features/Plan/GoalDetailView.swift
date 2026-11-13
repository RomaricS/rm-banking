import SwiftUI
import Charts
import AkweKit

/// 4.2 Goal detail (personal) / 6.1 Shared goal.
struct GoalDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let goalId: UUID
    @State private var contributing = false
    @State private var amountText = ""
    @State private var inviting = false
    @State private var confirmArchive = false
    @State private var cheered = false
    @State private var burst = 0

    var body: some View {
        if let goal = app.goals.first(where: { $0.id == goalId }) {
            content(goal)
        } else {
            EmptyState(icon: "target", title: tr("goal.gone"), message: "")
        }
    }

    private func content(_ goal: Goal) -> some View {
        let ledger = app.ledger
        let p = ledger.goalProgress(goal)
        let color = Color(hexString: goal.color)
        let me = p.members.first { $0.userId == app.userId }
        let partner = p.members.first { $0.userId != app.userId }
        let funding = app.ownFunding.first { $0.goalId == goal.id }
        let goalEvents = app.events.filter { $0.goalId == goal.id }.prefix(8)

        return ScrollView {
            ZStack(alignment: .top) {
                AuroraBackground(tint: p.isShared ? Color(hex: 0x5B2A6E) : Color(hex: 0x3A4FD9), secondary: color.opacity(0.4), height: 420)
                VStack(spacing: 16) {
                    if p.isShared, let partner {
                        Text(tr("goal.sharedWith", partner.displayName ?? tr("goal.partner"))).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.partner)
                    }
                    ZStack {
                        if p.isShared, let partner {
                            let mine = ((me?.currentAmount ?? 0) / goal.targetAmount).doubleValue
                            let theirs = ((partner.currentAmount ?? ((partner.sharePct ?? 0) / 100 * goal.targetAmount)) / goal.targetAmount).doubleValue
                            SplitRing(first: min(1, mine), second: min(1, theirs))
                        } else {
                            RingProgress(fraction: p.fraction, color: color, lineWidth: 14)
                        }
                        VStack(spacing: 2) {
                            AmountText(amount: p.saved, currency: goal.currency, font: .system(size: 32, weight: .heavy), cents: false)
                            Text(tr("goal.ofTarget", money(goal.targetAmount, goal.currency, cents: false), Int((p.fraction * 100).rounded())))
                                .font(.system(size: 13)).foregroundStyle(Palette.text2)
                        }
                        MilestoneBurst(trigger: burst, color: color)
                    }
                    .frame(width: 200, height: 200)
                    .padding(.top, 8)

                    if p.isShared {
                        HStack(spacing: 8) {
                            memberTile(tr("goal.you"), me?.currentAmount, color: Color(hex: 0x7C9CFF), currency: goal.currency)
                            memberTile(partner?.displayName ?? tr("goal.partner"), partner?.currentAmount, color: Palette.partner, currency: goal.currency, pct: partner?.sharePct)
                        }
                    } else {
                        HStack(spacing: 8) {
                            stat(tr("goal.perPeriod"), p.requiredPerPeriod.map { money($0, goal.currency, cents: false) } ?? "—")
                            stat(p.periodsLeft.map { tr("goal.periodsLeft", $0) } ?? tr("goal.target"), goal.targetDate?.full ?? "—")
                        }
                    }

                    if goal.targetDate != nil { ProjectionChart(progress: p, color: color).card() }

                    milestones(p, color: color)

                    if let funding {
                        HStack(spacing: 12) {
                            IconTile(systemName: funding.funding == .account ? "building.columns.fill" : (funding.funding == .earmark ? "tray.full.fill" : "hand.raised.fill"), color: Palette.iris, size: 36, radius: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fundingTitle(funding)).font(.system(size: 15, weight: .semibold))
                                Text(tr("goal.funding.\(funding.funding.rawValue).hint")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                            }
                            Spacer()
                        }
                        .card(padding: 14)
                    }

                    if !goalEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(goalEvents)) { e in eventRow(e, goal: goal) }
                        }
                        .card(padding: 14)
                    }

                    HStack(spacing: 8) {
                        if p.isShared {
                            Button(cheered ? tr("goal.cheered") : tr("goal.cheer", partner?.displayName ?? "")) {
                                Task { await app.cheer(goal); withAnimation(Motion.bouncy) { cheered = true } }
                            }
                            .buttonStyle(PrimaryButtonStyle(fill: Palette.partner.opacity(0.18), foreground: Palette.partner))
                            .disabled(cheered)
                        }
                        if funding?.funding != .account {
                            Button(tr("goal.add")) { contributing = true }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarClearance)
            }
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !p.isShared && goal.ownerId == app.userId {
                        Button { inviting = true } label: { Label(tr("goal.share"), systemImage: "person.badge.plus") }
                    }
                    Button { amountText = ""; contributing = true } label: { Label(tr("goal.withdraw"), systemImage: "minus.circle") }
                    if p.isShared {
                        Button(role: .destructive) { Task { await app.leave(goal); dismiss() } } label: { Label(tr("goal.leave"), systemImage: "rectangle.portrait.and.arrow.right") }
                    } else {
                        Button(role: .destructive) { confirmArchive = true } label: { Label(tr("goal.archive"), systemImage: "archivebox") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert(tr("goal.addTitle"), isPresented: $contributing) {
            TextField(tr("goal.amountPlaceholder"), text: $amountText).keyboardType(.decimalPad)
            Button(tr("goal.add")) { submit(goal, sign: 1, before: p) }
            Button(tr("goal.withdraw")) { submit(goal, sign: -1, before: p) }
            Button(tr("common.cancel"), role: .cancel) {}
        } message: { Text(tr("goal.addHint")) }
        .confirmationDialog(tr("goal.archiveConfirm"), isPresented: $confirmArchive, titleVisibility: .visible) {
            Button(tr("goal.archive"), role: .destructive) { Task { await app.archiveGoal(goal); dismiss() } }
        }
        .sheet(isPresented: $inviting) { InviteSheet(goal: goal) }
    }

    private func submit(_ goal: Goal, sign: Decimal, before: GoalProgress) {
        guard let v = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
        let beforeMilestone = before.milestones.filter(\.reached).count
        Task {
            await app.contribute(goal, amount: v * sign)
            let after = app.ledger.goalProgress(goal).milestones.filter(\.reached).count
            if after > beforeMilestone { burst += 1 }
        }
        amountText = ""
    }

    private func fundingTitle(_ f: GoalFundingSettings) -> String {
        switch f.funding {
        case .account: tr("goal.funding.account.title", app.accounts.first { $0.id == f.accountId }?.displayName ?? "")
        case .earmark: tr("goal.funding.earmark.title")
        case .manual: tr("goal.funding.manual.title")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.text2)
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
        .card(padding: 12, radius: Radius.tile)
    }

    private func memberTile(_ name: String, _ amount: Decimal?, color: Color, currency: String, pct: Decimal? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(name).font(.system(size: 12)).foregroundStyle(Palette.text2) }
            if let amount {
                AmountText(amount: amount, currency: currency, font: .system(size: 20, weight: .bold), cents: false)
            } else {
                Text(tr("goal.shareOnly", "\(Int((pct ?? 0).doubleValue.rounded()))")).font(.system(size: 20, weight: .bold))
            }
        }
        .card(padding: 12, radius: Radius.tile)
    }

    private func milestones(_ p: GoalProgress, color: Color) -> some View {
        HStack {
            ForEach(p.milestones, id: \.value) { m in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(m.reached ? color : .clear).overlay(Circle().stroke(m.reached ? color : Palette.text.opacity(0.2), lineWidth: 1.5))
                        if m.reached { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Palette.onInverse) }
                    }
                    .frame(width: 36, height: 36)
                    Text(m.value == 100 ? tr("goal.goal") : "\(m.value)%").font(.system(size: 12)).foregroundStyle(Palette.text2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card(padding: 14)
    }

    private func eventRow(_ e: GoalEvent, goal: Goal) -> some View {
        let mine = e.userId == app.userId
        let who = mine ? tr("goal.you") : (app.members.first { $0.userId == e.userId && $0.goalId == goal.id }?.displayName ?? tr("goal.partner"))
        let text: String = {
            switch e.kind {
            case "contribution": return tr("goal.event.contribution", who)
            case "withdrawal": return tr("goal.event.withdrawal", who)
            case "milestone": return tr("goal.event.milestone", Int(e.amount?.doubleValue ?? 0))
            case "reached": return tr("goal.event.reached")
            case "joined": return tr("goal.event.joined", who)
            case "cheer": return tr("goal.event.cheer", who)
            default: return e.kind
            }
        }()
        return HStack(spacing: 12) {
            Text(String(who.prefix(1))).font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.onInverse)
                .frame(width: 30, height: 30).background(mine ? Color(hex: 0x7C9CFF) : Palette.partner, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 14, weight: .semibold))
                Text(e.createdAt.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(Palette.text2)
            }
            Spacer()
            if let a = e.amount, e.kind == "contribution" || e.kind == "withdrawal" {
                AmountText(amount: e.kind == "withdrawal" ? -a : a, currency: goal.currency, font: .system(size: 14, weight: .bold), cents: false, signed: true, color: e.kind == "withdrawal" ? Palette.over : Palette.positive)
            }
        }
        .frame(minHeight: 52)
    }
}

/// Saved so far + straight-line projection to the target date.
struct ProjectionChart: View {
    let progress: GoalProgress
    let color: Color
    @State private var drawn = false

    var body: some View {
        let g = progress.goal
        let start = Day(date: g.createdAt)
        let today = Day.today()
        let end = g.targetDate ?? today
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("goal.projection")).font(.system(size: 15, weight: .bold))
                Spacer()
                GoalStatusText(progress: progress)
            }
            Chart {
                LineMark(x: .value("Date", start.date), y: .value("Saved", 0), series: .value("S", "saved")).foregroundStyle(color)
                LineMark(x: .value("Date", today.date), y: .value("Saved", progress.saved.doubleValue), series: .value("S", "saved"))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                if drawn {
                    LineMark(x: .value("Date", today.date), y: .value("Saved", progress.saved.doubleValue), series: .value("S", "proj"))
                        .foregroundStyle(color.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 5]))
                    LineMark(x: .value("Date", end.date), y: .value("Saved", g.targetAmount.doubleValue), series: .value("S", "proj"))
                        .foregroundStyle(color.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 5]))
                }
                PointMark(x: .value("Date", today.date), y: .value("Saved", progress.saved.doubleValue)).foregroundStyle(color)
                RuleMark(y: .value("Target", g.targetAmount.doubleValue)).foregroundStyle(Palette.text.opacity(0.15)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 120)
        }
        .onAppear { withAnimation(.smooth(duration: 0.9).delay(1.0)) { drawn = true } }
    }
}

/// Particle burst when a milestone is crossed (canvas › Motion › Milestone burst).
struct MilestoneBurst: View {
    let trigger: Int
    let color: Color
    @State private var fire = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * .pi
                Circle()
                    .fill([color, Palette.mint, Palette.warning, Palette.partner, .white][i % 5])
                    .frame(width: CGFloat(6 + i % 3 * 2))
                    .offset(x: fire ? cos(angle) * 120 : 0, y: fire ? sin(angle) * 120 : 0)
                    .opacity(fire ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .opacity(trigger == 0 ? 0 : 1)
        .onChange(of: trigger) { _, _ in
            fire = false
            Haptics.success()
            withAnimation(.easeOut(duration: 1.1)) { fire = true }
        }
        .accessibilityHidden(true)
    }
}
