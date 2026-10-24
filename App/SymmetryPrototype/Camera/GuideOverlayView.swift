import SwiftUI
import SymmetryCore
import UIKit

/// Alignment guides drawn over the live preview: the patient midline, a level line that
/// rotates with the phone's roll, the current angle's guidance, and an optional ghost of
/// the matching prior capture.
struct GuideOverlayView: View {
    let angle: ViewAngle
    let rollDegrees: Double?
    let pitchDegrees: Double?
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
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
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

    private var levelReadout: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let roll = rollDegrees {
                Image(systemName: isLevel ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(isLevel ? "Level" : "Roll \(roll, specifier: "%.0f")°")
            } else {
                Image(systemName: "arrow.down.circle")
                Text("Pointing down. Roll not measurable.")
            }
            if let pitch = pitchDegrees {
                Text("Pitch \(pitch, specifier: "%.0f")°").foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(isLevel || rollDegrees == nil ? Theme.Colors.guide : Theme.Colors.caution)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.black.opacity(0.55), in: Capsule())
    }
}
