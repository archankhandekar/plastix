import Charts
import SwiftUI
import SymmetryCore

/// One metric across photo sets, on the same centre-zero grammar as the lean gauges: sets
/// run top to bottom, zero is the plot centre (a 2pt Drape rule), each value is a diamond
/// with its ± as an Ink bar. Overlap uses 0 to 1 with a dashed rule at 1. Rows without a
/// measurement are left out of the marks; callers list them with their reason below.
struct StageLeanChart: View {
    struct Row: Identifiable, Hashable {
        let id: Int
        let label: String
        let measurement: MetricValue?

        init(id: Int, label: String, measurement: MetricValue?) {
            self.id = id
            self.label = label
            self.measurement = measurement
        }
    }

    enum Kind: Hashable {
        case difference(patientRightEnd: String, patientLeftEnd: String)
        case overlap
    }

    private let kind: Kind
    private let rows: [Row]
    private let compact: Bool

    init(kind: Kind, rows: [Row], compact: Bool = false) {
        self.kind = kind
        self.rows = rows
        self.compact = compact
    }

    /// Symmetric about zero and never narrower than the gauges' ±0.15 L, so zero is always
    /// the plot centre: D = max(0.15, 1.1 * max(|v| + u)).
    static func domain(for rows: [Row]) -> ClosedRange<Double> {
        let reach = rows.compactMap { $0.measurement }
            .map { abs($0.value) + abs($0.uncertainty) }
            .filter { $0.isFinite }
            .max() ?? 0
        let d = max(LeanGaugeMapping.range, 1.1 * reach)
        return -d...d
    }

    private var measuredRows: [Row] { rows.filter { $0.measurement != nil } }

    private var isOverlap: Bool {
        if case .overlap = kind { return true }
        return false
    }

    private var xDomain: ClosedRange<Double> {
        isOverlap ? 0...1 : Self.domain(for: rows)
    }

    private var axisValues: [Double] {
        isOverlap ? [0, 0.5, 1] : [-0.10, 0, 0.10]
    }

    private func axisLabel(_ v: Double) -> String {
        if abs(v) < 1e-9 { return "0" }
        if isOverlap { return v == 1 ? "1" : "0.5" }
        return String(format: "%+.2f L", v)
    }

    private var chartHeight: CGFloat {
        let count = CGFloat(max(1, measuredRows.count))
        return compact ? 32 * count : 56 * count + 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            endLabels
            chart
                .frame(height: chartHeight)
        }
    }

    @ViewBuilder
    private var endLabels: some View {
        let ends: (String, String) = {
            switch kind {
            case let .difference(patientRightEnd, patientLeftEnd):
                return (patientRightEnd, patientLeftEnd)
            case .overlap:
                // In the full chart the dashed rule at 1 carries its own label.
                return ("0, no overlap", compact ? "1, outlines coincide" : "")
            }
        }()
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(ends.0)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ends.1)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.support)
        .foregroundStyle(Theme.Colors.graduation)
        .accessibilityHidden(true)
    }

    private var chart: some View {
        Chart {
            if isOverlap {
                RuleMark(x: .value("Outlines coincide", 1.0))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Theme.Colors.graduation)
                    .annotation(position: .top, alignment: .trailing, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if !compact {
                            Text("1, outlines coincide")
                                .font(.scaleTick)
                                .foregroundStyle(Theme.Colors.graduation)
                        }
                    }
            } else {
                RuleMark(x: .value("Zero", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Theme.Colors.drape)
            }
            ForEach(measuredRows) { row in
                if let m = row.measurement {
                    let low = clampToDomain(m.value - abs(m.uncertainty))
                    let high = clampToDomain(m.value + abs(m.uncertainty))
                    RuleMark(xStart: .value("Low", low),
                             xEnd: .value("High", high),
                             y: .value("Set", row.label))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .foregroundStyle(Theme.Colors.ink)
                        .accessibilityHidden(true)
                    PointMark(x: .value("Value", clampToDomain(m.value)),
                              y: .value("Set", row.label))
                        .symbol {
                            ChartDiamond(filled: abs(m.value) > abs(m.uncertainty))
                        }
                        .annotation(position: .top, spacing: 2) {
                            if !compact {
                                Text(row.label)
                                    .font(.scaleTick)
                                    .foregroundStyle(Theme.Colors.graduation)
                            }
                        }
                        .accessibilityLabel(row.label)
                        .accessibilityValue(MetricFormatter.text(m))
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: measuredRows.map(\.label))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisTick(length: 6, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.Colors.graduation)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(axisLabel(v))
                            .font(.scaleTick)
                            .foregroundStyle(Theme.Colors.graduation)
                    }
                }
            }
        }
        .chartXAxis(compact ? .hidden : .visible)
        .chartLegend(.hidden)
    }

    private func clampToDomain(_ v: Double) -> Double {
        min(xDomain.upperBound, max(xDomain.lowerBound, v))
    }
}

/// The 16pt diamond used for chart points: filled Ink when the value is larger than its ±,
/// otherwise a 2pt Ink outline.
private struct ChartDiamond: View {
    let filled: Bool

    var body: some View {
        ZStack {
            if filled {
                DiamondShape().fill(Theme.Colors.ink)
            } else {
                DiamondShape().fill(Theme.Colors.tray)
                DiamondShape().stroke(Theme.Colors.ink, lineWidth: 2)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// A square diamond filling its rect.
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
