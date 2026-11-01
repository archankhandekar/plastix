import SwiftUI

/// The key directly under the symmetry plate. First the four left-right differences, each
/// a 56pt button with its title and verbatim MetricFormatter readout (with its ±); tapping
/// one brings its construction forward on the plate, tapping it again shows every layer.
/// Two columns when the readouts fit, one when they do not.
///
/// At accessibility text sizes the plate's own small labels are hard to read, so the key
/// then also repeats them at full size: each nipple's distance from the midline and what
/// the ruler marks. There are no numbered badges, so the key carries no numbers of its own.
struct PlateKeyList: View {
    private let reading: SetReading
    @Binding private var focus: PlateLayer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(reading: SetReading, focus: Binding<PlateLayer>) {
        self.reading = reading
        self._focus = focus
    }

    /// The plate's per-side text, patient right first as it sits on the screen-left side.
    var lines: [String] {
        [
            "Patient right nipple to midline: " + reading.rightToMidlineReadout,
            "Patient left nipple to midline: " + reading.leftToMidlineReadout,
            "The ruler runs from 0 at the notch to 1 L at the midline bottom.",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ViewThatFits(in: .horizontal) {
                Grid(horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.s) {
                    GridRow {
                        cell(.nippleHeight, singleLine: true)
                        cell(.nippleMidline, singleLine: true)
                    }
                    GridRow {
                        cell(.foldHeight, singleLine: true)
                        cell(.outlineOverlap, singleLine: true)
                    }
                }
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(BilateralMetric.allCases) { metric in
                        cell(metric, singleLine: false)
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ metric: BilateralMetric, singleLine: Bool) -> some View {
        let r = reading.reading(metric)
        let isSelected = focus == metric.layer
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        return Button {
            focus = isSelected ? .all : metric.layer
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.support.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(singleLine ? 1 : nil)
                    .fixedSize(horizontal: singleLine, vertical: true)
                Text(r.readout)
                    .font(.readoutRow)
                    .foregroundStyle(r.measurement == nil ? Theme.Colors.graduation : Theme.Colors.ink)
                    .lineLimit(singleLine ? 1 : nil)
                    .fixedSize(horizontal: singleLine, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.s + 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .background(isSelected ? Theme.Colors.fieldWash : Color.clear, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Theme.Colors.drape : Theme.Colors.graduation,
                                        lineWidth: isSelected ? 2 : 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(r.readout)")
        .accessibilityHint(isSelected ? "Shows every layer on the photo." : "Brings this difference forward on the photo.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("plateKey.\(metric)")
    }
}
