import CoreGraphics
import SwiftUI
import XCTest
import SymmetryCore
@testable import SymmetryPrototype

/// Pure layout rules of the symmetry plate: which edge a height caliper sits on, when a
/// caliper collapses to one tick, and where the mirror tick lands.
final class SymmetryPlateLayoutTests: XCTestCase {

    // MARK: - caliperEdge

    func testPositiveBeyondItsUncertaintySitsOnTheTrailingEdge() {
        // Patient left lower: patient left is the screen-right side.
        XCTAssertEqual(PlateLayout.caliperEdge(value: 0.071, uncertainty: 0.021), .trailing)
    }

    func testNegativeBeyondItsUncertaintySitsOnTheLeadingEdge() {
        XCTAssertEqual(PlateLayout.caliperEdge(value: -0.034, uncertainty: 0.021), .leading)
    }

    func testWithinItsUncertaintyStaysOnTheTrailingEdge() {
        XCTAssertEqual(PlateLayout.caliperEdge(value: 0.01, uncertainty: 0.021), .trailing)
        XCTAssertEqual(PlateLayout.caliperEdge(value: -0.01, uncertainty: 0.021), .trailing)
        XCTAssertEqual(PlateLayout.caliperEdge(value: 0, uncertainty: 0.021), .trailing)
    }

    func testExactlyAtItsUncertaintyCountsAsWithin() {
        XCTAssertEqual(PlateLayout.caliperEdge(value: 0.021, uncertainty: 0.021), .trailing)
        XCTAssertEqual(PlateLayout.caliperEdge(value: -0.021, uncertainty: 0.021), .trailing)
        XCTAssertEqual(PlateLayout.caliperEdge(value: -0.0211, uncertainty: 0.021), .leading)
    }

    // MARK: - isCollapsed

    func testLinesCloserThanSixPointsCollapse() {
        XCTAssertTrue(PlateLayout.isCollapsed(100, 100))
        XCTAssertTrue(PlateLayout.isCollapsed(100, 105.9))
        XCTAssertTrue(PlateLayout.isCollapsed(105.9, 100))
    }

    func testLinesSixPointsOrMoreApartDoNotCollapse() {
        XCTAssertFalse(PlateLayout.isCollapsed(100, 106))
        XCTAssertFalse(PlateLayout.isCollapsed(106, 100))
        XCTAssertFalse(PlateLayout.isCollapsed(20, 80))
    }

    // MARK: - mirrorTickX

    func testMirrorTickCarriesTheRightDistanceAcrossAnUprightMidline() throws {
        // Notch (500, 100), midline bottom (500, 900): L = 800 px, no rotation.
        let frame = try XCTUnwrap(MidlineFrame(notch: Point2D(x: 500, y: 100), midlineBottom: Point2D(x: 500, y: 900)))
        let g = PlateGeometry(frame: frame, size: CGSize(width: 320, height: 320))
        // k = 320 / 1.6 = 200 points per L, axisX = 160.
        // The patient-right nipple sits 200 px (0.25 L) to the image's left of the midline.
        let x = PlateLayout.mirrorTickX(geometry: g, rightNipplePixel: Point2D(x: 300, y: 400))
        XCTAssertEqual(x, 160 + 0.25 * 200, accuracy: 1e-9)
        XCTAssertGreaterThan(x, g.axisX)
    }

    func testMirrorTickMatchesTheMirroredRightNippleOnARotatedMidline() throws {
        // A rolled photo: the midline leans, so normalization has to rotate.
        let notch = Point2D(x: 980, y: 420)
        let bottom = Point2D(x: 1120, y: 1650)
        let frame = try XCTUnwrap(MidlineFrame(notch: notch, midlineBottom: bottom))
        XCTAssertNotEqual(frame.rotation, 0)
        let g = PlateGeometry(frame: frame, size: CGSize(width: 390, height: 390))
        let rightNipple = Point2D(x: 700, y: 1000)

        let x = PlateLayout.mirrorTickX(geometry: g, rightNipplePixel: rightNipple)
        let n = frame.normalize(rightNipple)
        XCTAssertLessThan(n.x, 0, "the patient right is on the image's left")
        XCTAssertEqual(x, g.axisX + CGFloat(abs(n.x)) * g.pointsPerL, accuracy: 1e-9)
        // The same place the mirrored point lands, and on the patient-left (screen-right) side.
        XCTAssertEqual(x, g.mirroredViewPoint(pixel: rightNipple).x, accuracy: 1e-9)
        XCTAssertGreaterThan(x, g.axisX)
        // Exactly as far from the axis as the right nipple itself, on the other side.
        XCTAssertEqual(x - g.axisX, g.axisX - g.viewPoint(pixel: rightNipple).x, accuracy: 1e-9)
    }

    func testMirrorTickUsesTheDistanceEvenWhenTheRightNippleCrossesTheMidline() throws {
        let frame = try XCTUnwrap(MidlineFrame(notch: Point2D(x: 500, y: 100), midlineBottom: Point2D(x: 500, y: 900)))
        let g = PlateGeometry(frame: frame, size: CGSize(width: 320, height: 320))
        let x = PlateLayout.mirrorTickX(geometry: g, rightNipplePixel: Point2D(x: 540, y: 400))
        XCTAssertEqual(x, 160 + 0.05 * 200, accuracy: 1e-9)
    }

    // MARK: - drawProgress

    func testDrawStagesStartInTurnAndAllFinish() {
        XCTAssertEqual(PlateLayout.drawProgress(clock: 0, stage: 0), 0, accuracy: 1e-12)
        for stage in 0..<PlateLayout.drawStageCount {
            XCTAssertEqual(PlateLayout.drawProgress(clock: 1, stage: stage), 1, accuracy: 1e-12)
        }
        // Part way through, an earlier guide is always further along than a later one.
        let early = PlateLayout.drawProgress(clock: 0.3, stage: 0)
        let late = PlateLayout.drawProgress(clock: 0.3, stage: 4)
        XCTAssertGreaterThan(early, late)
        XCTAssertEqual(PlateLayout.drawTotalDuration, 0.3 + 5 * Motion.drawStagger, accuracy: 1e-12)
    }
}
