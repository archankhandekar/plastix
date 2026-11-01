import XCTest
@testable import SymmetryCore

final class PolygonRasterTests: XCTestCase {
    private func square(x: Double, y: Double, size: Double) -> [Point2D] {
        [Point2D(x: x, y: y), Point2D(x: x + size, y: y), Point2D(x: x + size, y: y + size), Point2D(x: x, y: y + size)]
    }
    private let bounds = (min: Point2D(x: -2, y: -2), max: Point2D(x: 2, y: 2))

    func testIdenticalSquaresHaveDiceOne() {
        let a = square(x: 0, y: 0, size: 1)
        XCTAssertEqual(PolygonRaster.dice(a, a, gridSize: 256, bounds: bounds), 1.0, accuracy: 1e-9)
    }

    func testDisjointSquaresHaveDiceZero() {
        let a = square(x: -1.5, y: -1.5, size: 1)
        let b = square(x: 0.5, y: 0.5, size: 1)
        XCTAssertEqual(PolygonRaster.dice(a, b, gridSize: 256, bounds: bounds), 0.0, accuracy: 1e-9)
    }

    func testHalfOverlappingSquaresHaveDiceAboutHalf() {
        let a = square(x: 0, y: 0, size: 1)
        let b = square(x: 0.5, y: 0, size: 1)
        XCTAssertEqual(PolygonRaster.dice(a, b, gridSize: 256, bounds: bounds), 0.5, accuracy: 0.02)
    }

    func testConcavePolygonUsesEvenOddFill() {
        // A "U" shape: Dice of the U with its bounding square must be clearly below 1.
        let u: [Point2D] = [
            Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 1, y: 1), Point2D(x: 0.7, y: 1),
            Point2D(x: 0.7, y: 0.3), Point2D(x: 0.3, y: 0.3), Point2D(x: 0.3, y: 1), Point2D(x: 0, y: 1),
        ]
        let d = PolygonRaster.dice(u, square(x: 0, y: 0, size: 1), gridSize: 256, bounds: bounds)
        // U area = 1 - 0.4*0.7 = 0.72; Dice = 2*0.72 / (0.72 + 1) = 0.837
        XCTAssertEqual(d, 0.837, accuracy: 0.02)
    }

    func testEmptyOrTinyPolygonsGiveZeroWithoutCrashing() {
        XCTAssertEqual(PolygonRaster.dice([], square(x: 0, y: 0, size: 1), gridSize: 64, bounds: bounds), 0)
        XCTAssertEqual(PolygonRaster.dice([Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)], [], gridSize: 64, bounds: bounds), 0)
    }

    func testMirroredSymmetricContoursOverlapFully() throws {
        var s = FrontalMetricsTests.symmetricSet()
        // Patient-left contour (image right) and its mirror about the midline x = 500.
        let left: [Point2D] = stride(from: 0.0, through: 2 * Double.pi, by: Double.pi / 8).map {
            Point2D(x: 650 + 120 * cos($0), y: 480 + 90 * sin($0))
        }
        s.leftContour = left
        s.rightContour = left.map { $0.mirroredX(about: 500) }
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertEqual(try XCTUnwrap(m.contourOverlap).value, 1.0, accuracy: 0.03)
        XCTAssertEqual(m.contourOverlap?.unit, .dice)
        XCTAssertFalse(m.flags.contains(.contourTooSparse))
    }

    func testShiftedContourLowersOverlap() throws {
        var s = FrontalMetricsTests.symmetricSet()
        let left: [Point2D] = stride(from: 0.0, through: 2 * Double.pi, by: Double.pi / 8).map {
            Point2D(x: 650 + 120 * cos($0), y: 480 + 90 * sin($0))
        }
        s.leftContour = left
        s.rightContour = left.map { $0.mirroredX(about: 500) + Point2D(x: 0, y: 90) }
        let m = FrontalMetricsCalculator.compute(s)
        let d = try XCTUnwrap(m.contourOverlap).value
        XCTAssertLessThan(d, 0.7)
        XCTAssertGreaterThan(d, 0.2)
    }

    func testSparseContourIsNotMeasuredAndFlagged() {
        var s = FrontalMetricsTests.symmetricSet()
        s.leftContour = [Point2D(x: 600, y: 400), Point2D(x: 700, y: 400), Point2D(x: 700, y: 550), Point2D(x: 600, y: 550), Point2D(x: 600, y: 450)]
        s.rightContour = s.leftContour.map { $0.mirroredX(about: 500) }
        let m = FrontalMetricsCalculator.compute(s)
        XCTAssertNil(m.contourOverlap)
        XCTAssertTrue(m.flags.contains(.contourTooSparse))
    }
}
