import Foundation
import SymmetryCore

/// Assembles the de-identified research report for a session.
public enum ReportBuilder {
    /// Lists every capture set in chronological order and compares every pair of sets
    /// whose frontal captures both have landmarks (earlier set as baseline).
    public static func report(for session: StudySession, settings: ReportSettings, generatedAt: Date = Date()) -> ResearchReport {
        let sets = session.orderedCaptureSets
        let summaries = sets.map { $0.summary(sigma: settings.landmarkSigmaRatio) }

        var comparisons: [ComparisonSummary] = []
        for i in sets.indices {
            for j in sets.indices where j > i {
                guard let result = compareFrontal(baseline: sets[i], current: sets[j], settings: settings) else { continue }
                comparisons.append(ComparisonSummary(baselineSetID: sets[i].id, currentSetID: sets[j].id, result: result))
            }
        }
        return ResearchReport(studyID: session.studyID, generatedAt: generatedAt, settings: settings,
                              captureSets: summaries, comparisons: comparisons)
    }

    /// Frontal comparison of two sets, or nil when either lacks frontal landmarks.
    public static func compareFrontal(baseline: CaptureSet, current: CaptureSet, settings: ReportSettings) -> CaptureComparison? {
        guard let b = baseline.frontal, let c = current.frontal, let bl = b.landmarks, let cl = c.landmarks,
              let bm = b.frontalMetrics(sigma: settings.landmarkSigmaRatio),
              let cm = c.frontalMetrics(sigma: settings.landmarkSigmaRatio) else { return nil }
        let registration = Registration.register(cl, to: bl, maxResidualRatio: settings.maxResidualRatio)
        return Comparator.compare(baseline: bm, current: cm, registration: registration, angle: .frontal,
                                  captureFlags: b.reliabilityFlags + c.reliabilityFlags)
    }
}
