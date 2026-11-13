import SwiftUI
import UIKit

/// Design tokens from the akwe canvas (Foundations › tokens + row 7 light mode).
enum Palette {
    static let ground = Color(light: 0xF4F4F7, dark: 0x09090D)
    static let sheet = Color(light: 0xFFFFFF, dark: 0x101016)
    static let card = Color(light: 0xFFFFFF, dark: 0x15151C)
    static let raised = Color(light: 0xE9E9EF, dark: 0x1E1E27)
    static let text = Color(light: 0x111118, dark: 0xF5F5F7)
    static let text2 = Color(light: 0x5E5E6B, dark: 0xA1A1AA)
    static let text3 = Color(light: 0x6B6B78, dark: 0x8B8B96)
    static let stroke = Color(light: 0x111118, dark: 0xFFFFFF).opacity(0.08)
    /// Inverted surface for the active tab pill and primary buttons.
    static let inverse = Color(light: 0x111118, dark: 0xF5F5F7)
    static let onInverse = Color(light: 0xF4F4F7, dark: 0x09090D)

    static let iris = Color(light: 0x5B47E0, dark: 0xA99FFF)
    static let positive = Color(light: 0x0B8A5A, dark: 0x3DDC97)
    static let warning = Color(light: 0xA85F00, dark: 0xFFB86B)
    static let over = Color(light: 0xC7471A, dark: 0xFF8A5B)
    static let partner = Color(hex: 0xFF7EB6)
    static let aurora = Color(hex: 0x4B36FF)
    static let auroraTeal = Color(hex: 0x12B5A6)
    static let brandIndigo = Color(hex: 0x6A4BFF)
    static let brandDeep = Color(hex: 0x2A1FA8)
    static let mint = Color(hex: 0x3DDC97)
}

enum Radius {
    static let card: CGFloat = 22
    static let tile: CGFloat = 18
    static let icon: CGFloat = 14
    static let pill: CGFloat = 999
}

enum Motion {
    /// Taps, toggles.
    static let snappy = Animation.snappy(duration: 0.3)
    /// Layout changes.
    static let smooth = Animation.smooth(duration: 0.45)
    /// Success moments.
    static let bouncy = Animation.bouncy(duration: 0.5, extraBounce: 0.1)
    static let numbers = Animation.spring(duration: 0.45, bounce: 0.15)
    static let draw = Animation.smooth(duration: 1.0)

    static func stagger(_ i: Int, step: Double = 0.04) -> Animation { smooth.delay(Double(i) * step) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    /// "#FF9F5A" → Color. Pocket colors come from the database as hex strings.
    init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(s, radix: 16) ?? 0x8B8B96)
    }

    /// Pocket colors are tuned for dark mode; in light mode text uses a darker shade for contrast.
    static func pocket(_ hex: String) -> Color { Color(hexString: hex) }
}

enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
