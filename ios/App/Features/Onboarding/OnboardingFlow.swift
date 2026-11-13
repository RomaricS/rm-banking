import SwiftUI
import AkweKit

/// 1.2 Link banks → 1.3 First sync → 1.4 Pay schedule.
struct OnboardingFlow: View {
    enum Step: Int { case link, sync, schedule }
    @State private var step: Step = .link

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Capsule().fill(i <= step.rawValue ? Palette.inverse : Palette.text.opacity(0.14)).frame(height: 4)
                }
            }
            .animation(Motion.smooth, value: step)
            .padding(.horizontal, 16).padding(.top, 8)

            Group {
                switch step {
                case .link: LinkBanksView(onContinue: { go(.sync) })
                case .sync: FirstSyncView(onContinue: { go(.schedule) })
                case .schedule: PayScheduleView(onboarding: true)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        }
    }

    private func go(_ s: Step) { withAnimation(Motion.smooth) { step = s } }
}

/// Bank list with up to 4 slots. Used in onboarding and from Settings › Accounts.
struct LinkBanksView: View {
    @Environment(AppModel.self) private var app
    var onContinue: (() -> Void)?
    @State private var linker = PlaidLinker()
    @State private var opening = false
    /// Set while a bank Plaid just returned is being saved; drives the full-screen progress.
    @State private var adding: (name: String, stage: LinkStage)?

    private let maxBanks = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("link.title")).font(.system(size: 32, weight: .heavy)).tracking(-0.8)
                    Text(tr("link.subtitle", maxBanks)).font(.system(size: 15)).foregroundStyle(Palette.text2)
                }
                .padding(.top, 24)

                ForEach(Array(app.items.enumerated()), id: \.element.id) { i, item in
                    BankRow(item: item, accounts: app.accounts.filter { $0.itemId == item.id })
                        .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity), removal: .opacity))
                        .rise(i)
                }

                if app.items.count < maxBanks {
                    Button { Task { await addBank() } } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if opening { ProgressView().tint(Palette.iris) }
                                else { Image(systemName: "plus").font(.system(size: 20, weight: .bold)) }
                            }
                                .foregroundStyle(Palette.iris).frame(width: 44, height: 44)
                                .background(Palette.iris.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opening ? tr("link.opening") : app.items.isEmpty ? tr("link.addFirst") : tr("link.addAnother"))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(tr("link.slotsLeft", maxBanks - app.items.count)).font(.system(size: 13)).foregroundStyle(Palette.text2)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.iris.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.plain)
                    .disabled(opening || app.isDemo)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(Palette.positive)
                    Text(tr("link.security")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                }
                .card(padding: 14, radius: 18, fill: Palette.text.opacity(0.04))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let onContinue {
                Button(app.items.isEmpty ? tr("link.skip") : tr("link.continue", app.items.count), action: onContinue)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .animation(Motion.bouncy, value: app.items.count)
        .overlay {
            if let adding {
                AddingBankView(bankName: adding.name, stage: adding.stage)
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: adding?.stage)
        .animation(Motion.smooth, value: adding == nil)
        .interactiveDismissDisabled(adding != nil)
        .navigationBarBackButtonHidden(adding != nil)
        .toolbar(adding != nil ? .hidden : .automatic, for: .navigationBar)
    }

    private func addBank() async {
        opening = true
        defer { opening = false }
        do {
            let token = try await app.linkToken()
            guard let r = await linker.open(token: token) else { return }
            let name = r.institutionName ?? tr("link.yourBank")
            adding = (name, .importing)
            let ok = await app.exchange(publicToken: r.publicToken, institutionId: r.institutionId, institutionName: r.institutionName) { stage in
                adding = (name, stage)
            }
            // Let the success state register before the new row drops into its slot.
            if ok { try? await Task.sleep(for: .milliseconds(900)) }
            adding = nil
        } catch {
            adding = nil
            app.show(error)
        }
    }
}

struct BankRow: View {
    @Environment(AppModel.self) private var app
    let item: BankItem
    let accounts: [Account]
    @State private var linker = PlaidLinker()

    var body: some View {
        HStack(spacing: 12) {
            BankBadge(name: item.institutionName, color: accounts.first.map(app.accountColor) ?? Palette.iris, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.institutionName).font(.system(size: 16, weight: .bold))
                Text(accounts.map { "\($0.displayName)\($0.mask.map { " ··\($0)" } ?? "")" }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Palette.text2).lineLimit(1)
            }
            Spacer()
            if item.status.needsAttention {
                Button(tr("link.reconnect")) { Task { await repair() } }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.over)
            } else {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Palette.positive).frame(width: 28, height: 28)
                    .background(Palette.positive.opacity(0.16), in: Circle())
            }
        }
        .card(padding: 14, radius: 20)
    }

    private func repair() async {
        do {
            let token = try await app.linkToken(repairing: item.id)
            if await linker.open(token: token) != nil { await app.sync(itemId: item.id) }
        } catch { app.show(error) }
    }
}

/// 1.3 First sync.
struct FirstSyncView: View {
    @Environment(AppModel.self) private var app
    let onContinue: () -> Void
    @State private var spin = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 40)
            ZStack {
                Circle().fill(RadialGradient(colors: [Palette.aurora.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 130))
                    .frame(width: 240, height: 240).scaleEffect(spin ? 1.1 : 0.95)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: spin)
                Circle().stroke(Palette.text.opacity(0.08), lineWidth: 10).frame(width: 180)
                Circle().trim(from: 0, to: 0.28).stroke(Palette.iris, style: StrokeStyle(lineWidth: 10, lineCap: .round)).frame(width: 180)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                VStack(spacing: 2) {
                    Text("\(app.transactions.count)").font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(app.transactions.count)))
                    Text(tr("sync.transactions")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                }
            }
            VStack(spacing: 6) {
                Text(tr("sync.title")).font(.system(size: 26, weight: .heavy))
                Text(tr("sync.subtitle")).font(.system(size: 15)).foregroundStyle(Palette.text2)
            }
            VStack(spacing: 0) {
                ForEach(app.items) { item in
                    step(item.institutionName, done: item.lastSyncedAt != nil, meta: tr("sync.accounts", app.accounts.filter { $0.itemId == item.id }.count))
                }
                step(tr("sync.transfers"), done: !app.isSyncing && !app.transactions.isEmpty, meta: "")
                step(tr("sync.paycheck"), done: app.schedule.detected, meta: "")
            }
            .card(padding: 14)
            Spacer()
            Button(tr("sync.background"), action: onContinue).buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
        .onAppear { spin = true }
        .task {
            // Poll a few times while Plaid prepares historical data.
            for _ in 0..<6 {
                await app.load()
                if app.schedule.detected { break }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func step(_ label: String, done: Bool, meta: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Palette.positive)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.onInverse)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 26, height: 26)
            .animation(Motion.bouncy, value: done)
            Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(done ? Palette.text : Palette.text2)
            Spacer()
            Text(meta).font(.system(size: 13)).foregroundStyle(Palette.text2)
        }
        .frame(minHeight: 48)
    }
}
