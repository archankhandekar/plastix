import CoreGraphics
import XCTest
import SymmetryCore
@testable import SymmetryPrototype

/// Pure geometry behind the Plumb design system: the gauge mapping, the plate transform
/// (its sign must match MidlineFrame.normalize) and the stage chart domain.
final class DesignGeometryTests: XCTestCase {

    // MARK: - LeanGaugeMapping

    func testPositiveLeansRightNegativeLeansLeftZeroIsCentre() {
        let m = LeanGaugeMapping(value: 0, uncertainty: 0.01)
        XCTAssertGreaterThan(m.fraction(0.05), 0.5)
        XCTAssertLessThan(m.fraction(-0.05), 0.5)
        XCTAssertEqual(m.fraction(0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(LeanGaugeMapping(value: 0, uncertainty: 0).needleFraction, 0.5, accuracy: 1e-12)
    }

    func testValueOffTheScaleIsClampedToTheEnd() {
        let m = LeanGaugeMapping(value: 0.2, uncertainty: 0.01)
        XCTAssertTrue(m.isClamped)
        XCTAssertEqual(m.needleFraction, 1.0, accuracy: 1e-12)
        XCTAssertEqual(m.fraction(-0.2), 0.0, accuracy: 1e-12)
        XCTAssertFalse(LeanGaugeMapping(value: 0.15, uncertainty: 0.01).isClamped)
    }

    func testFilledOnlyWhenLargerThanItsUncertainty() {
        XCTAssertFalse(LeanGaugeMapping(value: 0.02, uncertainty: 0.0212).isFilled)
        XCTAssertTrue(LeanGaugeMapping(value: 0.03, uncertainty: 0.0212).isFilled)
        XCTAssertTrue(LeanGaugeMapping(value: -0.03, uncertainty: 0.0212).isFilled)
    }

    func testBracketSpansTheUncertainty() {
        let m = LeanGaugeMapping(value: 0.03, uncertainty: 0.0212)
        XCTAssertEqual(m.bracket.lowerBound, m.fraction(0.03 - 0.0212), accuracy: 1e-12)
        XCTAssertEqual(m.bracket.upperBound, m.fraction(0.03 + 0.0212), accuracy: 1e-12)
        XCTAssertTrue(m.bracket.contains(m.needleFraction))
    }

    func testInitFromMetricValue() {
        let m = LeanGaugeMapping(MetricValue(value: -0.04, uncertainty: 0.01, unit: .ratioOfReference))
        XCTAssertEqual(m, LeanGaugeMapping(value: -0.04, uncertainty: 0.01))
    }

    func testSevenEvenlySpacedTicks() {
        let ticks = LeanGaugeMapping.tickFractions
        XCTAssertEqual(ticks.count, 7)
        XCTAssertEqual(ticks.first ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(ticks.last ?? -1, 1, accuracy: 1e-12)
        for i in 1..<ticks.count {
            XCTAssertEqual(ticks[i] - ticks[i - 1], 1.0 / 6.0, accuracy: 1e-12)
        }
        // The middle tick is the zero.
        XCTAssertEqual(ticks[3], 0.5, accuracy: 1e-12)
    }

    func testOverlapScaleIsClampedToZeroOne() {
        XCTAssertEqual(OverlapScaleMapping.fraction(0.82), 0.82, accuracy: 1e-12)
        XCTAssertEqual(OverlapScaleMapping.fraction(1.2), 1)
        XCTAssertEqual(OverlapScaleMapping.fraction(-0.1), 0)
    }

    // MARK: - PlateGeometry

    private let notch = Point2D(x: 500, y: 300)
    private let bottom = Point2D(x: 560, y: 900)
    private let size = CGSize(width: 400, height: 400)

    private func geometry() throws -> PlateGeometry {
        var set = LandmarkSet(imageSize: Point2D(x: 1000, y: 1400))
        set[.sternalNotch] = notch
        set[.midlineBottom] = bottom
        return try XCTUnwrap(PlateGeometry(landmarks: set, size: size))
    }

    func testNotchAndMidlineBottomLandOnTheAxis() throws {
        let g = try geometry()
        XCTAssertEqual(g.axisX, 200)
        XCTAssertEqual(g.notchY, 72, accuracy: 1e-9)
        XCTAssertEqual(g.pointsPerL, 250, accuracy: 1e-9)
        XCTAssertEqual(g.bottomY, 322, accuracy: 1e-9)

        let n = g.viewPoint(pixel: notch)
        XCTAssertEqual(n.x, 200, accuracy: 1e-6)
        XCTAssertEqual(n.y, 72, accuracy: 1e-6)
        let b = g.viewPoint(pixel: bottom)
        XCTAssertEqual(b.x, 200, accuracy: 1e-6)
        XCTAssertEqual(b.y, 322, accuracy: 1e-6)

        let tn = CGPoint(x: notch.x, y: notch.y).applying(g.imageTransform)
        let tb = CGPoint(x: bottom.x, y: bottom.y).applying(g.imageTransform)
        XCTAssertEqual(tn.x, 200, accuracy: 1e-6)
        XCTAssertEqual(tn.y, 72, accuracy: 1e-6)
        XCTAssertEqual(tb.x, 200, accuracy: 1e-6)
        XCTAssertEqual(tb.y, 322, accuracy: 1e-6)
    }

    func testImageTransformMatchesViewPointForSamplePixels() throws {
        let g = try geometry()
        XCTAssertNotEqual(g.frame.rotation, 0, "The sample midline must be rotated to test the sign.")
        for i in 0..<20 {
            let p = Point2D(x: Double((i * 137) % 1000), y: Double((i * 251) % 1400))
            let viaTransform = CGPoint(x: p.x, y: p.y).applying(g.imageTransform)
            let viaNormalize = g.viewPoint(pixel: p)
            XCTAssertEqual(viaTransform.x, viaNormalize.x, accuracy: 1e-6, "x for \(p)")
            XCTAssertEqual(viaTransform.y, viaNormalize.y, accuracy: 1e-6, "y for \(p)")
        }
    }

    func testTurnAtProgressZeroKeepsTheCapturedAngle() throws {
        let g = try geometry()
        let t0 = g.turnTransform(progress: 0)
        // With no rotation the notch still lands on (axisX, notchY) ...
        let n = CGPoint(x: notch.x, y: notch.y).applying(t0)
        XCTAssertEqual(n.x, 200, accuracy: 1e-6)
        XCTAssertEqual(n.y, 72, accuracy: 1e-6)
        // ... but the tilted midline bottom does not sit on the axis yet.
        let b = CGPoint(x: bottom.x, y: bottom.y).applying(t0)
        XCTAssertGreaterThan(abs(b.x - 200), 1)
    }

    func testPatientLeftPixelLandsOnTheScreenRightOfTheAxis() throws {
        let g = try geometry()
        // Image-right of the midline is the patient's left in a frontal photo.
        let patientLeft = Point2D(x: 700, y: 600)
        XCTAssertGreaterThan(g.viewPoint(pixel: patientLeft).x, g.axisX)
        let patientRight = Point2D(x: 350, y: 600)
        XCTAssertLessThan(g.viewPoint(pixel: patientRight).x, g.axisX)
    }

    func testMirroredPointIsSymmetricAboutTheAxis() throws {
        let g = try geometry()
        let p = Point2D(x: 380, y: 640)
        let v = g.viewPoint(pixel: p)
        let m = g.mirroredViewPoint(pixel: p)
        XCTAssertEqual(v.y, m.y, accuracy: 1e-9)
        XCTAssertEqual((v.x + m.x) / 2, g.axisX, accuracy: 1e-9)
        XCTAssertLessThan(v.x, g.axisX)
        XCTAssertGreaterThan(m.x, g.axisX)
    }

    func testUncertaintyPointsScaleWithL() throws {
        let g = try geometry()
        XCTAssertEqual(g.uncertaintyPoints(0.02), 5, accuracy: 1e-9)
    }

    func testCanTurnNeedsTwoDistinctMidlinePoints() {
        XCTAssertFalse(PlateGeometry.canTurn(nil))
        var set = LandmarkSet(imageSize: Point2D(x: 100, y: 100))
        XCTAssertFalse(PlateGeometry.canTurn(set))
        set[.sternalNotch] = Point2D(x: 50, y: 10)
        set[.midlineBottom] = Point2D(x: 50, y: 10)
        XCTAssertFalse(PlateGeometry.canTurn(set))
        XCTAssertNil(PlateGeometry(landmarks: set, size: size))
        set[.midlineBottom] = Point2D(x: 52, y: 90)
        XCTAssertTrue(PlateGeometry.canTurn(set))
    }

    // MARK: - StageLeanChart.domain

    func testStageChartDomainIsSymmetricAndAtLeastTheGaugeRange() {
        let none = StageLeanChart.domain(for: [])
        XCTAssertEqual(none.lowerBound, -0.15, accuracy: 1e-12)
        XCTAssertEqual(none.upperBound, 0.15, accuracy: 1e-12)

        let small = StageLeanChart.domain(for: [
            .init(id: 1, label: "Set 1", measurement: MetricValue(value: 0.03, uncertainty: 0.02, unit: .ratioOfReference)),
            .init(id: 2, label: "Set 2", measurement: nil),
        ])
        XCTAssertEqual(small.lowerBound, -small.upperBound, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(small.upperBound, 0.15)

        let wide = StageLeanChart.domain(for: [
            .init(id: 1, label: "Set 1", measurement: MetricValue(value: -0.20, uncertainty: 0.02, unit: .ratioOfReference)),
            .init(id: 2, label: "Set 2", measurement: MetricValue(value: 0.05, uncertainty: 0.01, unit: .ratioOfReference)),
        ])
        XCTAssertEqual(wide.lowerBound, -wide.upperBound, accuracy: 1e-12)
        XCTAssertEqual(wide.upperBound, 1.1 * 0.22, accuracy: 1e-12)
    }
}
