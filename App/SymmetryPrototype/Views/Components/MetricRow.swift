import SwiftUI
import SymmetryCore

/// One metric with value ± uncertainty. "Not measured" when nil. Never colours a value
/// as good or bad.
struct MetricRow: View {
    let name: String
    let measurement: MetricValue?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
            Spacer()
            Text(MetricFormatter.text(measurement))
                .font(.metric)
                .foregroundStyle(measurement == nil ? Theme.Colors.slate : Theme.Colors.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One metric across two capture sets with the change between them.
struct MetricDeltaRow: View {
    let delta: MetricDelta

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(delta.name)
            HStack(spacing: Theme.Spacing.m) {
                column("Baseline", delta.baseline)
                column("Current", delta.current)
                column("Change", delta.delta)
            }
            .font(.metricSmall)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func column(_ title: String, _ m: MetricValue?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Theme.Colors.slate)
            Text(MetricFormatter.text(m)).foregroundStyle(m == nil ? Theme.Colors.slate : Theme.Colors.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MetricFormatter {
    static func text(_ m: MetricValue?) -> String {
        guard let m else { return "Not measured" }
        switch m.unit {
        case .ratioOfReference: return String(format: "%+.3f ± %.3f L", m.value, m.uncertainty)
        case .pixels: return String(format: "%.0f ± %.0f px", m.value, m.uncertainty)
        case .dice: return String(format: "%.2f ± %.2f", m.value, m.uncertainty)
        case .degrees: return String(format: "%.1f ± %.1f°", m.value, m.uncertainty)
        }
    }
}
