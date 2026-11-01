import SwiftUI
import SymmetryCore

/// One metric across photo sets, on the same centre-zero grammar as the lean gauges: sets
/// run top to bottom, zero is the plot centre (a 2pt Drape rule), each value is a diamond
/// with its ± as an Ink bar. Overlap uses 0 to 1 with a dashed rule at 1. Rows without a
/// measurement are left out of the marks; callers list them with their reason below.
///
/// Each row's name sits in its own band above the row's strip, never on the plot itself:
/// at the default sizes it is held to the patient-right half so the zero rule never runs
/// through it, and at accessibility sizes (where a name may need the full width) the zero
/// rule is drawn only through the strips. The layout is plain SwiftUI so that the names can
/// wrap and the rows grow with Dynamic Type; the x mapping is linear over `domain(for:)`.
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// Axis tick text: bare numbers with a true minus sign. The unit is stated once by the
    /// screen, so no "L" sits beside the "Left" end label.
    static func axisLabel(_ v: Double, overlap: Bool) -> String {
        if abs(v) < 1e-9 { return "0" }
        if overlap { return abs(v - 1) < 1e-9 ? "1" : "0.5" }
        return String(format: "%+.2f", v).replacingOccurrences(of: "-", with: "\u{2212}")
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

    private var stripHeight: CGFloat { compact ? 22 : 28 }
    private var rowSpacing: CGFloat { compact ? 6 : Theme.Spacing.s }

    /// Names take the full width when the reference rule is not at the centre (overlap) or
    /// when the text is so large that half the width would break words.
    private var namesUseFullWidth: Bool {
        isOverlap || dynamicTypeSize.isAccessibilitySize
    }

    /// The zero rule runs unbroken from the first row to the last only when no name can
    /// reach it.
    private var continuousRule: Bool {
        !isOverlap && (compact || !dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            endLabels
            VStack(alignment: .leading, spacing: 0) {
                plotRows
                if !compact {
                    axis
                }
            }
        }
    }

    @ViewBuilder
    private var endLabels: some View {
        let ends: (String, String) = {
            switch kind {
            case let .difference(patientRightEnd, patientLeftEnd):
                return (patientRightEnd, patientLeftEnd)
            case .overlap:
                return ("0, no overlap", "1, outlines coincide")
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

    // MARK: Rows

    private var plotRows: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(measuredRows) { row in
                if let m = row.measurement {
                    rowView(row, m)
                }
            }
        }
        .padding(.vertical, compact ? 0 : Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if continuousRule {
                GeometryReader { geo in
                    referenceRule(width: geo.size.width, height: geo.size.height)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func rowView(_ row: Row, _ m: MetricValue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !compact {
                rowName(row.label)
            }
            strip(m)
                .frame(height: stripHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(MetricFormatter.text(m))
    }

    @ViewBuilder
    private func rowName(_ label: String) -> some View {
        let name = Text(label)
            .font(.scaleTick)
            .foregroundStyle(Theme.Colors.graduation)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if namesUseFullWidth {
            name.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Two equal halves with a gap: the name ends 8pt short of the zero rule.
            HStack(spacing: Theme.Spacing.m) {
                name.frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
    }

    private func strip(_ m: MetricValue) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lowX = xPosition(m.value - abs(m.uncertainty), width: w)
            let highX = xPosition(m.value + abs(m.uncertainty), width: w)
            ZStack(alignment: .topLeading) {
                // Rule first, so the hollow diamond's tray fill sits over it.
                referenceRule(width: w, height: h)
                Rectangle()
                    .fill(Theme.Colors.ink)
                    .frame(width: max(highX - lowX, 1), height: 3)
                    .position(x: (lowX + highX) / 2, y: h / 2)
                ChartDiamond(filled: abs(m.value) > abs(m.uncertainty))
                    .position(x: xPosition(m.value, width: w), y: h / 2)
            }
        }
        .accessibilityHidden(true)
    }

    /// The 2pt Drape zero rule at the centre, or the dashed Graduation rule at 1 for overlap.
    @ViewBuilder
    private func referenceRule(width: CGFloat, height: CGFloat) -> some View {
        if isOverlap {
            Path { p in
                p.move(to: CGPoint(x: width - 1, y: 0))
                p.addLine(to: CGPoint(x: width - 1, y: height))
            }
            .stroke(Theme.Colors.graduation, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        } else {
            Rectangle()
                .fill(Theme.Colors.drape)
                .frame(width: 2, height: height)
                .position(x: xPosition(0, width: width), y: height / 2)
        }
    }

    // MARK: Axis

    /// Ticks with their labels centred under them. An invisible sample label sets the height.
    private var axis: some View {
        Text("0")
            .font(.scaleTick)
            .hidden()
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    ForEach(axisValues, id: \.self) { v in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Theme.Colors.graduation)
                                .frame(width: 1, height: 6)
                            Text(Self.axisLabel(v, overlap: isOverlap))
                                .font(.scaleTick)
                                .foregroundStyle(Theme.Colors.graduation)
                        }
                        .fixedSize()
                        .position(x: min(max(xPosition(v, width: w), 0.5), w - 0.5), y: geo.size.height / 2)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: Mapping

    private func xPosition(_ v: Double, width: CGFloat) -> CGFloat {
        let lo = xDomain.lowerBound, hi = xDomain.upperBound
        guard hi > lo, v.isFinite else { return width / 2 }
        let t = (min(hi, max(lo, v)) - lo) / (hi - lo)
        return CGFloat(t) * width
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
