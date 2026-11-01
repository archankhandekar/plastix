import SwiftUI

/// "Plumb" design tokens: an intraoperative measuring instrument, used with gloves under
/// OR lights. One flat steel tray, one Drape axis, and a fixed dark Plate behind photos.
///
/// Provenance colour grammar: violet (marker) is what a hand placed, blue (drape) is what
/// the app derived, and everything else is quiet steel. Colour never judges a value.
enum Theme {
    enum Colors {
        // MARK: Adaptive (light / dark)

        /// All primary text and readouts.
        static let ink = Color(light: 0x162026, dark: 0xE3E8EB)
        /// Screen background: brushed stainless, one flat surface.
        static let tray = Color(light: 0xE7EAEC, dark: 0x0F1417)
        /// Secondary text, ticks, scale end labels, axis labels.
        static let graduation = Color(light: 0x56626A, dark: 0x95A2AA)
        /// Derived geometry off-plate, the primary button fill, selected outlines.
        static let drape = Color(light: 0x0A5C78, dark: 0x56B6D6)
        /// Primary button label.
        static let onDrape = Color(light: 0xFFFFFF, dark: 0x07090B)
        /// Drape mixed into Tray: selected segment, active band. The only raised tone off-plate.
        static let fieldWash = Color(light: 0xD2E3EA, dark: 0x14303B)
        /// Hand-placed things off-plate. Never chrome or buttons.
        static let marker = Color(light: 0x5A2A8C, dark: 0xB99BEA)
        /// Warnings and Not measured reasons. Always with a glyph and a sentence.
        static let caution = Color(light: 0x8A5200, dark: 0xE8A845)

        // MARK: Fixed (identical in both appearances)

        /// Lightbox behind every photo, the viewfinder and the plate.
        static let plate = Color(hex: 0x0C1013)
        static let plateInk = Color(hex: 0xE3E8EB)
        static let plateGraduation = Color(hex: 0x95A2AA)
        /// Hand-placed marks on Plate, always with a 2pt Plate-coloured halo.
        static let markerOnPlate = Color(hex: 0xC9A8FF)
        /// Axis, guides and the mirrored outline on Plate.
        static let drapeOnPlate = Color(hex: 0x56B6D6)
        static let cautionOnPlate = Color(hex: 0xE8A845)
        /// The white caliper: always "the difference itself".
        static let caliper = Color(hex: 0xFFFFFF)

        // MARK: Compatibility aliases (screens not yet restyled keep compiling)

        static let paper = tray
        static let surface = tray
        static let slate = graduation
        /// Placeholders only. Rows are separated by space, never by hairlines.
        static let hairline = Color(light: 0xC6CDD2, dark: 0x27313A)
        static let accent = drape
        static let unreliable = caution
        static let capture = plate
        static let guide = drapeOnPlate
        static let guideMuted = Color.white.opacity(0.55)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
        /// Screen margin.
        static let margin: CGFloat = 20
        /// Between gauge rows.
        static let gaugeGap: CGFloat = 24
        /// Between sections.
        static let section: CGFloat = 40
    }

    /// Minimum hit area for gloved use.
    static let tapTarget: CGFloat = 56
    /// Height of the one primary action per screen.
    static let primaryHeight: CGFloat = 64
    static let shutterSize: CGFloat = 80
    /// Buttons, fields and segments.
    static let cornerRadius: CGFloat = 8
    /// Photos and the plate (steel-tray corner).
    static let photoRadius: CGFloat = 4
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

extension Theme.Colors {
    /// Completed-step ticks.
    static let done = drape
    /// There are no cards: the old card surface is the tray itself.
    static let cardBackground = tray
}

/// Formerly a card. Plumb has no cards: this is a flat, full-width group with a little
/// vertical breathing room, no background and no stroke.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Outlined button for the dark camera screen (Stop, Match pose).
struct OutlinedCaptureButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.actionLabel)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.tapTarget)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Color.white, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// Outlined button for use on Plate (photos, the symmetry plate, the viewfinder).
struct PlateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.actionLabel)
            .foregroundStyle(Theme.Colors.plateInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minWidth: Theme.tapTarget, minHeight: Theme.tapTarget)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.Colors.plateInk, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }

    /// Full-width row with the minimum tap height, hit-testable across its whole area.
    func tapTarget() -> some View {
        frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// Text field style shared by forms: 56pt, 1.5pt Graduation outline, 8pt corners.
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: Theme.tapTarget)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.Colors.graduation, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

extension View {
    func fieldStyle() -> some View { modifier(FieldStyle()) }
}

/// The primary action: one per screen, full width, 64pt, Drape fill.
/// A destructive action is never red: it renders as the secondary outline with a trash glyph.
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isDestructive {
            SecondaryButtonStyle.body(configuration: configuration, isEnabled: isEnabled, leadingSymbol: "trash")
        } else {
            configuration.label
                .font(.actionLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(maxWidth: .infinity, minHeight: Theme.primaryHeight)
                .foregroundStyle(Theme.Colors.onDrape)
                .background(Theme.Colors.drape, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        }
    }
}

/// 56pt, 1.5pt Ink outline, clear fill, Ink label.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Self.body(configuration: configuration, isEnabled: isEnabled, leadingSymbol: nil)
    }

    @ViewBuilder
    fileprivate static func body(configuration: Configuration, isEnabled: Bool, leadingSymbol: String?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .accessibilityHidden(true)
            }
            configuration.label
        }
        .font(.actionLabel)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
        .foregroundStyle(Theme.Colors.ink)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .stroke(Theme.Colors.ink, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}
