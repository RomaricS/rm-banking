import SwiftUI
import AkweKit

/// 1.4 Pay schedule (also reachable from Settings).
struct PayScheduleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onboarding = false
    @State private var frequency: PayFrequency = .biweekly
    @State private var anchor = Date()
    @State private var firstDay = 1
    @State private var secondDay = 15

    private var draft: PaySchedule {
        PaySchedule(frequency: frequency, anchorDate: Day(date: anchor), semimonthlyDays: [firstDay, secondDay],
                    incomeSource: app.schedule.incomeSource, typicalAmount: app.schedule.typicalAmount)
    }

    private var paydays: [Day] {
        app.transactions.filter { $0.kind == .income && $0.amount > 100 }.map(\.date).sorted().suffix(5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.schedule.detected ? tr("pay.foundTitle") : tr("pay.setTitle")).font(.system(size: 32, weight: .heavy)).tracking(-0.8)
                    Text(tr("pay.subtitle")).font(.system(size: 15)).foregroundStyle(Palette.text2)
                }
                .padding(.top, 24)

                if app.schedule.detected, !paydays.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(app.schedule.incomeSource?.capitalized ?? tr("pay.income")).font(.system(size: 16, weight: .bold))
                            Spacer()
                            if let amt = app.schedule.typicalAmount {
                                AmountText(amount: amt, currency: app.currency, font: .system(size: 20, weight: .heavy), signed: true, color: Palette.positive)
                            }
                        }
                        HStack {
                            ForEach(Array((paydays + [draft.nextPayday(after: .today())]).enumerated()), id: \.offset) { i, d in
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

                VStack(spacing: 0) {
                    ForEach(PayFrequency.allCases, id: \.self) { f in
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.snappy) { frequency = f }
                        } label: {
                            HStack {
                                Text(f.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Spacer()
                                Image(systemName: frequency == f ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(frequency == f ? Palette.iris : Palette.text3)
                            }
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(frequency == f ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                if frequency == .semimonthly {
                    HStack {
                        Stepper(tr("pay.firstDay", firstDay), value: $firstDay, in: 1...28)
                    }.card(padding: 14)
                    HStack {
                        Stepper(tr("pay.secondDay", secondDay), value: $secondDay, in: 2...31)
                    }.card(padding: 14)
                } else {
                    DatePicker(tr("pay.lastPayday"), selection: $anchor, displayedComponents: .date).card(padding: 14)
                }

                HStack {
                    Text(tr("pay.next")).font(.system(size: 14)).foregroundStyle(Palette.text2)
                    Spacer()
                    Text(draft.nextPayday(after: .today()).medium).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.positive)
                }
                .card(padding: 14, radius: 18, fill: Palette.positive.opacity(0.1))
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button(tr("pay.use")) {
                Task {
                    await app.savePaySchedule(draft)
                    Haptics.success()
                    if onboarding { await app.completeOnboarding() } else { dismiss() }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .onAppear {
            frequency = app.schedule.frequency
            anchor = app.schedule.anchorDate.localDate()
            if app.schedule.semimonthlyDays.count == 2 { firstDay = app.schedule.semimonthlyDays[0]; secondDay = app.schedule.semimonthlyDays[1] }
        }
        .navigationTitle(onboarding ? "" : tr("settings.paySchedule"))
    }
}
