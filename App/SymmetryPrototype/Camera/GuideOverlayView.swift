import SwiftUI
import SymmetryCore
import UIKit

/// Alignment guides drawn over the live preview: the patient midline, a level line that
/// rotates with the phone's roll, the current angle's guidance, and an optional ghost of
/// the matching prior capture. The level readout is words only; no degree value is shown.
struct GuideOverlayView: View {
    let angle: ViewAngle
    let rollDegrees: Double?
    let maxTiltDegrees: Double
    let ghost: UIImage?

    private var isLevel: Bool {
        guard let roll = rollDegrees else { return false }
        return abs(roll) <= maxTiltDegrees
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let ghost {
                    Image(uiImage: ghost)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.35)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityHidden(true)
                }

                // Patient midline guide.
                Rectangle()
                    .fill(angle == .frontal ? Theme.Colors.guide : Theme.Colors.guideMuted)
                    .frame(width: 1.5, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Level line: fixed reference plus a line that follows the phone's roll.
                Rectangle()
                    .fill(Theme.Colors.guideMuted)
                    .frame(width: geo.size.width * 0.6, height: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if let roll = rollDegrees {
                    Rectangle()
                        .fill(isLevel ? Theme.Colors.guide : Theme.Colors.caution)
                        .frame(width: geo.size.width * 0.6, height: 2)
                        .rotationEffect(.degrees(-roll))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                VStack {
                    Text(angle.guidanceText)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .padding(.top, Theme.Spacing.m)
                    Spacer()
                    levelReadout
                        .padding(.bottom, Theme.Spacing.m)
                }
                .padding(.horizontal, Theme.Spacing.m)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Level readout

    private var readoutText: String {
        guard rollDegrees != nil else { return "Phone is pointing down, tilt is not checked" }
        return isLevel ? "Level, press the shutter" : "Tilt the phone until the line turns teal"
    }

    private var readoutSymbol: String {
        guard rollDegrees != nil else { return "arrow.down.circle" }
        return isLevel ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var readoutColor: Color {
        guard rollDegrees != nil else { return .white }
        return isLevel ? Theme.Colors.guide : Theme.Colors.caution
    }

    private var levelReadout: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: readoutSymbol)
            Text(readoutText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(readoutColor)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.black.opacity(0.55), in: Capsule())
    }
}
