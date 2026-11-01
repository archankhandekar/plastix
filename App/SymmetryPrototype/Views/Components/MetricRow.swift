import SwiftUI
import SymmetryCore

/// One metric with value ± uncertainty. "Not measured" when nil. Never colours a value
/// as good or bad, and never shrinks text: a long name wraps instead. Flat, separated from
/// its neighbours by space alone.
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
                    nameText.fixedSize(horizontal: false, vertical: true)
                    ReadoutText(MetricFormatter.text(measurement),
                                color: measurement == nil ? Theme.Colors.graduation : Theme.Colors.ink,
                                alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if let explanation {
                Text(explanation)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if measurement == nil, let reason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.support)
                    .foregroundStyle(Theme.Colors.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var nameText: some View {
        Text(name)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Colors.ink)
    }

    private var valueText: some View {
        Text(MetricFormatter.text(measurement))
            .font(.readoutRow)
            .foregroundStyle(measurement == nil ? Theme.Colors.graduation : Theme.Colors.ink)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let explanation {
                Text(explanation)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            line(columnTitles.0, delta.baseline, emphasised: false)
            line(columnTitles.1, delta.current, emphasised: false)
            line(columnTitles.2, delta.delta, emphasised: true)
            if let change = delta.delta, abs(change.value) <= change.uncertainty {
                Text(MetricGlossary.withinUncertaintyLine)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if delta.delta == nil, let reason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.support)
                    .foregroundStyle(Theme.Colors.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    /// Title and readout on one line when both fit; otherwise the title above and the
    /// readout on its own line. The readout is never broken between a value and its ±.
    private func line(_ title: String, _ m: MetricValue?, emphasised: Bool) -> some View {
        ReadoutLine(title: title,
                    readout: MetricFormatter.text(m),
                    font: emphasised ? .readoutRow.weight(.semibold) : .readoutRow,
                    color: m == nil ? Theme.Colors.graduation : Theme.Colors.ink)
            .opacity(dimmed ? 0.6 : 1)
    }
}

/// A MetricFormatter string shown verbatim and kept whole. On one line when it fits;
/// when even the readout alone is wider than the screen (the largest text sizes), it breaks
/// only before the ±, so the ± always leads its uncertainty and never dangles.
/// Layout only: the string itself is never changed.
struct ReadoutText: View {
    let text: String
    var font: Font = .readoutRow
    var color: Color = Theme.Colors.ink
    var alignment: TextAlignment = .leading

    init(_ text: String, font: Font = .readoutRow, color: Color = Theme.Colors.ink, alignment: TextAlignment = .leading) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
    }

    private static let separator = " \u{00B1} "

    private var stackAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            styled(Text(text)).fixedSize()
            if let range = text.range(of: Self.separator) {
                VStack(alignment: stackAlignment, spacing: 0) {
                    styled(Text(text[..<range.lowerBound]))
                    // "± 0.021 L": the ± opens the second line with its uncertainty.
                    styled(Text(text[range.lowerBound...].dropFirst()))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            styled(Text(text)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func styled(_ t: Text) -> some View {
        t.font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment)
    }
}

/// A support-styled title and a readout. Side by side when both fit on one line (readout
/// trailing); otherwise the title on its own line and the readout below it, whole.
struct ReadoutLine: View {
    let title: String
    let readout: String
    var font: Font = .readoutRow
    var color: Color = Theme.Colors.ink

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                titleText.fixedSize()
                Spacer(minLength: 0)
                ReadoutText(readout, font: font, color: color).fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText.fixedSize(horizontal: false, vertical: true)
                ReadoutText(readout, font: font, color: color, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
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
