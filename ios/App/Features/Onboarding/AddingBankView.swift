import SwiftUI

/// Where a bank link is, from the moment Plaid Link reports success until the new row is on screen.
/// Stages follow real work: `plaid-exchange` imports accounts + history server-side, then the app reloads.
enum LinkStage: Int, Comparable {
    case importing, finishing, done
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Full-screen, non-dismissable progress shown while a newly linked bank is being added.
/// Exists so a ~5–15 s server import never looks like a frozen screen the user should retry.
struct AddingBankView: View {
    let bankName: String
    let stage: LinkStage
    @State private var pulse = false
    @State private var slow = false

    var body: some View {
        ZStack {
            Palette.ground.opacity(0.94).ignoresSafeArea()
            Circle()
                .fill(RadialGradient(colors: [Palette.aurora.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 160))
                .frame(width: 320, height: 320)
                .scaleEffect(pulse ? 1.08 : 0.92)
                .offset(y: -150)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
                .accessibilityHidden(true)

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle().stroke(Palette.text.opacity(0.08), lineWidth: 6).frame(width: 112, height: 112)
                    if stage == .done {
                        Circle().fill(Palette.positive).frame(width: 112, height: 112).transition(.scale.combined(with: .opacity))
                        Image(systemName: "checkmark").font(.system(size: 40, weight: .heavy)).foregroundStyle(Palette.onInverse)
                            .transition(.scale)
                    } else {
                        Circle().trim(from: 0, to: 0.26)
                            .stroke(Palette.iris, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 112, height: 112)
                            .rotationEffect(.degrees(pulse ? 360 : 0))
                            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                        BankBadge(name: bankName, color: Palette.iris, size: 72)
                    }
                }
                .animation(Motion.bouncy, value: stage)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(stage == .done ? tr("adding.doneTitle", bankName) : tr("adding.title", bankName))
                        .font(.system(size: 26, weight: .heavy)).tracking(-0.5).multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    Text(slow ? tr("adding.slow") : tr("adding.subtitle"))
                        .font(.system(size: 15)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 12)

                VStack(spacing: 0) {
                    row(tr("adding.step.connected", bankName), state: .done)
                    row(tr("adding.step.importing"), state: rowState(.importing))
                    row(tr("adding.step.finishing"), state: rowState(.finishing))
                }
                .card(padding: 14)

                Spacer()
                Label(tr("adding.keepOpen"), systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text3)
                    .opacity(stage == .done ? 0 : 1)
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { pulse = true }
        .task {
            // Sandbox takes ~7 s; real banks can take much longer. Reassure instead of looking stuck.
            try? await Task.sleep(for: .seconds(12))
            withAnimation { slow = true }
        }
    }

    private enum RowState { case done, active, todo }

    private func rowState(_ s: LinkStage) -> RowState {
        stage > s ? .done : stage == s ? .active : .todo
    }

    private func row(_ label: String, state: RowState) -> some View {
        HStack(spacing: 12) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Palette.positive)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.onInverse)
                case .active:
                    ProgressView().controlSize(.small)
                case .todo:
                    Circle().strokeBorder(Palette.text.opacity(0.16), lineWidth: 2)
                }
            }
            .frame(width: 26, height: 26)
            .animation(Motion.bouncy, value: state == .done)
            Text(label).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == .todo ? Palette.text3 : Palette.text)
            Spacer()
        }
        .frame(minHeight: 48)
    }
}
