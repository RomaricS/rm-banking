import SwiftUI
import AkweKit

// Visual language for "counts in your total" vs "left out" (accounts).
// Counted: full colour, solid card, mint check.  Left out: "ghost" card — dashed outline,
// no fill, greyed badge and amount, eye-slash. The difference reads at a glance, not just
// from a small badge.

/// Compact on/off pill used on account rows (count in total, show/hide).
/// On: tinted fill. Off: dashed outline, so the two states differ in shape, not only colour.
struct StatusToggle: View {
    let isOn: Bool
    let onIcon: String, offIcon: String
    let onText: String, offText: String
    let onColor: Color
    let a11yLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? onIcon : offIcon)
                    .font(.system(size: 12, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(isOn ? onText : offText).font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(isOn ? onColor : Palette.text2)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background {
                if isOn {
                    Capsule().fill(onColor.opacity(0.14))
                } else {
                    Capsule().strokeBorder(Palette.text3.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
            }
            .frame(minHeight: 44) // touch target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(isOn ? onText : offText)
        .accessibilityAddTraits(.isToggle)
    }
}

/// "In total" / "Not counted".
struct InTotalToggle: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        StatusToggle(isOn: isOn, onIcon: "checkmark.circle.fill", offIcon: "minus.circle",
                     onText: tr("totals.counted"), offText: tr("totals.leftOut"), onColor: Palette.positive,
                     a11yLabel: tr("accounts.includeInTotals"), action: action)
    }
}

/// "Shown" / "Hidden".
struct VisibilityToggle: View {
    let isShown: Bool
    let action: () -> Void
    var body: some View {
        StatusToggle(isOn: isShown, onIcon: "eye", offIcon: "eye.slash",
                     onText: tr("vis.shown"), offText: tr("vis.hidden"), onColor: Palette.iris,
                     a11yLabel: tr("accounts.showOnHome"), action: action)
    }
}

extension View {
    /// Ghost treatment for something left out of totals: dashed outline instead of a fill,
    /// desaturated content. `fill` is the normal background when counted.
    func countedStyle(_ counted: Bool, fill: Color, radius: CGFloat) -> some View {
        self
            .leftOutContent(!counted)
            .countedBackground(counted, fill: fill, radius: radius)
    }

    /// Greys out content that doesn't count (colour drained, softened).
    func leftOutContent(_ leftOut: Bool) -> some View {
        self.saturation(leftOut ? 0 : 1).opacity(leftOut ? 0.62 : 1)
            .animation(Motion.snappy, value: leftOut)
    }

    /// Solid fill when counted, dashed outline when left out.
    func countedBackground(_ counted: Bool, fill: Color, radius: CGFloat) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if counted {
                shape.fill(fill)
            } else {
                shape.strokeBorder(Palette.text3.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
        }
        .animation(Motion.snappy, value: counted)
    }
}

/// "What's in your total": one bar, a coloured segment per counted account (assets), and a
/// hatched grey segment for everything left out, with a legend underneath.
struct TotalCompositionCard: View {
    @Environment(AppModel.self) private var app

    private struct Slice: Identifiable { let id: UUID; let name: String; let value: Decimal; let color: Color }

    var body: some View {
        let ledger = app.ledger
        let value: (Account) -> Decimal = { ledger.rates.convert($0.currentBalance ?? 0, from: $0.currency, to: ledger.currency) }
        let counted = app.accounts.filter(\.includeInTotals).sorted { $0.sort < $1.sort }
        let leftOut = app.accounts.filter { !$0.includeInTotals }
        let slices = counted.compactMap { a -> Slice? in
            let v = value(a); return v > 0 ? Slice(id: a.id, name: a.displayName, value: v, color: app.accountColor(a)) : nil
        }
        let leftOutValue = leftOut.reduce(Decimal(0)) { $0 + max(0, value($1)) }
        let whole = slices.reduce(Decimal(0)) { $0 + $1.value } + leftOutValue

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("totals.title")).font(.system(size: 15, weight: .bold))
                Spacer()
                AmountText(amount: ledger.totalBalance, currency: app.currency, font: .system(size: 17, weight: .heavy), cents: false)
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(slices) { s in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(s.color)
                            .frame(width: width(s.value, of: whole, in: geo.size.width, gaps: slices.count + (leftOutValue > 0 ? 1 : 0)))
                    }
                    if leftOutValue > 0 {
                        Hatch().clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.text3.opacity(0.5), lineWidth: 1))
                            .frame(width: width(leftOutValue, of: whole, in: geo.size.width, gaps: slices.count + 1))
                    }
                }
            }
            .frame(height: 14)
            .animation(Motion.smooth, value: counted.map(\.id))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
                    Text(tr("totals.countedSummary", counted.count)).foregroundStyle(Palette.text)
                }
                if !leftOut.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle").foregroundStyle(Palette.text3)
                        Text(tr("totals.leftOutSummary", leftOut.count, money(leftOutValue, app.currency, cents: false)))
                            .foregroundStyle(Palette.text2)
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .accessibilityElement(children: .combine)
        }
        .card(padding: 14)
    }

    private func width(_ v: Decimal, of whole: Decimal, in total: CGFloat, gaps: Int) -> CGFloat {
        guard whole > 0 else { return 0 }
        let usable = max(0, total - CGFloat(max(0, gaps - 1)) * 3)
        return max(6, usable * CGFloat((v / whole).doubleValue))
    }

    /// Diagonal stripes: the bar's "left out" segment.
    private struct Hatch: View {
        var body: some View {
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 6
                }
                ctx.stroke(p, with: .color(Palette.text3.opacity(0.55)), lineWidth: 1.5)
            }
            .background(Palette.text.opacity(0.04))
        }
    }
}
