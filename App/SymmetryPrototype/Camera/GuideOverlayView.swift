import SwiftUI
import SymmetryCore
import UIKit

/// Alignment guides drawn over the viewfinder: the patient midline (the one Drape axis), a
/// level line that rotates with the phone's roll, the current angle's guidance, and an
/// optional ghost of the matching prior capture. The level readout is words only; no degree
/// value is shown.
///
/// The viewfinder is always on the fixed dark Plate, so every colour here is a fixed
/// on-Plate token that reads the same in light and dark appearance.
struct GuideOverlayView: View {
    let angle: ViewAngle
    let rollDegrees: Double?
    let maxTiltDegrees: Double
    let ghost: UIImage?

    private var isLevel: Bool {
        guard let roll = rollDegrees else { return false }
        return abs(roll) <= maxTiltDegrees
    }

    /// Scrim behind the readouts so they do not depend on what the camera sees.
    private let scrim = Theme.Colors.plate.opacity(0.8)
    private var scrimShape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.cornerRadius) }

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

                // Patient midline guide: the 2pt Drape axis at exactly half the width.
                Rectangle()
                    .fill(Theme.Colors.drapeOnPlate)
                    .frame(width: 2, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Level line: a fixed reference plus a line that follows the phone's roll.
                Rectangle()
                    .fill(Theme.Colors.guideMuted)
                    .frame(width: geo.size.width * 0.6, height: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if let roll = rollDegrees {
                    Rectangle()
                        .fill(isLevel ? Theme.Colors.drapeOnPlate : Theme.Colors.cautionOnPlate)
                        .frame(width: geo.size.width * 0.6, height: 2)
                        .rotationEffect(.degrees(-roll))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                VStack {
                    Text(angle.guidanceText)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.plateInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(scrim, in: scrimShape)
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
        return isLevel ? "Level, press the shutter" : "Tilt the phone until the line turns blue"
    }

    private var readoutSymbol: String {
        guard rollDegrees != nil else { return "info.circle" }
        return isLevel ? "checkmark" : "exclamationmark.triangle"
    }

    private var readoutColor: Color {
        guard rollDegrees != nil else { return Theme.Colors.plateInk }
        return isLevel ? Theme.Colors.drapeOnPlate : Theme.Colors.cautionOnPlate
    }

    private var levelReadout: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: readoutSymbol)
                .accessibilityHidden(true)
            Text(readoutText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(readoutColor)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(scrim, in: scrimShape)
        .accessibilityElement(children: .combine)
    }
}
