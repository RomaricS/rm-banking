import SwiftUI
import AkweKit

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = Radius.card
    var fill: Color = Palette.card
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = Radius.card, fill: Color = Palette.card) -> some View {
        modifier(CardBackground(padding: padding, radius: radius, fill: fill))
    }

    /// Fade + rise on appear, staggered by index.
    func rise(_ index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear { withAnimation(Motion.stagger(index, step: 0.06)) { shown = true } }
    }
}

// MARK: - Money

/// Amount that rolls digit by digit when it changes, and blurs when balances are hidden.
struct AmountText: View {
    let amount: Decimal
    let currency: String
    var font: Font = .system(size: 17, weight: .semibold)
    var cents: Bool? = nil
    var signed: Bool = false
    var color: Color = Palette.text
    var hideable: Bool = true
    @Environment(AppModel.self) private var app

    var body: some View {
        Text(money(amount, currency, cents: cents, signed: signed))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: amount.doubleValue))
            .animation(Motion.numbers, value: amount)
            .blur(radius: hideable && app.hideBalances ? 9 : 0)
            .animation(Motion.smooth, value: app.hideBalances)
            .accessibilityLabel(hideable && app.hideBalances ? tr("a11y.hiddenAmount") : money(amount, currency, cents: cents, signed: signed))
    }
}

/// Big hero amount: "$12,480" + smaller ".32".
struct HeroAmount: View {
    let amount: Decimal
    let currency: String
    var size: CGFloat = 52
    @Environment(AppModel.self) private var app

    var body: some View {
        let full = money(amount, currency, cents: true)
        let parts = splitDecimal(full)
        (Text(parts.0).font(.system(size: size, weight: .bold)) + Text(parts.1).font(.system(size: size * 0.58, weight: .bold)).foregroundColor(Palette.text2))
            .tracking(-1.5)
            .monospacedDigit()
            .contentTransition(.numericText(value: amount.doubleValue))
            .animation(Motion.numbers, value: amount)
            .blur(radius: app.hideBalances ? 14 : 0)
            .animation(Motion.smooth, value: app.hideBalances)
            .accessibilityLabel(app.hideBalances ? tr("a11y.hiddenAmount") : full)
    }

    /// Splits "$12,480.32" → ("$12,480", ".32"), "12 480,32 €" → ("12 480", ",32 €").
    private func splitDecimal(_ s: String) -> (String, String) {
        let sep = Locale.current.decimalSeparator ?? "."
        guard let r = s.range(of: sep, options: .backwards) else { return (s, "") }
        return (String(s[..<r.lowerBound]), String(s[r.lowerBound...]))
    }
}

// MARK: - Icons

struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 40
    var radius: CGFloat = Radius.icon
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct BankBadge: View {
    let name: String
    let color: Color
    var size: CGFloat = 28
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .heavy))
            .foregroundStyle(Palette.onInverse)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.text2
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Progress

struct RingProgress: View {
    let fraction: Double
    var color: Color = Palette.iris
    var lineWidth: CGFloat = 12
    var track: Color = Palette.text.opacity(0.1)
    @State private var drawn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, drawn))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(reduceMotion ? nil : Motion.draw.delay(0.15)) { drawn = min(1, fraction) } }
        .onChange(of: fraction) { _, v in withAnimation(Motion.smooth) { drawn = min(1, v) } }
    }
}

/// Two-person ring for shared goals.
struct SplitRing: View {
    let first: Double
    let second: Double
    var firstColor: Color = Color(hex: 0x7C9CFF)
    var secondColor: Color = Palette.partner
    var lineWidth: CGFloat = 14
    @State private var p: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Palette.text.opacity(0.1), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, first * p))
                .stroke(firstColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().trim(from: min(first + 0.015, 1), to: min(1, first + 0.015 + second * p))
                .stroke(secondColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(Motion.draw.delay(0.2)) { p = 1 } }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var color: Color = Palette.text
    var height: CGFloat = 8
    var marker: Double? = nil
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.text.opacity(0.08))
                Capsule().fill(color).frame(width: geo.size.width * (shown ? min(1, max(0, fraction)) : 0))
                if let m = marker {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.positive)
                        .frame(width: 2, height: height + 8)
                        .offset(x: geo.size.width * min(1, m) - 1)
                }
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(Motion.smooth.delay(0.3)) { shown = true } }
    }
}

// MARK: - Controls

/// Segmented control with a sliding pill (matchedGeometryEffect).
struct PillSegments<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { o in
                Button {
                    Haptics.selection()
                    withAnimation(Motion.snappy) { selection = o }
                } label: {
                    Text(label(o))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == o ? Palette.onInverse : Palette.text2)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == o {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.inverse)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == o ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.inverse
    var foreground: Color = Palette.onInverse
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Palette.raised, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct CircleIconButton: View {
    let systemName: String
    let label: String
    var fill: Color = Palette.raised
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 40, height: 40)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.iris)
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.text3)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
            Text(message).font(.system(size: 14)).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Aurora

/// Slowly drifting gradient blobs behind hero sections.
struct AuroraBackground: View {
    var tint: Color = Palette.aurora
    var secondary: Color = Palette.auroraTeal
    var height: CGFloat = 470
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let strength = scheme == .dark ? 1.0 : 0.3
        ZStack {
            Circle().fill(RadialGradient(colors: [tint.opacity(0.95 * strength), .clear], center: .center, startRadius: 0, endRadius: 210))
                .frame(width: 420, height: 420)
                .offset(x: drift ? -60 : -110, y: drift ? -110 : -150)
            Circle().fill(RadialGradient(colors: [secondary.opacity(0.55 * strength), .clear], center: .center, startRadius: 0, endRadius: 180))
                .frame(width: 360, height: 360)
                .offset(x: drift ? 120 : 160, y: drift ? -10 : -40)
            LinearGradient(colors: [.clear, Palette.ground], startPoint: .center, endPoint: .bottom)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - Logo

/// The cowrie mark (canvas › App icon & logo, option A).
struct CowrieMark: View {
    var size: CGFloat = 60
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Palette.brandIndigo, Palette.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Ellipse().fill(Color(hex: 0xF5F5F7)).frame(width: size * 0.6, height: size * 0.71).offset(y: size * 0.005)
            Capsule().fill(Palette.brandDeep).frame(width: size * 0.065, height: size * 0.5).offset(x: -size * 0.01)
            Circle().fill(Palette.mint).frame(width: size * 0.14).offset(x: size * 0.22, y: -size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("akwe")
    }
}
