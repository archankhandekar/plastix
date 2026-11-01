import SwiftUI

/// The one axis: a vertical Drape rule meaning "patient midline" or "zero difference", and
/// nothing else. It fills the height it is given.
struct AxisRule: View {
    private let color: Color
    private let lineWidth: CGFloat

    init(color: Color = Theme.Colors.drape, lineWidth: CGFloat = 2) {
        self.color = color
        self.lineWidth = lineWidth
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: lineWidth)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// Two columns that face the patient, like a frontal photo: patient right in the
/// screen-left half, patient left in the screen-right half, with the axis exactly at 50
/// percent of the width.
struct FacingColumns<Right: View, Left: View>: View {
    private let showsAxis: Bool
    private let spacing: CGFloat
    private let patientRight: Right
    private let patientLeft: Left

    init(showsAxis: Bool = true,
         spacing: CGFloat = 12,
         @ViewBuilder patientRight: () -> Right,
         @ViewBuilder patientLeft: () -> Left) {
        self.showsAxis = showsAxis
        self.spacing = spacing
        self.patientRight = patientRight()
        self.patientLeft = patientLeft()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            patientRight
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.trailing, spacing)
            patientLeft
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.leading, spacing)
        }
        // The two halves are equal, so an overlay centred on the stack sits exactly at 50 percent.
        .overlay {
            if showsAxis {
                AxisRule()
            }
        }
    }
}

/// "Patient right" at the screen-left end and "Patient left" at the screen-right end.
struct SideLabels: View {
    private let onPlate: Bool

    init(onPlate: Bool = false) {
        self.onPlate = onPlate
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text("Patient right")
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Patient left")
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.sideLabel)
        .foregroundStyle(onPlate ? Theme.Colors.plateInk : Theme.Colors.ink)
    }
}
