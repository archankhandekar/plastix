import XCTest
@testable import SymmetryCore

final class MidlineFrameTests: XCTestCase {
    private func set(notch: Point2D, bottom: Point2D) -> LandmarkSet {
        var s = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        s[.sternalNotch] = notch
        s[.midlineBottom] = bottom
        return s
    }

    func testUprightMidlineNormalizesNotchToOriginAndBottomToUnitY() throws {
        let frame = try XCTUnwrap(MidlineFrame.from(set(notch: Point2D(x: 500, y: 200), bottom: Point2D(x: 500, y: 700))))
        XCTAssertEqual(frame.referenceLength, 500, accuracy: 1e-9)
        let n = frame.normalize(Point2D(x: 500, y: 200))
        let b = frame.normalize(Point2D(x: 500, y: 700))
        XCTAssertEqual(n.x, 0, accuracy: 1e-9); XCTAssertEqual(n.y, 0, accuracy: 1e-9)
        XCTAssertEqual(b.x, 0, accuracy: 1e-9); XCTAssertEqual(b.y, 1, accuracy: 1e-9)
    }

    func testTiltedMidlineIsRotatedUpright() throws {
        // Midline tilted 30 degrees from vertical, length 400.
        let notch = Point2D(x: 500, y: 200)
        let bottom = Point2D(x: 500 + 400 * sin(Double.pi / 6), y: 200 + 400 * cos(Double.pi / 6))
        let frame = try XCTUnwrap(MidlineFrame.from(set(notch: notch, bottom: bottom)))
        XCTAssertEqual(frame.referenceLength, 400, accuracy: 1e-6)
        let b = frame.normalize(bottom)
        XCTAssertEqual(b.x, 0, accuracy: 1e-6)
        XCTAssertEqual(b.y, 1, accuracy: 1e-6)
    }

    func testPointToImageRightOfMidlineHasPositiveX() throws {
        let frame = try XCTUnwrap(MidlineFrame.from(set(notch: Point2D(x: 500, y: 200), bottom: Point2D(x: 500, y: 700))))
        let p = frame.normalize(Point2D(x: 750, y: 450))
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.5, accuracy: 1e-9)
    }

    func testDistancesScaleByReferenceLength() throws {
        let frame = try XCTUnwrap(MidlineFrame.from(set(notch: Point2D(x: 100, y: 100), bottom: Point2D(x: 100, y: 300))))
        let a = frame.normalize(Point2D(x: 100, y: 100))
        let b = frame.normalize(Point2D(x: 160, y: 180))
        XCTAssertEqual(a.distance(to: b), 100.0 / 200.0, accuracy: 1e-9)
    }

    func testMissingMidlinePointGivesNil() {
        var s = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        s[.midlineBottom] = Point2D(x: 500, y: 700)
        XCTAssertNil(MidlineFrame.from(s))
    }

    func testCoincidentMidlinePointsGiveNil() {
        XCTAssertNil(MidlineFrame.from(set(notch: Point2D(x: 500, y: 200), bottom: Point2D(x: 500, y: 200))))
        XCTAssertNil(MidlineFrame.from(set(notch: Point2D(x: 500, y: 200), bottom: Point2D(x: 500.3, y: 200.2))))
    }

    func testDenormalizeInvertsNormalize() throws {
        let notch = Point2D(x: 420, y: 180)
        let bottom = Point2D(x: 560, y: 690)
        let frame = try XCTUnwrap(MidlineFrame.from(set(notch: notch, bottom: bottom)))
        let p = Point2D(x: 777, y: 333)
        let back = frame.denormalize(frame.normalize(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
    }
}
