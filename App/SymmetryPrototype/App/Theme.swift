import SwiftUI

/// "Scrub Light" theme tokens. One accent, quiet neutrals, dark capture surfaces.
/// Colours adapt to light and dark appearance; the viewfinder is always dark.
enum Theme {
    enum Colors {
        static let ink = Color(light: 0x17201F, dark: 0xEEF2F1)
        static let paper = Color(light: 0xF6F7F5, dark: 0x101514)
        static let surface = Color(light: 0xFFFFFF, dark: 0x1A2120)
        static let slate = Color(light: 0x5C6B69, dark: 0x9FB0AD)
        static let hairline = Color(light: 0xD9DEDC, dark: 0x2B3534)
        static let accent = Color(light: 0x1E7F74, dark: 0x3FB3A6)
        static let caution = Color(light: 0xB8741A, dark: 0xE0A04A)
        static let unreliable = Color(light: 0x8A3B3B, dark: 0xD97B7B)
        static let capture = Color(hex: 0x0E1413)
        static let guide = Color(hex: 0x3FB3A6)
        static let guideMuted = Color.white.opacity(0.55)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    /// Minimum tap target for gloved use.
    static let tapTarget: CGFloat = 56
    static let cornerRadius: CGFloat = 10
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that resolves differently in light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

extension Font {
    /// Numbers with tabular digits so ± columns line up.
    static let metric = Font.system(.body, design: .default).monospacedDigit()
    static let metricSmall = Font.system(.caption, design: .default).monospacedDigit()
}

/// Rounded text field style shared by forms.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.tapTarget)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.Colors.hairline))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

/// The primary action: one per screen, always the accent.
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            .foregroundStyle(.white)
            .background(isDestructive ? Theme.Colors.unreliable : Theme.Colors.accent,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            .foregroundStyle(Theme.Colors.ink)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.Colors.hairline))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
