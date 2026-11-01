import SwiftUI
import SymmetryCore

/// One metric with value ± uncertainty. "Not measured" when nil. Never colours a value
/// as good or bad, and never shrinks text: a long name wraps instead.
struct MetricRow: View {
    let name: String
    let measurement: MetricValue?
    /// Plain-English meaning, shown beneath when non-nil.
    var explanation: String? = nil
    /// Why the row reads "Not measured"; shown only when `measurement == nil`.
    var reason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    nameText.fixedSize()
                    Spacer(minLength: 0)
                    valueText.fixedSize()
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    nameText
                    valueText.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if measurement == nil, let reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var nameText: some View {
        Text(name)
            .font(.body)
            .foregroundStyle(Theme.Colors.ink)
    }

    private var valueText: some View {
        Text(MetricFormatter.text(measurement))
            .font(.metricLarge)
            .foregroundStyle(measurement == nil ? Theme.Colors.slate : Theme.Colors.ink)
    }
}

/// One metric across two capture sets with the change between them, stacked so nothing
/// has to shrink.
struct MetricDeltaRow: View {
    let delta: MetricDelta
    var columnTitles: (String, String, String) = ("Baseline", "Current", "Change")
    var explanation: String? = nil
    var reason: String? = nil
    /// Fades only the three value texts (never the explanation or reason) when the
    /// comparison the values come from is not reliable.
    var dimmed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(delta.name)
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            line(columnTitles.0, delta.baseline, emphasised: false)
            line(columnTitles.1, delta.current, emphasised: false)
            line(columnTitles.2, delta.delta, emphasised: true)
            if let change = delta.delta, abs(change.value) <= change.uncertainty {
                Text(MetricGlossary.withinUncertaintyLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if delta.delta == nil, let reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ m: MetricValue?, emphasised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.slate)
            Spacer(minLength: 0)
            Text(MetricFormatter.text(m))
                .font(emphasised ? .metric.weight(.semibold) : .metric)
                .foregroundStyle(m == nil ? Theme.Colors.slate : Theme.Colors.ink)
                .opacity(dimmed ? 0.6 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
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
