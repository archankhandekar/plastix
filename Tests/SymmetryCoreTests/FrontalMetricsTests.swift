import XCTest
@testable import SymmetryCore

final class FrontalMetricsTests: XCTestCase {
    /// Upright synthetic torso: notch (500,200), midline bottom (500,700), L = 500.
    /// Patient-left structures sit on the image's right.
    static func symmetricSet() -> LandmarkSet {
        var s = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        s[.sternalNotch] = Point2D(x: 500, y: 200)
        s[.midlineBottom] = Point2D(x: 500, y: 700)
        s[.leftNipple] = Point2D(x: 650, y: 450)
        s[.rightNipple] = Point2D(x: 350, y: 450)
        s[.leftIMF] = Point2D(x: 660, y: 560)
        s[.rightIMF] = Point2D(x: 340, y: 560)
        return s
    }

    static func rotated(_ set: LandmarkSet, by angle: Double, about pivot: Point2D) -> LandmarkSet {
        var out = set
        out.points = set.points.mapValues { ($0 - pivot).rotated(by: angle) + pivot }
        out.leftContour = set.leftContour.map { ($0 - pivot).rotated(by: angle) + pivot }
        out.rightContour = set.rightContour.map { ($0 - pivot).rotated(by: angle) + pivot }
        return out
    }

    func testSymmetricSetHasZeroDifferencesWithPropagatedUncertainty() throws {
        let sigma = 0.015
        let m = FrontalMetricsCalculator.compute(Self.symmetricSet(), landmarkSigmaRatio: sigma)
        XCTAssertEqual(m.referenceLengthPixels, 500, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.verticalNippleDifference).value, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.verticalNippleDifference).uncertainty, sigma * 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(m.nippleToMidlineDifference).value, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.imfHeightDifference).value, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.leftNippleToMidline).value, 0.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.leftNippleToMidline).uncertainty, sigma, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(m.rightNippleToMidline).value, 0.3, accuracy: 1e-9)
        XCTAssertEqual(m.verticalNippleDifference?.unit, .ratioOfReference)
        XCTAssertTrue(m.flags.isEmpty)
    }

    func testLowerLeftNippleGivesPositiveVerticalDifference() throws {
        var s = Self.symmetricSet()
        s[.leftNipple] = Point2D(x: 650, y: 500) // 50 px lower = 0.1 L
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertEqual(try XCTUnwrap(m.verticalNippleDifference).value, 0.1, accuracy: 1e-9)
    }

    func testLateralLeftNippleGivesPositiveMidlineDifference() throws {
        var s = Self.symmetricSet()
        s[.leftNipple] = Point2D(x: 700, y: 450) // 0.4 L from midline vs 0.3 L
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertEqual(try XCTUnwrap(m.leftNippleToMidline).value, 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(m.nippleToMidlineDifference).value, 0.1, accuracy: 1e-9)
    }

    func testHigherLeftFoldGivesNegativeIMFDifference() throws {
        var s = Self.symmetricSet()
        s[.leftIMF] = Point2D(x: 660, y: 535) // 25 px higher = -0.05 L
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertEqual(try XCTUnwrap(m.imfHeightDifference).value, -0.05, accuracy: 1e-9)
    }

    func testMetricsAreInvariantToImageRotation() throws {
        var s = Self.symmetricSet()
        s[.leftNipple] = Point2D(x: 640, y: 480)
        s[.rightIMF] = Point2D(x: 330, y: 575)
        let a = FrontalMetricsCalculator.compute(s)
        let b = FrontalMetricsCalculator.compute(Self.rotated(s, by: 20 * .pi / 180, about: Point2D(x: 500, y: 200)))
        XCTAssertEqual(try XCTUnwrap(a.verticalNippleDifference).value, try XCTUnwrap(b.verticalNippleDifference).value, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(a.nippleToMidlineDifference).value, try XCTUnwrap(b.nippleToMidlineDifference).value, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(a.imfHeightDifference).value, try XCTUnwrap(b.imfHeightDifference).value, accuracy: 1e-6)
    }

    func testMetricsAreInvariantToImageScale() throws {
        let s = Self.symmetricSet()
        var big = s
        big.points = s.points.mapValues { $0 * 2.5 }
        let a = FrontalMetricsCalculator.compute(s)
        let b = FrontalMetricsCalculator.compute(big)
        XCTAssertEqual(try XCTUnwrap(a.leftNippleToMidline).value, try XCTUnwrap(b.leftNippleToMidline).value, accuracy: 1e-9)
        XCTAssertEqual(b.referenceLengthPixels, 1250, accuracy: 1e-9)
    }

    func testMissingFoldReportsNilForFoldMetricOnly() {
        var s = Self.symmetricSet()
        s[.leftIMF] = nil
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertNil(m.imfHeightDifference)
        XCTAssertNotNil(m.verticalNippleDifference)
        XCTAssertNotNil(m.nippleToMidlineDifference)
        XCTAssertTrue(m.flags.contains(.missingLandmarks))
    }

    func testDegenerateMidlineReportsNothing() {
        var s = Self.symmetricSet()
        s[.midlineBottom] = s[.sternalNotch]
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertNil(m.verticalNippleDifference)
        XCTAssertNil(m.leftNippleToMidline)
        XCTAssertNil(m.rightNippleToMidline)
        XCTAssertNil(m.nippleToMidlineDifference)
        XCTAssertNil(m.imfHeightDifference)
        XCTAssertEqual(m.referenceLengthPixels, 0)
        XCTAssertTrue(m.flags.contains(.degenerateMidline))
    }

    func testEmptySetReportsMissingAndDegenerate() {
        let m = FrontalMetricsCalculator.compute(LandmarkSet(imageSize: Point2D(x: 10, y: 10)))
        XCTAssertTrue(m.flags.contains(.missingLandmarks))
        XCTAssertTrue(m.flags.contains(.degenerateMidline))
        XCTAssertNil(m.verticalNippleDifference)
    }

    func testMeasurementRoundTripsThroughJSON() throws {
        let m = FrontalMetricsCalculator.compute(Self.symmetricSet())
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(FrontalMetrics.self, from: data)
        XCTAssertEqual(back.verticalNippleDifference, m.verticalNippleDifference)
        XCTAssertEqual(back.flags, m.flags)
    }
}
