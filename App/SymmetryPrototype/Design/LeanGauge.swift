import SwiftUI
import SymmetryCore

/// Maps a signed left-right difference onto a centre-zero gauge track. Pure value type.
/// A fixed range of ±0.15 L, so gauges in different sets line up. Positive values lean
/// right on screen, toward patient left.
struct LeanGaugeMapping: Equatable {
    static let range = 0.15
    static let tickStep = 0.05

    let value: Double
    let uncertainty: Double

    init(value: Double, uncertainty: Double) {
        self.value = value
        self.uncertainty = uncertainty
    }

    init(_ m: MetricValue) {
        self.init(value: m.value, uncertainty: m.uncertainty)
    }

    /// True when the value is larger than its ±, so the needle is drawn filled.
    var isFilled: Bool { abs(value) > uncertainty }

    /// True when the value runs off the fixed scale; an outward notch replaces the needle.
    var isClamped: Bool { abs(value) > Self.range }

    /// 0 is the screen-left end, 0.5 the zero (the axis), 1 the screen-right end.
    func fraction(_ v: Double) -> Double {
        0.5 + max(-Self.range, min(Self.range, v)) / (2 * Self.range)
    }

    var needleFraction: Double { fraction(value) }

    /// The ± span, as track fractions.
    var bracket: ClosedRange<Double> {
        let a = fraction(value - abs(uncertainty))
        let b = fraction(value + abs(uncertainty))
        return min(a, b)...max(a, b)
    }

    /// A tick every 0.05 L from -0.15 L to +0.15 L: seven evenly spaced fractions.
    static var tickFractions: [Double] {
        let count = Int((2 * range / tickStep).rounded())
        return (0...count).map { Double($0) / Double(count) }
    }
}

/// Maps a 0 to 1 overlap value onto an unfilled line.
struct OverlapScaleMapping {
    static func fraction(_ v: Double) -> Double {
        max(0, min(1, v))
    }
}

// MARK: - Shared track

/// The drawn part of a gauge: baseline, ticks, an optional zero tick, the ± caliper and the
/// diamond needle (or an outward notch when the value is off the scale).
private struct GaugeTrack: View {
    let ticks: [Double]
    let zeroFraction: Double?
    let needle: Double
    let bracket: ClosedRange<Double>
    let filled: Bool
    /// -1 when off the screen-left end, +1 when off the screen-right end, 0 otherwise.
    let clampDirection: Int
    let height: CGFloat

    /// Room at each end so a needle or notch at the end stays inside the view.
    private let inset: CGFloat = 12

