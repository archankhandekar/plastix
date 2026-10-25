import SwiftUI
import SymmetryCore

/// Lists reliability flags next to the numbers they qualify. Empty flags render nothing.
struct FlagList: View {
    let flags: [ReliabilityFlag]

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(flags, id: \.self) { flag in
                    Label(flag.displayText, systemImage: flag == .registrationResidualHigh || flag == .degenerateMidline
                          ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(flag == .registrationResidualHigh || flag == .degenerateMidline
                                         ? Theme.Colors.unreliable : Theme.Colors.caution)
                }
            }
        }
    }
}

/// Quality failures for one capture.
struct QualityFailureList: View {
    let report: QualityReport?
    let overridden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let report {
                if report.passed {
                    Label("Quality checks passed", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    ForEach(report.failures, id: \.self) { f in
                        Label(f.displayText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.caution)
                    }
                    if overridden {
                        Text("Kept despite the warning").foregroundStyle(Theme.Colors.slate)
                    }
                }
                Text("Blur \(report.blurScore, specifier: "%.0f"), clipped \(report.clippedHighlightFraction * 100, specifier: "%.1f")% high, \(report.clippedShadowFraction * 100, specifier: "%.1f")% low\(report.tiltDegrees.map { String(format: ", roll %.0f°", $0) } ?? "")")
                    .font(.metricSmall)
                    .foregroundStyle(Theme.Colors.slate)
            } else {
                Text("Quality not checked").foregroundStyle(Theme.Colors.slate)
            }
        }
        .font(.footnote)
    }
}
