import XCTest
import SymmetryCore
@testable import SymmetryModels

final class ReportBuilderTests: XCTestCase {
    private func frontal(withLandmarks: Bool) -> Capture {
        var c = Capture(angle: .frontal, imageFilename: "f.jpg", pixelWidth: 1000, pixelHeight: 1500, quality: nil, tiltDegrees: nil)
        if withLandmarks {
            var lm = LandmarkSet(imageSize: c.imageSize)
            lm[.sternalNotch] = Point2D(x: 500, y: 200); lm[.midlineBottom] = Point2D(x: 500, y: 700)
            lm[.leftNipple] = Point2D(x: 650, y: 450); lm[.rightNipple] = Point2D(x: 350, y: 450)
            lm[.leftIMF] = Point2D(x: 660, y: 560); lm[.rightIMF] = Point2D(x: 340, y: 560)
            c.landmarks = lm
        }
        return c
    }

    private func set(_ t: TimeInterval, landmarks: Bool) -> CaptureSet {
        var s = CaptureSet(stage: .afterClosure, positioning: Positioning(), createdAt: Date(timeIntervalSince1970: t))
        s.captures[.frontal] = frontal(withLandmarks: landmarks)
        return s
    }

    private let settings = ReportSettings(landmarkSigmaRatio: 0.015, qualityThresholds: QualityThresholds(), maxResidualRatio: 0.05)

    func testReportListsSetsInOrderAndComparesEveryLandmarkedPair() {
        let session = StudySession(studyID: "S-9", captureSets: [set(300, landmarks: true), set(100, landmarks: true), set(200, landmarks: true)])
        let report = ReportBuilder.report(for: session, settings: settings)
        XCTAssertEqual(report.studyID, "S-9")
        XCTAssertEqual(report.captureSets.map(\.capturedAt.timeIntervalSince1970), [100, 200, 300])
        XCTAssertEqual(report.comparisons.count, 3) // (1,2) (1,3) (2,3)
        XCTAssertEqual(report.comparisons.first?.baselineSetID, report.captureSets[0].id)
        XCTAssertEqual(report.comparisons.first?.currentSetID, report.captureSets[1].id)
        XCTAssertEqual(report.comparisons.first?.result.angle, .frontal)
        XCTAssertEqual(report.settings, settings)
    }

    func testSetsWithoutLandmarksAreListedButNotCompared() {
        let session = StudySession(studyID: "S-9", captureSets: [set(100, landmarks: true), set(200, landmarks: false)])
        let report = ReportBuilder.report(for: session, settings: settings)
        XCTAssertEqual(report.captureSets.count, 2)
        XCTAssertTrue(report.comparisons.isEmpty)
        XCTAssertNil(report.captureSets[1].captures.first?.frontalMetrics)
        XCTAssertNotNil(report.captureSets[0].captures.first?.frontalMetrics)
    }

    func testCaptureFlagsTravelIntoComparisons() {
        var a = set(100, landmarks: true)
        var c = a.captures[.frontal]!
        c.quality = QualityReport(blurScore: 1, clippedHighlightFraction: 0, clippedShadowFraction: 0, tiltDegrees: nil, failures: [.blurry])
        c.qualityOverridden = true
        a.captures[.frontal] = c
        let session = StudySession(studyID: "S-9", captureSets: [a, set(200, landmarks: true)])
        let report = ReportBuilder.report(for: session, settings: settings)
        let flags = report.comparisons.first?.result.flags ?? []
        XCTAssertTrue(flags.contains(.lowImageQuality))
        XCTAssertTrue(flags.contains(.qualityOverridden))
    }
}
