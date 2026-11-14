import SwiftUI
import AkweKit

/// 2.4 Review inbox — swipe right = looks good, swipe left = change category.
struct ReviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Transaction] = []
    @State private var total = 0
    @State private var drag: CGSize = .zero
    @State private var picking: Transaction?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(queue.isEmpty ? "" : tr("review.position", total - queue.count + 1, total))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text2)
                Spacer()
                if !queue.isEmpty {
                    Button(tr("review.acceptAll")) { Task { for t in queue { await app.confirmReview(t) }; withAnimation { queue = [] } } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            progress

            ZStack {
                if queue.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Palette.positive).symbolEffect(.bounce, value: queue.isEmpty)
                        Text(tr("review.done")).font(.system(size: 22, weight: .heavy))
                        Button(tr("common.close")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                ForEach(Array(queue.prefix(3).enumerated().reversed()), id: \.element.id) { i, t in
                    ReviewCard(tx: t, onPick: { categoryId in Task { await app.setCategory(t, to: categoryId); advance() } })
                        .scaleEffect(1 - CGFloat(i) * 0.05)
                        .offset(y: CGFloat(i) * 14)
                        .offset(i == 0 ? drag : .zero)
                        .rotationEffect(.degrees(i == 0 ? Double(drag.width / 18) : 0))
                        .overlay {
                            if i == 0 {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(drag.width > 0 ? Palette.positive : Palette.over, lineWidth: 2)
                                    .opacity(min(1, abs(drag.width) / 120))
                            }
                        }
                        .gesture(dragGesture(t), including: i == 0 ? .all : .subviews)
                        .allowsHitTesting(i == 0)
                        .zIndex(Double(3 - i))
                }
            }
            .frame(maxHeight: .infinity)

            if let top = queue.first {
                HStack(spacing: 28) {
                    roundButton("pencil", tr("review.change"), color: Palette.over, size: 72) { picking = top }
                    roundButton("checkmark", tr("review.good"), color: Palette.positive, size: 88, filled: true) { Task { await approve(top) } }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        // Never wider than the screen, whatever a child asks for.
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.bottom, tabBarClearance - 20)
        .background(Palette.ground)
        .navigationTitle(tr("review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if queue.isEmpty { queue = app.ledger.needsReview; total = queue.count }
        }
        .sheet(item: $picking) { t in
            CategoryPicker(tx: t) { _ in }
                .onDisappear { if app.transactions.first(where: { $0.id == t.id })?.needsReview == false { advance() } }
        }
    }

    /// One segment per transaction for short queues; a single bar for long ones. (122 segments
    /// with 4-pt gaps needed ~480 pt and pushed the whole screen wider than the display.)
    @ViewBuilder private var progress: some View {
        let done = total - queue.count
        if total <= 12 {
            HStack(spacing: 4) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule().fill(i < done ? Palette.positive : (i == done ? Palette.text : Palette.text.opacity(0.14))).frame(height: 4)
                }
            }
        } else {
            ProgressBar(fraction: total > 0 ? Double(done) / Double(total) : 0, color: Palette.positive, height: 4)
                .animation(Motion.smooth, value: done)
        }
    }

    private func dragGesture(_ t: Transaction) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if v.translation.width > 120 {
                    withAnimation(.easeIn(duration: 0.22)) { drag = CGSize(width: 600, height: v.translation.height) }
                    Task { try? await Task.sleep(for: .milliseconds(200)); await approve(t) }
                } else if v.translation.width < -120 {
                    withAnimation(Motion.bouncy) { drag = .zero }
                    picking = t
                } else {
                    withAnimation(Motion.bouncy) { drag = .zero }
                }
            }
    }

    private func approve(_ t: Transaction) async {
        Haptics.light()
        await app.confirmReview(t)
        advance()
    }

    private func advance() {
        withAnimation(Motion.bouncy) {
            if !queue.isEmpty { queue.removeFirst() }
            drag = .zero
        }
        if queue.isEmpty { Haptics.success() }
    }

    private func roundButton(_ icon: String, _ label: String, color: Color, size: CGFloat, filled: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(filled ? Palette.onInverse : color)
                    .frame(width: size, height: size)
                    .background(filled ? color : color.opacity(0.16), in: Circle())
                    .shadow(color: filled ? color.opacity(0.35) : .clear, radius: 14, y: 8)
            }
            .buttonStyle(.row)
            .accessibilityLabel(label)
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.text2)
        }
    }
}

private struct ReviewCard: View {
    @Environment(AppModel.self) private var app
    let tx: Transaction
    let onPick: (UUID) -> Void

    var body: some View {
        let ledger = app.ledger
        let cat = ledger.category(tx.categoryId)
        let pocket = ledger.pocket(cat?.pocketId)
        let color = Color(hexString: pocket?.color ?? "#8B8B96")
        let siblings = app.spendingCategories.filter { $0.pocketId == cat?.pocketId && $0.id != cat?.id }.prefix(3)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                IconTile(systemName: cat?.icon ?? "questionmark", color: color, size: 56, radius: 20)
                Spacer()
                Text(tx.date.short).font(.system(size: 13)).foregroundStyle(Palette.text2)
            }
            VStack(alignment: .leading, spacing: 4) {
                AmountText(amount: tx.amount, currency: tx.currency, font: .system(size: 40, weight: .heavy), cents: true, hideable: false)
                Text(tx.title).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                Text("\(app.accounts.first { $0.id == tx.accountId }?.displayName ?? "") · \(tx.paymentMethod.label)").font(.system(size: 14)).foregroundStyle(Palette.text2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("review.suggested")).font(.system(size: 12, weight: .bold)).textCase(.uppercase).foregroundStyle(Palette.text2)
                HStack {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(cat?.name ?? tr("tx.uncategorized")).font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text(pocket?.name ?? "").font(.system(size: 13)).foregroundStyle(Palette.text2)
                }
            }
            .card(padding: 14, radius: 18, fill: Palette.text.opacity(0.05))
            if !siblings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("review.orPick")).font(.system(size: 13)).foregroundStyle(Palette.text2)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(siblings)) { c in
                                Button(c.name) { onPick(c.id) }
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .overlay(Capsule().stroke(Palette.text.opacity(0.14)))
                            }
                        }
                        .padding(1)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: 470)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 20)
    }
}
