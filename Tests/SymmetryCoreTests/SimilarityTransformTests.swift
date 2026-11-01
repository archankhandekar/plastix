import XCTest
@testable import SymmetryCore

final class SimilarityTransformTests: XCTestCase {
    private let source: [Point2D] = [
        Point2D(x: 500, y: 200), Point2D(x: 500, y: 700), Point2D(x: 650, y: 450),
        Point2D(x: 350, y: 450), Point2D(x: 660, y: 560), Point2D(x: 340, y: 560),
    ]

    func testFitRecoversKnownSimilarity() throws {
        let truth = SimilarityTransform(scale: 1.3, rotation: 0.2, translation: Point2D(x: 10, y: -5))
        let target = source.map(truth.apply)
        let fit = try XCTUnwrap(SimilarityTransform.fit(from: source, to: target))
        XCTAssertEqual(fit.scale, 1.3, accuracy: 1e-6)
        XCTAssertEqual(fit.rotation, 0.2, accuracy: 1e-6)
        XCTAssertEqual(fit.translation.x, 10, accuracy: 1e-6)
        XCTAssertEqual(fit.translation.y, -5, accuracy: 1e-6)
        for (s, t) in zip(source, target) {
            XCTAssertEqual(fit.apply(s).distance(to: t), 0, accuracy: 1e-6)
        }
    }

    func testFitNeedsAtLeastTwoDistinctPoints() {
        XCTAssertNil(SimilarityTransform.fit(from: [Point2D(x: 1, y: 1)], to: [Point2D(x: 2, y: 2)]))
        XCTAssertNil(SimilarityTransform.fit(from: [Point2D(x: 1, y: 1), Point2D(x: 1, y: 1)], to: [Point2D(x: 2, y: 2), Point2D(x: 3, y: 3)]))
        XCTAssertNil(SimilarityTransform.fit(from: source, to: Array(source.dropLast())))
    }

    func testInverseUndoesTransform() {
        let t = SimilarityTransform(scale: 0.8, rotation: -0.7, translation: Point2D(x: -30, y: 12))
        let p = Point2D(x: 123, y: 456)
        let back = t.inverse.apply(t.apply(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
    }

    func testRegistrationOfIdenticalSetsIsReliableWithZeroResidual() throws {
        let s = FrontalMetricsTests.symmetricSet()
        let r = try XCTUnwrap(Registration.register(s, to: s))
        XCTAssertEqual(r.rmsResidualRatio, 0, accuracy: 1e-9)
        XCTAssertTrue(r.isReliable)
    }

    func testRegistrationOfRigidlyMovedSetIsReliable() throws {
        let base = FrontalMetricsTests.symmetricSet()
        let moved = FrontalMetricsTests.rotated(base, by: 0.3, about: Point2D(x: 100, y: 100))
        let r = try XCTUnwrap(Registration.register(moved, to: base))
        XCTAssertEqual(r.rmsResidualRatio, 0, accuracy: 1e-9)
        XCTAssertTrue(r.isReliable)
        XCTAssertEqual(r.transform.rotation, -0.3, accuracy: 1e-9)
    }

    func testRegistrationWithDisplacedLandmarkIsUnreliable() throws {
        let base = FrontalMetricsTests.symmetricSet()
        var current = base
        current[.leftNipple] = Point2D(x: 650, y: 650) // moved 200 px = 0.4 L
        let r = try XCTUnwrap(Registration.register(current, to: base))
        XCTAssertGreaterThan(r.rmsResidualRatio, 0.05)
        XCTAssertFalse(r.isReliable)
        XCTAssertTrue(Registration.register(current, to: base, maxResidualRatio: 1.0)!.isReliable)
    }

    func testRegistrationUsesOnlySharedLandmarks() throws {
        let base = FrontalMetricsTests.symmetricSet()
        var current = base
        current[.leftIMF] = nil
        let r = try XCTUnwrap(Registration.register(current, to: base))
        XCTAssertEqual(r.sharedLandmarkCount, 5)
        XCTAssertTrue(r.isReliable)
    }

    func testRegistrationNeedsMidlineAndAtLeastThreeSharedLandmarks() {
        let base = FrontalMetricsTests.symmetricSet()
        var sparse = LandmarkSet(imageSize: base.imageSize)
        sparse[.sternalNotch] = base[.sternalNotch]
        sparse[.midlineBottom] = base[.midlineBottom]
        XCTAssertNil(Registration.register(sparse, to: base))
        var noMidline = base
        noMidline[.midlineBottom] = nil
        XCTAssertNil(Registration.register(noMidline, to: base))
    }
}
