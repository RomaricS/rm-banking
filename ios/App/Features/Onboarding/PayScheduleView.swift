import SwiftUI
import AkweKit

/// 1.4 Pay schedule (also reachable from Settings).
struct PayScheduleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onboarding = false
    @State private var frequency: PayFrequency = .biweekly
    /// Any known payday; for weekly / every 2 weeks / monthly the user sets it by picking the next payday.
    @State private var anchor = Date()
    /// Twice a month: the two days, in tap order (oldest is replaced when a third is tapped).
    @State private var semiDays: [Int] = [1, 15]
    @State private var editingNext = false

    private var today: Day { .today() }

    private var draft: PaySchedule {
        PaySchedule(frequency: frequency, anchorDate: Day(date: anchor), semimonthlyDays: semiDays.sorted(),
                    incomeSource: app.schedule.incomeSource, typicalAmount: app.schedule.typicalAmount)
    }

    private var isComplete: Bool { frequency != .semimonthly || semiDays.count == 2 }

    private var paydays: [Day] {
        let dates: [Day] = app.transactions
            .filter { $0.kind == .income && $0.amount > 100 }
            .map { $0.date }
            .sorted()
        return Array(dates.suffix(5))
    }

    /// The next payday and the two after it, so the pattern can be checked at a glance.
    private var upcoming: [Day] {
        guard isComplete else { return [] }
        var out = [draft.nextPayday(after: today)]
        while out.count < 3, let last = out.last { out.append(draft.nextPayday(after: last)) }
        return out
    }

    /// Next payday can be any day within one pay period from tomorrow.
    private var nextRange: ClosedRange<Date> {
        let len = switch frequency { case .weekly: 7; case .biweekly: 14; default: 31 }
        return today.adding(days: 1).localDate()...today.adding(days: len).localDate()
    }

    private var nextBinding: Binding<Date> {
        Binding(get: { draft.nextPayday(after: today).localDate() },
                set: { anchor = $0; Haptics.selection() })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.schedule.detected ? tr("pay.foundTitle") : tr("pay.setTitle")).font(.system(size: 32, weight: .heavy)).tracking(-0.8)
                    Text(tr("pay.subtitle")).font(.system(size: 15)).foregroundStyle(Palette.text2)
                }
                .padding(.top, 24)

                if app.schedule.detected, !paydays.isEmpty { detectedCard }

                frequencyPicker

                if frequency == .semimonthly { dayGrid } else { nextPaydayCard }

                if !upcoming.isEmpty { upcomingRow }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button(isComplete ? tr("pay.use") : tr("pay.pickTwo")) {
                Task {
                    await app.savePaySchedule(draft)
                    Haptics.success()
                    if onboarding { await app.completeOnboarding() } else { dismiss() }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isComplete)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .onAppear {
            frequency = app.schedule.frequency
            anchor = app.schedule.anchorDate.localDate()
            if app.schedule.semimonthlyDays.count == 2 { semiDays = app.schedule.semimonthlyDays }
        }
        .navigationTitle(onboarding ? "" : tr("settings.paySchedule"))
    }

    // MARK: Sections

    private var detectedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(app.schedule.incomeSource?.capitalized ?? tr("pay.income")).font(.system(size: 16, weight: .bold))
                Spacer()
                if let amt = app.schedule.typicalAmount {
                    AmountText(amount: amt, currency: app.currency, font: .system(size: 20, weight: .heavy), signed: true, color: Palette.positive)
                }
            }
            HStack {
                ForEach(Array((paydays + [draft.nextPayday(after: today)]).enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 8) {
                        Circle().fill(i < paydays.count ? Palette.positive : .clear)
                            .overlay(Circle().stroke(Palette.positive, lineWidth: 2))
                            .frame(width: 22, height: 22)
                            .rise(i)
                        Text(d.short).font(.system(size: 11, weight: .semibold)).foregroundStyle(i < paydays.count ? Palette.text2 : Palette.positive)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    private var frequencyPicker: some View {
        VStack(spacing: 0) {
            ForEach(PayFrequency.allCases, id: \.self) { f in
                Button {
                    Haptics.selection()
                    withAnimation(Motion.snappy) { frequency = f; editingNext = false }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            Text(tr("pay.hint.\(f.rawValue)")).font(.system(size: 12)).foregroundStyle(Palette.text2)
                        }
                        Spacer()
                        Image(systemName: frequency == f ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(frequency == f ? Palette.iris : Palette.text3)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(frequency == f ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16).background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Weekly / every 2 weeks / monthly: the next payday is directly editable; later ones follow.
    private var nextPaydayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.selection()
                withAnimation(Motion.snappy) { editingNext.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("pay.next")).font(.system(size: 14)).foregroundStyle(Palette.text2)
                        Text(draft.nextPayday(after: today).long).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.positive)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text(editingNext ? tr("common.done") : tr("pay.editNext"))
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.iris)
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(Palette.iris.opacity(0.14), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editingNext {
                DatePicker(tr("pay.next"), selection: nextBinding, in: nextRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Palette.iris)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Text(tr("pay.nextHint")).font(.system(size: 12)).foregroundStyle(Palette.text2)
            }
        }
        .card(padding: 14, radius: 18, fill: Palette.positive.opacity(0.1))
    }

    /// Twice a month: pick the two days of the month on a 1–31 grid.
    private var dayGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("pay.pickDays")).font(.system(size: 15, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(1...31, id: \.self) { d in
                    let on = semiDays.contains(d)
                    Button { toggle(d) } label: {
                        Text("\(d)").font(.system(size: 15, weight: on ? .heavy : .medium)).monospacedDigit()
                            .foregroundStyle(on ? Palette.onInverse : Palette.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Palette.iris : Palette.text.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("pay.dayA11y", d))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(tr("pay.pickDaysHint")).font(.system(size: 12)).foregroundStyle(Palette.text2)
        }
        .card(padding: 14)
        .animation(Motion.snappy, value: semiDays)
    }

    private var upcomingRow: some View {
        HStack {
            Text(tr("pay.upcoming")).font(.system(size: 14)).foregroundStyle(Palette.text2)
            Spacer()
            Text(upcoming.map(\.short).joined(separator: " · "))
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ d: Int) {
        Haptics.selection()
        if let i = semiDays.firstIndex(of: d) { semiDays.remove(at: i); return }
        if semiDays.count == 2 { semiDays.removeFirst() }
        semiDays.append(d)
    }
}
