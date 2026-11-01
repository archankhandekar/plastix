import XCTest
@testable import SymmetryCore

final class LandmarkSetTests: XCTestCase {
    func testEmptySetIsNotComplete() {
        let set = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        XCTAssertFalse(set.isComplete)
        XCTAssertEqual(set.missing, LandmarkType.allCases)
    }

    func testSetWithSixPointsIsComplete() {
        var set = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        for type in LandmarkType.allCases {
            set.points[type] = Point2D(x: 500, y: 500)
        }
        XCTAssertTrue(set.isComplete)
        XCTAssertTrue(set.missing.isEmpty)
    }

    func testMissingListsAbsentTypesInDeclarationOrder() {
        var set = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        set.points[.sternalNotch] = Point2D(x: 500, y: 100)
        set.points[.leftNipple] = Point2D(x: 700, y: 600)
        XCTAssertEqual(set.missing, [.midlineBottom, .rightNipple, .leftIMF, .rightIMF])
    }

    func testPointRotationByQuarterTurn() {
        let p = Point2D(x: 1, y: 0).rotated(by: .pi / 2)
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p.y, 1, accuracy: 1e-9)
    }

    func testPointDistanceAndMirror() {
        let a = Point2D(x: 0, y: 0)
        let b = Point2D(x: 3, y: 4)
        XCTAssertEqual(a.distance(to: b), 5, accuracy: 1e-12)
        XCTAssertEqual(b.mirroredX(about: 1).x, -1, accuracy: 1e-12)
        XCTAssertEqual(b.mirroredX(about: 1).y, 4, accuracy: 1e-12)
    }

    func testViewAngleAndLandmarkNamesUsePatientSide() {
        XCTAssertEqual(LandmarkType.leftNipple.displayName, "Patient left nipple")
        XCTAssertEqual(LandmarkType.rightIMF.displayName, "Patient right inframammary fold")
        XCTAssertEqual(ViewAngle.leftOblique.displayName, "Left oblique")
        XCTAssertEqual(ViewAngle.allCases.count, 3)
    }

    func testLandmarkSetRoundTripsThroughJSON() throws {
        var set = LandmarkSet(imageSize: Point2D(x: 1000, y: 1500))
        set.points[.sternalNotch] = Point2D(x: 500, y: 100)
        set.leftContour = [Point2D(x: 1, y: 2), Point2D(x: 3, y: 4)]
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(LandmarkSet.self, from: data)
        XCTAssertEqual(decoded, set)
    }
}
