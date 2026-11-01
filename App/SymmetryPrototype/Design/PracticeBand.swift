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

/// The practice marker: a 56pt hatched band with one sentence. Practice data always carries
/// it, and nothing else uses the hatch.
struct PracticeBand: View {
    enum Style { case tray, plate }

    static let defaultText = "Practice: virtual patient. Nothing here is study data."
    static let photoText = "Virtual patient. Practice photo."

    private let text: String
    private let style: Style

    init(_ text: String = PracticeBand.defaultText, style: Style = .tray) {
        self.text = text
        self.style = style
    }

    private var background: Color { style == .plate ? Theme.Colors.plate : Theme.Colors.tray }
    private var hatchColor: Color {
        style == .plate ? Theme.Colors.plateGraduation.opacity(0.35) : Theme.Colors.graduation.opacity(0.25)
    }
    private var textColor: Color { style == .plate ? Theme.Colors.plateInk : Theme.Colors.ink }

    var body: some View {
        // The text sets the height; the hatch fills whatever that is, never more.
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget)
            .background {
                ZStack {
                    background
                    HatchPattern(spacing: 6)
                        .stroke(hatchColor, lineWidth: 1)
                }
                .clipped()
            }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
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
