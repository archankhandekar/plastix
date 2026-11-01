import SwiftUI

/// The accessibility-size key under the plate. At accessibility text sizes the on-plate text
/// (side labels, ruler labels, bracket labels) is hidden, and these numbered lines repeat it
/// at full size. Readouts are verbatim MetricFormatter strings.
struct PlateKeyList: View {
    private let reading: SetReading

    init(reading: SetReading) {
        self.reading = reading
    }

    /// Patient right first, as it sits on the screen-left side of the plate.
    var lines: [String] {
        [
            "Patient right nipple to midline: " + reading.rightToMidlineReadout,
            "Patient left nipple to midline: " + reading.leftToMidlineReadout,
            "The ruler runs from 0 at the notch to 1 L at the midline bottom.",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("\(item.offset + 1).")
                        .font(.readoutRow)
                        .foregroundStyle(Theme.Colors.graduation)
                        .accessibilityHidden(true)
                    Text(item.element)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
