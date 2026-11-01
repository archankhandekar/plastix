import XCTest
import SymmetryCore
@testable import SymmetryPrototype

/// The practice teaching aid: the ring radius, the inside / outside / not placed lines, their
/// order, and that no line ever reads as a count or a grade.
final class TeachingCheckTests: XCTestCase {
    private let sigma = 0.015

    /// Notch (600, 400), midline bottom (600, 1000): L = 600 px, so the ring radius is
    /// 2 * 0.015 * 600 = 18 px.
    private func truth(_ points: [LandmarkType: Point2D]? = nil) -> LandmarkSet {
        LandmarkSet(points: points ?? [
            .sternalNotch: Point2D(x: 600, y: 400),
            .midlineBottom: Point2D(x: 600, y: 1000),
            .leftNipple: Point2D(x: 800, y: 640),
            .rightNipple: Point2D(x: 400, y: 640),
            .leftIMF: Point2D(x: 790, y: 820),
            .rightIMF: Point2D(x: 410, y: 820),
        ], leftContour: [], rightContour: [], imageSize: Point2D(x: 1200, y: 1600))
    }

    private func shifted(_ set: LandmarkSet, by dx: Double) -> LandmarkSet {
        LandmarkSet(points: set.points.mapValues { Point2D(x: $0.x + dx, y: $0.y) },
                    leftContour: [], rightContour: [], imageSize: set.imageSize)
    }

    private static let names: [LandmarkType: String] = [
        .leftNipple: "Patient left nipple",
        .rightNipple: "Patient right nipple",
        .leftIMF: "Patient left fold",
        .rightIMF: "Patient right fold",
        .sternalNotch: "Sternal notch",
        .midlineBottom: "Midline bottom",
    ]

    // MARK: - Radius

    func testRingRadiusIsTwoSigmaL() throws {
        let r = try XCTUnwrap(TeachingCheck.ringRadiusPixels(truth: truth(), sigma: sigma))
        XCTAssertEqual(r, 18, accuracy: 1e-9)
        let wider = try XCTUnwrap(TeachingCheck.ringRadiusPixels(truth: truth(), sigma: 0.03))
        XCTAssertEqual(wider, 36, accuracy: 1e-9)
    }

    func testRingRadiusUsesTheFullNotchToBottomDistance() throws {
        var t = truth()
        t[.midlineBottom] = Point2D(x: 960, y: 880) // 360 across, 480 down: 600 px
        let r = try XCTUnwrap(TeachingCheck.ringRadiusPixels(truth: t, sigma: sigma))
        XCTAssertEqual(r, 18, accuracy: 1e-9)
    }

    func testNoRadiusWithoutMidlineTruth() {
        var noBottom = truth()
        noBottom[.midlineBottom] = nil
        XCTAssertNil(TeachingCheck.ringRadiusPixels(truth: noBottom, sigma: sigma))
        var noNotch = truth()
        noNotch[.sternalNotch] = nil
        XCTAssertNil(TeachingCheck.ringRadiusPixels(truth: noNotch, sigma: sigma))
        XCTAssertEqual(TeachingCheck.lines(placed: truth(), truth: noNotch, sigma: sigma), [])
    }

    // MARK: - Lines

    func testInsideForEachType() {
        let t = truth()
        // 10 px off, inside an 18 px ring.
        let lines = TeachingCheck.lines(placed: shifted(t, by: 10), truth: t, sigma: sigma)
        XCTAssertEqual(lines.count, 6)
        for (type, line) in zip(LandmarkType.allCases, lines) {
            XCTAssertEqual(line, "\(Self.names[type]!): inside its ring.")
        }
    }

    func testOnTheRingCountsAsInside() {
        let t = truth()
        let lines = TeachingCheck.lines(placed: shifted(t, by: 18), truth: t, sigma: sigma)
        XCTAssertTrue(lines.allSatisfy { $0.hasSuffix(": inside its ring.") }, "\(lines)")
    }

    func testOutsideForEachType() {
        let t = truth()
        let lines = TeachingCheck.lines(placed: shifted(t, by: 25), truth: t, sigma: sigma)
        XCTAssertEqual(lines.count, 6)
        for (type, line) in zip(LandmarkType.allCases, lines) {
            XCTAssertEqual(line, "\(Self.names[type]!): outside its ring. Drag it closer.")
        }
    }

