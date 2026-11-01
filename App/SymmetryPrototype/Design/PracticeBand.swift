import SwiftUI

/// 45-degree engineering hatch. Used only to mark practice data and, on the plate, the
/// areas where only one outline reaches. Stroke it and clip it to the area it marks.
struct HatchPattern: Shape {
    var spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(1, spacing)
        // Lines of constant x + y, rising to the right at 45 degrees, covering the whole rect.
        var c: CGFloat = 0
        let limit = rect.width + rect.height
        while c <= limit {
            path.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + c - rect.height, y: rect.maxY))
            c += step
        }
        return path
    }
}

/// The practice marker: one compact line, left-aligned, led by a small hatched swatch and
/// closed by a 4pt hatched rule. Practice data always carries it, and nothing else uses the
/// hatch. It is pinned, so its type is capped and it never wraps: at every text size it
/// stays a single line of about 40pt (under 6 percent of the screen). VoiceOver reads the
/// full sentence, and the large content viewer shows it at accessibility sizes.
struct PracticeBand: View {
    enum Style { case tray, plate }

    /// Shown text. The nav title already says "Virtual patient", so the band only says what
    /// the data is.
    static let defaultText = "Practice. Not study data."
    static let photoText = "Practice photo."
    /// Spoken in place of the short default text.
    static let spokenText = "Practice with the virtual patient. Nothing here is study data."

    /// Pinned chrome stops growing here; the scrolling content below keeps scaling.
    static let maxTypeSize = DynamicTypeSize.xxLarge

    private let text: String
    private let style: Style

    init(_ text: String = PracticeBand.defaultText, style: Style = .tray) {
        self.text = text
        self.style = style
    }

    private var background: Color { style == .plate ? Theme.Colors.plate : Theme.Colors.tray }
    private var hatchColor: Color {
        style == .plate ? Theme.Colors.plateGraduation : Theme.Colors.graduation
    }
    private var textColor: Color { style == .plate ? Theme.Colors.plateInk : Theme.Colors.ink }
    private var spoken: String { text == Self.defaultText ? Self.spokenText : text }

    private static let ruleHeight: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            HatchSwatch(color: hatchColor)
                .frame(width: 20)
                .frame(maxHeight: .infinity)
            Text(text)
                .font(.support.weight(.semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.margin)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s + Self.ruleHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .bottom) {
            HatchPattern(spacing: 5)
                .stroke(hatchColor.opacity(0.7), lineWidth: 1)
                .frame(height: Self.ruleHeight)
                .clipped()
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...Self.maxTypeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityShowsLargeContentViewer {
            Text(spoken)
        }
    }
}

/// A small hatched block: the practice glyph, at the head of the band and in the tag.
private struct HatchSwatch: View {
    let color: Color

    var body: some View {
        HatchPattern(spacing: 4)
            .stroke(color, lineWidth: 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A small corner tag for practice photos: a hatched swatch and "Practice" on a Plate scrim.
/// Use it on a photo when the screen already pins the band, which stays the one full-width
/// practice marker per screen.
struct PracticeTag: View {
    var text: String = "Practice"

    var body: some View {
        HStack(spacing: 6) {
            HatchSwatch(color: Theme.Colors.plateGraduation)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.support.weight(.semibold))
                .foregroundStyle(Theme.Colors.plateInk)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.plate.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.photoRadius))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practice photo of the virtual patient")
    }
}

extension View {
    /// Pins the practice band to the top of the screen when `isPractice` is true.
    func practiceBand(_ isPractice: Bool,
                      style: PracticeBand.Style = .tray,
                      text: String = PracticeBand.defaultText) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if isPractice {
                PracticeBand(text, style: style)
            }
        }
    }
}
