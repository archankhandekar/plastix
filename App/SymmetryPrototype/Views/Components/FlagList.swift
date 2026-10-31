import SwiftUI
import SymmetryCore

/// Plain-language advice for the photo quality checks. One sentence names the problem and
/// what to try. The raw check values stay in the exported JSON, never on screen.
enum QualityAdvice {
    static let passed = "Passed the checks: sharp, well lit and level."
    /// Shown instead of `passed` when the phone gave no tilt reading (pointing down, or no
    /// motion data), so the level check never ran.
    static let passedNoTilt = "Passed the checks: sharp and well lit. Tilt was not checked."

    static func passedText(_ report: QualityReport) -> String {
        report.tiltDegrees == nil ? passedNoTilt : passed
    }
    static let kept = "Kept with this warning. It stays attached to every comparison that uses this photo."
    static let notChecked = "Quality not checked for this photo."

    static func text(_ f: QualityReport.Failure) -> String {
        switch f {
        case .blurry: return "The photo is blurred. Hold still, let the camera focus, then retake."
        case .overexposed: return "Parts of the photo are too bright. Reduce the overhead light or move the lamp, then retake."
        case .underexposed: return "Parts of the photo are too dark. Add light, then retake."
        case .tilted: return "The phone was tilted. Watch the level line until it turns teal, then retake."
        }
    }

    static func shortLabel(_ f: QualityReport.Failure) -> String {
        switch f {
        case .blurry: return "blurred"
        case .overexposed: return "too bright"
        case .underexposed: return "too dark"
        case .tilted: return "tilted"
        }
    }

    /// "Passed the checks" | "Passed the checks, tilt not checked" | "Has a warning: blurred, tilted" | "Not checked".
    static func headline(report: QualityReport?, overridden: Bool) -> String {
        guard let report else { return "Not checked" }
        if report.passed { return report.tiltDegrees == nil ? "Passed the checks, tilt not checked" : "Passed the checks" }
        return "Has a warning: " + report.failures.map(shortLabel).joined(separator: ", ")
    }
}

/// Plain-language advice for reliability flags.
enum ReliabilityAdvice {
    static func text(_ f: ReliabilityFlag) -> String {
        switch f {
        case .missingLandmarks: return "Some of the 6 points are not marked yet. Mark them to fill in the blanks."
        case .degenerateMidline: return "The notch and the midline bottom are on the same spot, so nothing can be scaled. Move one of them."
        case .contourTooSparse: return "An outline has fewer than 8 points, so overlap is left blank. Add points or leave it."
        case .lowImageQuality: return "A photo used here did not pass the checks."
        case .excessiveTilt: return "The phone was tilted past the limit when a photo was taken."
        case .registrationResidualHigh: return "The two frontal photos did not line up. Re-check the notch and midline bottom on both."
        case .qualityOverridden: return "A photo was kept despite a warning."
        }
    }

    /// True when the numbers cannot be trusted at all (unreliable colour); otherwise caution.
    static func isBlocking(_ f: ReliabilityFlag) -> Bool {
        f == .degenerateMidline || f == .registrationResidualHigh
    }
}

/// Quality advice for one capture: one line per failure, the kept line when overridden,
/// the not-checked line when there is no report.
struct QualityAdviceList: View {
    let report: QualityReport?
    let overridden: Bool
    var showsPassLine: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let report {
                if report.passed {
                    if showsPassLine {
                        Label(QualityAdvice.passedText(report), systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                } else {
                    ForEach(report.failures, id: \.self) { f in
                        Label(QualityAdvice.text(f), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.caution)
                    }
                    if overridden {
                        Text(QualityAdvice.kept).foregroundStyle(Theme.Colors.slate)
                    }
                }
            } else {
                Text(QualityAdvice.notChecked).foregroundStyle(Theme.Colors.slate)
            }
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Keeps existing call sites compiling until the camera and review screens move over.
typealias QualityFailureList = QualityAdviceList

/// Lists reliability flags next to the numbers they qualify. Empty flags render nothing.
struct FlagList: View {
    let flags: [ReliabilityFlag]
    var heading: String? = "Why these numbers need care"

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let heading {
                    Text(heading)
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)
                }
                ForEach(flags, id: \.self) { flag in
                    Label(ReliabilityAdvice.text(flag),
                          systemImage: ReliabilityAdvice.isBlocking(flag) ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(ReliabilityAdvice.isBlocking(flag) ? Theme.Colors.unreliable : Theme.Colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
