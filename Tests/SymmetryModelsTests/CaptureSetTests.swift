import XCTest
import SymmetryCore
@testable import SymmetryModels

final class CaptureSetTests: XCTestCase {
    private func capture(_ angle: ViewAngle, failed: Bool = false, overridden: Bool = false, tilted: Bool = false) -> Capture {
        let failures: [QualityReport.Failure] = failed ? (tilted ? [.blurry, .tilted] : [.blurry]) : []
        let q = QualityReport(blurScore: 10, clippedHighlightFraction: 0, clippedShadowFraction: 0, tiltDegrees: tilted ? 12 : 1, failures: failures)
        return Capture(angle: angle, imageFilename: "\(angle.rawValue).jpg", pixelWidth: 3000, pixelHeight: 4000,
                       quality: q, tiltDegrees: q.tiltDegrees, qualityOverridden: overridden)
    }

    func testCompletenessRequiresAllThreeAngles() {
        var set = CaptureSet(stage: .afterClosure, positioning: Positioning())
        XCTAssertFalse(set.isComplete)
        XCTAssertEqual(set.missingAngles, ViewAngle.allCases)
        set.captures[.frontal] = capture(.frontal)
        set.captures[.leftOblique] = capture(.leftOblique)
        XCTAssertEqual(set.missingAngles, [.rightOblique])
        set.captures[.rightOblique] = capture(.rightOblique)
        XCTAssertTrue(set.isComplete)
        XCTAssertEqual(set.orderedCaptures.map(\.angle), ViewAngle.allCases)
    }

    func testSwapObliqueLabelsRelabelsBothCaptures() {
        var set = CaptureSet(stage: .afterClosure, positioning: Positioning())
        let left = capture(.leftOblique)
        let right = capture(.rightOblique)
        set.captures[.leftOblique] = left
        set.captures[.rightOblique] = right
        set.swapObliqueLabels()
        XCTAssertEqual(set.captures[.leftOblique]?.id, right.id)
        XCTAssertEqual(set.captures[.leftOblique]?.angle, .leftOblique)
        XCTAssertEqual(set.captures[.rightOblique]?.id, left.id)
        XCTAssertEqual(set.captures[.rightOblique]?.angle, .rightOblique)
    }

    func testUpdateMovesCaptureWhenAngleChanges() {
        var set = CaptureSet(stage: .afterClosure, positioning: Positioning())
        var c = capture(.leftOblique)
        set.captures[.leftOblique] = c
        c.angle = .rightOblique
        set.update(c)
        XCTAssertNil(set.captures[.leftOblique])
        XCTAssertEqual(set.captures[.rightOblique]?.id, c.id)
    }

    func testReliabilityFlagsFollowQualityAndOverride() {
        XCTAssertEqual(capture(.frontal).reliabilityFlags, [])
        XCTAssertEqual(capture(.frontal, failed: true).reliabilityFlags, [.lowImageQuality])
        XCTAssertEqual(capture(.frontal, failed: true, tilted: true).reliabilityFlags, [.lowImageQuality, .excessiveTilt])
        XCTAssertEqual(capture(.frontal, failed: true, overridden: true).reliabilityFlags, [.lowImageQuality, .qualityOverridden])
    }

    func testFrontalMetricsOnlyForFrontalWithLandmarks() {
        var c = capture(.frontal)
        XCTAssertNil(c.frontalMetrics(sigma: 0.015))
        var lm = LandmarkSet(imageSize: c.imageSize)
        lm[.sternalNotch] = Point2D(x: 1500, y: 800)
        lm[.midlineBottom] = Point2D(x: 1500, y: 2000)
        c.landmarks = lm
        XCTAssertNotNil(c.frontalMetrics(sigma: 0.015))
        var oblique = capture(.leftOblique)
        oblique.landmarks = lm
        XCTAssertNil(oblique.frontalMetrics(sigma: 0.015))
    }

    func testSummaryCarriesStageAndPositioning() {
        var set = CaptureSet(stage: .custom("Stage X"), positioning: Positioning(tableAngle: "30°", armPosition: "90°"))
        set.captures[.frontal] = capture(.frontal)
        let s = set.summary(sigma: 0.015)
        XCTAssertEqual(s.stageLabel, "Stage X")
        XCTAssertEqual(s.positioningNote, "Table 30°, Arms 90°")
        XCTAssertEqual(s.captures.count, 1)
    }
}
