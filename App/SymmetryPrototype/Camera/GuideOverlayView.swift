import SwiftUI
import SymmetryCore
import UIKit

/// Alignment guides drawn over the viewfinder: the patient midline (the one Drape axis), a
/// level line that rotates with the phone's roll, the level readout at the bottom edge, and
/// an optional ghost of the matching prior capture. The level readout is words only; no
/// degree value is shown.
///
/// The angle's guidance sentence lives in the capture chrome above the viewfinder, not here,
/// so the top of the frame (neck and sternal notch, the landmark it asks you to align) is
/// never covered.
///
/// The viewfinder is always on the fixed dark Plate, so every colour here is a fixed
/// on-Plate token that reads the same in light and dark appearance.
struct GuideOverlayView: View {
    let angle: ViewAngle
    let rollDegrees: Double?
    let maxTiltDegrees: Double
    let ghost: UIImage?

    /// Below this roll the readout says level; up to the limit it says the tilt is inside it.
    static let levelDegrees: Double = 1

    /// Inside the tilt limit from Settings.
    private var isWithinLimit: Bool {
        guard let roll = rollDegrees else { return false }
        return abs(roll) <= maxTiltDegrees
    }

    /// Really level, not only inside the limit.
    private var isLevel: Bool {
        guard let roll = rollDegrees else { return false }
        return abs(roll) <= min(Self.levelDegrees, maxTiltDegrees)
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
                        .fill(isWithinLimit ? Theme.Colors.drapeOnPlate : Theme.Colors.cautionOnPlate)
                        .frame(width: geo.size.width * 0.6, height: 2)
                        .rotationEffect(.degrees(-roll))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                VStack {
                    Spacer()
                    levelReadout
                        .padding(.bottom, Theme.Spacing.s)
                }
                .padding(.horizontal, Theme.Spacing.s)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Level readout

    private var readoutText: String {
        guard rollDegrees != nil else { return "Phone is pointing down, tilt is not checked" }
        if isLevel { return "Level, press the shutter" }
        return isWithinLimit ? "Slight tilt, inside the limit" : "Tilt the phone until the line turns blue"
    }

    private var readoutSymbol: String {
        guard rollDegrees != nil else { return "info.circle" }
        if isLevel { return "checkmark" }
        return isWithinLimit ? "info.circle" : "exclamationmark.triangle"
    }

    private var readoutColor: Color {
        guard rollDegrees != nil else { return Theme.Colors.plateInk }
        return isWithinLimit ? Theme.Colors.drapeOnPlate : Theme.Colors.cautionOnPlate
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
        // The readout is a short status line; past xxLarge it would cover the lower torso.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }
}