    var body: some View {
        Canvas { ctx, size in
            let ink = Theme.Colors.ink
            let graduation = Theme.Colors.graduation
            let midY = size.height / 2
            let usable = max(1, size.width - 2 * inset)
            func x(_ f: Double) -> CGFloat { inset + CGFloat(f) * usable }

            // Baseline.
            var base = Path()
            base.move(to: CGPoint(x: x(0), y: midY))
            base.addLine(to: CGPoint(x: x(1), y: midY))
            ctx.stroke(base, with: .color(graduation), lineWidth: 2)

            // Graduation ticks.
            var tickPath = Path()
            for t in ticks {
                tickPath.move(to: CGPoint(x: x(t), y: midY - 4))
                tickPath.addLine(to: CGPoint(x: x(t), y: midY + 4))
            }
            ctx.stroke(tickPath, with: .color(graduation), lineWidth: 1.5)

            // Zero: a 2pt Drape tick, 24pt tall, exactly at the centre.
            if let zeroFraction {
                var zero = Path()
                let zx = x(zeroFraction)
                zero.move(to: CGPoint(x: zx, y: midY - 12))
                zero.addLine(to: CGPoint(x: zx, y: midY + 12))
                ctx.stroke(zero, with: .color(Theme.Colors.drape), lineWidth: 2)
            }

            // The ± caliper.
            let x1 = x(bracket.lowerBound), x2 = x(bracket.upperBound)
            var caliper = Path()
            caliper.move(to: CGPoint(x: x1, y: midY))
            caliper.addLine(to: CGPoint(x: x2, y: midY))
            caliper.move(to: CGPoint(x: x1, y: midY - 5))
            caliper.addLine(to: CGPoint(x: x1, y: midY + 5))
            caliper.move(to: CGPoint(x: x2, y: midY - 5))
            caliper.addLine(to: CGPoint(x: x2, y: midY + 5))
            ctx.stroke(caliper, with: .color(ink), lineWidth: 2)

            if clampDirection != 0 {
                // Outward notch at the end the value ran off.
                let tipX = clampDirection > 0 ? size.width - 1 : 1
                let baseX = clampDirection > 0 ? tipX - 12 : tipX + 12
                var notch = Path()
                notch.move(to: CGPoint(x: tipX, y: midY))
                notch.addLine(to: CGPoint(x: baseX, y: midY - 8))
                notch.addLine(to: CGPoint(x: baseX, y: midY + 8))
                notch.closeSubpath()
                ctx.fill(notch, with: .color(ink))
            } else {
                let nx = x(needle)
                var diamond = Path()
                diamond.move(to: CGPoint(x: nx, y: midY - 8))
                diamond.addLine(to: CGPoint(x: nx + 8, y: midY))
                diamond.addLine(to: CGPoint(x: nx, y: midY + 8))
                diamond.addLine(to: CGPoint(x: nx - 8, y: midY))
                diamond.closeSubpath()
                if filled {
                    ctx.fill(diamond, with: .color(ink))
                } else {
                    ctx.stroke(diamond, with: .color(ink), lineWidth: 2)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// The Not measured replacement for a track: a caution glyph and the reason, plus an
/// optional "Mark points" button (placed by the caller outside any row button).
private struct NotMeasuredLine: View {
    let reason: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text(reason ?? MetricFormatter.text(nil))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .foregroundStyle(Theme.Colors.caution)
    }
}

/// The title line of a gauge row; a focused row gets a 4pt Drape leading bar.
private struct GaugeTitle: View {
    let title: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if isFocused {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.drape)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
            }
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EndLabels: View {
    let screenLeft: String
    let screenRight: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(screenLeft)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(screenRight)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.support)
        .foregroundStyle(Theme.Colors.graduation)
        .accessibilityHidden(true)
    }
}

private struct ExportLine: View {
    let exportName: String

    var body: some View {
        (Text("In the export: ") + Text(exportName))
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wraps a gauge row's content in a full-row button when `onSelect` is given, and keeps
/// the optional "Mark points" button outside it so the two never nest.
private struct GaugeRowShell<Content: View>: View {
    let accessibilityText: String
    let isFocused: Bool
    let showsMarkPoints: Bool
    let onSelect: (() -> Void)?
    let onMarkPoints: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let onSelect {
                Button(action: onSelect) {
                    content()
                        .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .fixedSize(horizontal: false, vertical: true)
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : [.isButton])
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
            }
            if showsMarkPoints, let onMarkPoints {
                Button("Mark points", action: onMarkPoints)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Lean gauge

/// One left-right difference on a centre-zero track whose zero sits on the screen axis.
/// It never colours, fills or zones the scale: it shows where the value sits and its ±.
struct LeanGauge: View {
    private let title: String
    private let measurement: MetricValue?
    private let patientRightEnd: String
    private let patientLeftEnd: String
    private let sentence: String?
    private let exportName: String?
    private let notMeasuredReason: String?
    private let isFocused: Bool
    private let compact: Bool
    private let onSelect: (() -> Void)?
    private let onMarkPoints: (() -> Void)?

    init(title: String,
         measurement: MetricValue?,
         patientRightEnd: String,
         patientLeftEnd: String,
         sentence: String?,
         exportName: String?,
         notMeasuredReason: String?,
         isFocused: Bool = false,
         compact: Bool = false,
         onSelect: (() -> Void)? = nil,
         onMarkPoints: (() -> Void)? = nil) {
        self.title = title
        self.measurement = measurement
        self.patientRightEnd = patientRightEnd
        self.patientLeftEnd = patientLeftEnd
        self.sentence = sentence
        self.exportName = exportName
        self.notMeasuredReason = notMeasuredReason
        self.isFocused = isFocused
        self.compact = compact
        self.onSelect = onSelect
        self.onMarkPoints = onMarkPoints
    }

    private var readout: String { MetricFormatter.text(measurement) }

    private var accessibilityText: String {
        var parts = [title, readout]
        if measurement == nil {
            if let notMeasuredReason { parts.append(notMeasuredReason) }
        } else if let sentence, !compact {
            parts.append(sentence)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        GaugeRowShell(accessibilityText: accessibilityText,
                      isFocused: isFocused,
                      showsMarkPoints: measurement == nil,
                      onSelect: onSelect,
                      onMarkPoints: onMarkPoints) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                GaugeTitle(title: title, isFocused: isFocused)
                if let measurement {
                    let mapping = LeanGaugeMapping(measurement)
                    VStack(spacing: Theme.Spacing.xs) {
                        EndLabels(screenLeft: patientRightEnd, screenRight: patientLeftEnd)
                        GaugeTrack(ticks: LeanGaugeMapping.tickFractions,
                                   zeroFraction: 0.5,
                                   needle: mapping.needleFraction,
                                   bracket: mapping.bracket,
                                   filled: mapping.isFilled,
                                   clampDirection: mapping.isClamped ? (mapping.value > 0 ? 1 : -1) : 0,
                                   height: compact ? 32 : 40)
                    }
                    Text(readout)
                        .font(.readoutRow)
                        .foregroundStyle(Theme.Colors.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if !compact, let sentence {
                        Text(sentence)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    NotMeasuredLine(reason: notMeasuredReason)
                }
                if !compact, let exportName {
                    ExportLine(exportName: exportName)
                }
            }
        }
    }
}

// MARK: - Overlap scale

/// Contour overlap on an unfilled 0 to 1 line. Never a fill, a ring or a zone.
struct OverlapScale: View {
    private let measurement: MetricValue?
    private let sentence: String?
    private let exportName: String?
    private let notMeasuredReason: String?
    private let isFocused: Bool
    private let compact: Bool
    private let onSelect: (() -> Void)?
    private let onMarkPoints: (() -> Void)?

    static let title = "Outline overlap"

    init(measurement: MetricValue?,
         sentence: String?,
         exportName: String?,
         notMeasuredReason: String?,
         isFocused: Bool = false,
         compact: Bool = false,
         onSelect: (() -> Void)? = nil,
         onMarkPoints: (() -> Void)? = nil) {
        self.measurement = measurement
        self.sentence = sentence
        self.exportName = exportName
        self.notMeasuredReason = notMeasuredReason
        self.isFocused = isFocused
        self.compact = compact
        self.onSelect = onSelect
        self.onMarkPoints = onMarkPoints
    }

    private var readout: String { MetricFormatter.text(measurement) }

    private var accessibilityText: String {
        var parts = [Self.title, readout]
        if measurement == nil {
            if let notMeasuredReason { parts.append(notMeasuredReason) }
        } else if let sentence, !compact {
            parts.append(sentence)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        GaugeRowShell(accessibilityText: accessibilityText,
                      isFocused: isFocused,
                      showsMarkPoints: measurement == nil,
                      onSelect: onSelect,
                      onMarkPoints: onMarkPoints) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                GaugeTitle(title: Self.title, isFocused: isFocused)
                if let measurement {
                    let v = measurement.value, u = abs(measurement.uncertainty)
                    VStack(spacing: Theme.Spacing.xs) {
                        EndLabels(screenLeft: "0, no overlap", screenRight: "1, outlines coincide")
                        GaugeTrack(ticks: [0, 0.5, 1],
                                   zeroFraction: nil,
                                   needle: OverlapScaleMapping.fraction(v),
                                   bracket: OverlapScaleMapping.fraction(v - u)...OverlapScaleMapping.fraction(v + u),
                                   filled: true,
                                   clampDirection: 0,
                                   height: compact ? 32 : 40)
                    }
                    Text(readout)
                        .font(.readoutRow)
                        .foregroundStyle(Theme.Colors.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if !compact, let sentence {
                        Text(sentence)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    NotMeasuredLine(reason: notMeasuredReason)
                }
                if !compact, let exportName {
                    ExportLine(exportName: exportName)
                }
            }
        }
    }
}
