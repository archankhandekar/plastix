import CoreGraphics
import SwiftUI
import XCTest
import SymmetryCore
@testable import SymmetryPrototype

/// Pure layout rules of the symmetry plate: layer strength, the direction words on a
/// label, where calipers, labels and the comparison lane sit, when a caliper collapses to
/// one tick, and where the mirror tick lands.
final class SymmetryPlateLayoutTests: XCTestCase {

    private func reading(_ metric: BilateralMetric, _ value: Double?, _ u: Double = 0.021) -> MetricReading {
        let m = value.map { MetricValue(value: $0, uncertainty: u, unit: .ratioOfReference) }
        return MetricReading(metric: metric, measurement: m, readout: MetricFormatter.text(m),
                             sentence: nil, notMeasuredReason: m == nil ? "Not measured: place both folds." : nil,
                             isDistinguishableFromZero: m.map { abs($0.value) > $0.uncertainty } ?? false)
    }

    // MARK: - Layer strength

    func testAllDrawsEveryLayerStronglyAndFocusDimsTheOthers() {
        XCTAssertEqual(PlateLayout.opacity(of: .nippleHeight, focus: .all), 0.85)
        XCTAssertEqual(PlateLayout.opacity(of: .nippleHeight, focus: .nippleHeight), 1)
        XCTAssertEqual(PlateLayout.opacity(of: .foldHeight, focus: .nippleHeight), 0.4)
        XCTAssertTrue(PlateLayout.showsLabels(of: .foldHeight, focus: .all))
        XCTAssertTrue(PlateLayout.showsLabels(of: .foldHeight, focus: .foldHeight))
        XCTAssertFalse(PlateLayout.showsLabels(of: .foldHeight, focus: .outlines))
    }

    // MARK: - Labels

    func testReadoutBreaksBeforeItsPlusMinusWithoutChangingACharacter() {
        let readout = MetricFormatter.text(MetricValue(value: 0.071, uncertainty: 0.021, unit: .ratioOfReference))
        let lines = PlateLayout.readoutLines(readout)
        XCTAssertEqual(lines, ["+0.071", "± 0.021 L"])
        XCTAssertEqual(lines.joined(separator: " "), readout)
        XCTAssertEqual(PlateLayout.readoutLines("Not measured"), ["Not measured"])
    }

    func testDirectionFollowsTheSignOnlyBeyondTheUncertainty() {
        // Positive: patient left lower (patient left is the screen-right side).
        XCTAssertEqual(PlateLayout.direction(of: reading(.nippleHeight, 0.071)), "Left lower")
        XCTAssertEqual(PlateLayout.direction(of: reading(.foldHeight, -0.034)), "Right lower")
        XCTAssertEqual(PlateLayout.direction(of: reading(.nippleMidline, 0.07)), "Left farther")
        XCTAssertEqual(PlateLayout.direction(of: reading(.nippleMidline, -0.07)), "Right farther")
        // Within its ±, exactly at it, or not measured: no direction.
        XCTAssertNil(PlateLayout.direction(of: reading(.nippleHeight, 0.01)))
        XCTAssertNil(PlateLayout.direction(of: reading(.nippleHeight, -0.021)))
        XCTAssertNil(PlateLayout.direction(of: reading(.foldHeight, nil)))
    }

    func testGutterLinesKeepTheReadoutAndAddTheDirection() {
        XCTAssertEqual(PlateLayout.gutterLines(reading(.nippleHeight, 0.078)), ["+0.078", "± 0.021 L", "Left lower"])
        XCTAssertEqual(PlateLayout.gutterLines(reading(.foldHeight, 0.01)), ["+0.010", "± 0.021 L"])
        XCTAssertEqual(PlateLayout.gutterLines(reading(.foldHeight, nil)), ["Not measured"])
    }

    func testRulerLabelStepsAsideFromAGuide() {
        XCTAssertTrue(PlateLayout.rulerLabelIsClear(y: 100, labelHeight: 20, guides: []))
        XCTAssertTrue(PlateLayout.rulerLabelIsClear(y: 100, labelHeight: 20, guides: [60, 120]))
        XCTAssertFalse(PlateLayout.rulerLabelIsClear(y: 100, labelHeight: 20, guides: [60, 115]))
        XCTAssertFalse(PlateLayout.rulerLabelIsClear(y: 100, labelHeight: 20, guides: [100]))
    }

    // MARK: - Calipers, gutters and the lane

    func testLateralEdgeIsTheFarthestOutlinePointOnItsOwnSide() {
        let outline = [CGPoint(x: 210, y: 100), CGPoint(x: 290, y: 140), CGPoint(x: 250, y: 180)]
        XCTAssertEqual(PlateLayout.lateralEdge(outline: outline, nipple: CGPoint(x: 260, y: 150), axisX: 180,
                                               pointsPerL: 250, patientLeft: true), 302.5)
        XCTAssertEqual(PlateLayout.lateralEdge(outline: [], nipple: CGPoint(x: 260, y: 150), axisX: 180,
                                               pointsPerL: 250, patientLeft: true), 302.5)
        XCTAssertEqual(PlateLayout.lateralEdge(outline: [CGPoint(x: 60, y: 100), CGPoint(x: 140, y: 120)],
                                               nipple: nil, axisX: 180, pointsPerL: 250, patientLeft: false), 60)
        XCTAssertNil(PlateLayout.lateralEdge(outline: [], nipple: nil, axisX: 180, pointsPerL: 250, patientLeft: true))
    }

    func testHeightCaliperSitsJustOutsideTheTorsoAndOnThePlate() {
        XCTAssertEqual(PlateLayout.caliperX(lateralEdge: 290, plateWidth: 360), 300)
        XCTAssertEqual(PlateLayout.caliperX(lateralEdge: 355, plateWidth: 360), 348)
        XCTAssertEqual(PlateLayout.caliperX(lateralEdge: nil, plateWidth: 400), 350)
    }

    func testGutterLabelsSitFlushWithTheirOwnSide() {
        // Patient left is the screen-right side.
        XCTAssertEqual(PlateLayout.gutterLabelX(labelWidth: 60, plateWidth: 360, patientLeft: true), 296)
        XCTAssertEqual(PlateLayout.gutterLabelX(labelWidth: 60, plateWidth: 360, patientLeft: false), 4)
    }

    func testLaneSitsUnderTheLowestGuideAndStaysOnThePlate() {
        XCTAssertEqual(PlateLayout.laneY(lowestGuide: 200, plateHeight: 320), 224)
        XCTAssertEqual(PlateLayout.laneY(lowestGuide: 300, plateHeight: 320), 306)
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
        // The symmetry plate's wide framing: k = 256 / 1.28 = 200 points per L, axisX = 160.
        let g = PlateGeometry(frame: frame, size: CGSize(width: 320, height: 256), framing: .wide)
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
        let g = PlateGeometry(frame: frame, size: CGSize(width: 390, height: 390 * 7 / 8), framing: .wide)
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
        let g = PlateGeometry(frame: frame, size: CGSize(width: 320, height: 256), framing: .wide)
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