    func testNotPlacedForEachType() {
        let t = truth()
        let empty = LandmarkSet(imageSize: t.imageSize)
        for placed in [empty, nil] as [LandmarkSet?] {
            let lines = TeachingCheck.lines(placed: placed, truth: t, sigma: sigma)
            XCTAssertEqual(lines.count, 6)
            for (type, line) in zip(LandmarkType.allCases, lines) {
                XCTAssertEqual(line, "\(Self.names[type]!): not placed yet.")
            }
        }
    }

    func testMixedPlacementsAndOrder() {
        let t = truth()
        var placed = LandmarkSet(imageSize: t.imageSize)
        placed[.sternalNotch] = Point2D(x: 605, y: 400)   // inside
        placed[.leftNipple] = Point2D(x: 800, y: 700)     // outside, 60 px low
        placed[.rightIMF] = Point2D(x: 410, y: 830)       // inside
        let lines = TeachingCheck.lines(placed: placed, truth: t, sigma: sigma)
        XCTAssertEqual(lines, [
            "Sternal notch: inside its ring.",
            "Midline bottom: not placed yet.",
            "Patient left nipple: outside its ring. Drag it closer.",
            "Patient right nipple: not placed yet.",
            "Patient left fold: not placed yet.",
            "Patient right fold: inside its ring.",
        ])
    }

    func testOnlyPointsWithTruthGetALine() {
        // An oblique render can hide a nipple: no truth, so no line for it.
        var t = truth()
        t[.rightNipple] = nil
        let lines = TeachingCheck.lines(placed: t, truth: t, sigma: sigma)
        XCTAssertEqual(lines.count, 5)
        XCTAssertFalse(lines.contains { $0.hasPrefix("Patient right nipple") })
    }

    func testScaledTruthFollowsThePhotoSize() throws {
        let t = truth()
        let half = TeachingCheck.scaled(t, to: Point2D(x: 600, y: 800))
        XCTAssertEqual(half.imageSize, Point2D(x: 600, y: 800))
        XCTAssertEqual(try XCTUnwrap(half[.leftNipple]), Point2D(x: 400, y: 320))
        let r = try XCTUnwrap(TeachingCheck.ringRadiusPixels(truth: half, sigma: sigma))
        XCTAssertEqual(r, 9, accuracy: 1e-9)
        XCTAssertEqual(TeachingCheck.scaled(t, to: t.imageSize), t)
    }

    // MARK: - Targets on the canvas

    /// The drawn ring is the true check radius (so "inside its ring" means what it shows),
    /// mapped through the fit rect, never below the minimum; ticks sit outside it.
    func testTargetsMapThroughTheFitAndKeepTheCheckRadius() throws {
        let fit = CGRect(x: 10, y: 20, width: 300, height: 400) // 1200 x 1600 pixels at 0.25
        let targets = TeachingRings.targets(truth: truth(), radiusPixels: 18 * 4, pixelSize: CGSize(width: 1200, height: 1600), fit: fit)
        XCTAssertEqual(targets.map(\.type), LandmarkType.allCases)
        let notch = try XCTUnwrap(targets.first { $0.type == .sternalNotch })
        XCTAssertEqual(notch.center.x, 10 + 600 * 0.25, accuracy: 1e-9)
        XCTAssertEqual(notch.center.y, 20 + 400 * 0.25, accuracy: 1e-9)
        // Ring 18pt plus a 3pt gap and 6pt ticks.
        XCTAssertEqual(notch.outerRadius, 18 + 9, accuracy: 1e-9)

        let tiny = TeachingRings.targets(truth: truth(), radiusPixels: 1, pixelSize: CGSize(width: 1200, height: 1600), fit: fit)
        XCTAssertEqual(try XCTUnwrap(tiny.first).outerRadius, TeachingRings.minimumRingRadius + 9, accuracy: 1e-9)
        XCTAssertTrue(TeachingRings.targets(truth: truth(), radiusPixels: 18, pixelSize: .zero, fit: fit).isEmpty)
    }

    // MARK: - Copy

    func testNoLineCountsOrGrades() {
        var all: [String] = [TeachingCheck.caption.replacingOccurrences(of: "±", with: "")]
        for type in LandmarkType.allCases {
            for placement in [TeachingCheck.Placement.inside, .outside, .notPlaced] {
                all.append(TeachingCheck.line(type, placement))
            }
        }
        XCTAssertEqual(Set(all.dropFirst()).count, 18)
        for line in all.dropFirst() {
            XCTAssertNil(line.rangeOfCharacter(from: .decimalDigits), line)
        }
        for line in all {
            let lower = line.lowercased()
            for banned in ["correct", "score", "grade", "accura", "good", "bad", "better", "worse", "%"] {
                XCTAssertFalse(lower.contains(banned), "\(banned) in: \(line)")
            }
        }
    }
}
