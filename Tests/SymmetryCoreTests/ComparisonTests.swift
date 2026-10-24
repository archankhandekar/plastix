import XCTest
@testable import SymmetryCore

final class ComparisonTests: XCTestCase {
    func testDeltaCombinesUncertaintyInQuadrature() throws {
        let a = Measurement(value: 0.10, uncertainty: 0.03, unit: .ratioOfReference)
        let b = Measurement(value: 0.04, uncertainty: 0.04, unit: .ratioOfReference)
        let d = try XCTUnwrap(a.subtracting(b))
        XCTAssertEqual(d.value, 0.06, accuracy: 1e-12)
        XCTAssertEqual(d.uncertainty, 0.05, accuracy: 1e-12)
        XCTAssertNil(a.subtracting(Measurement(value: 1, uncertainty: 0, unit: .pixels)))
    }

    func testComparisonReportsDeltaPerMetric() throws {
        let base = FrontalMetricsTests.symmetricSet()
        var cur = base
        cur[.leftNipple] = Point2D(x: 650, y: 500) // vertical difference becomes 0.1
        let bm = FrontalMetricsCalculator.compute(base)
        let cm = FrontalMetricsCalculator.compute(cur)
        let reg = Registration.register(cur, to: base)
        let result = Comparator.compare(baseline: bm, current: cm, registration: reg, angle: .frontal)
        XCTAssertEqual(result.angle, .frontal)
        let vertical = try XCTUnwrap(result.deltas.first { $0.name == "Vertical nipple difference" })
        XCTAssertEqual(try XCTUnwrap(vertical.delta).value, 0.1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(vertical.delta).uncertainty, 0.015 * 2, accuracy: 1e-9)
        XCTAssertEqual(result.deltas.count, bm.namedMetrics.count)
    }

    func testNilMetricOnEitherSideGivesNilDelta() throws {
        let base = FrontalMetricsTests.symmetricSet()
        var cur = base
        cur[.leftIMF] = nil
        let result = Comparator.compare(baseline: FrontalMetricsCalculator.compute(base),
                                        current: FrontalMetricsCalculator.compute(cur),
                                        registration: Registration.register(cur, to: base), angle: .frontal)
        let imf = try XCTUnwrap(result.deltas.first { $0.name == "Inframammary fold height difference" })
        XCTAssertNotNil(imf.baseline)
        XCTAssertNil(imf.current)
        XCTAssertNil(imf.delta)
        XCTAssertTrue(result.flags.contains(.missingLandmarks))
    }

    func testUnreliableRegistrationIsFlagged() throws {
        let base = FrontalMetricsTests.symmetricSet()
        var cur = base
        cur[.leftNipple] = Point2D(x: 650, y: 650)
        let reg = Registration.register(cur, to: base)
        let result = Comparator.compare(baseline: FrontalMetricsCalculator.compute(base),
                                        current: FrontalMetricsCalculator.compute(cur),
                                        registration: reg, angle: .frontal)
        XCTAssertTrue(result.flags.contains(.registrationResidualHigh))
        XCTAssertEqual(result.registration?.isReliable, false)
        XCTAssertFalse(result.isReliable)
    }

    func testMissingRegistrationIsFlagged() {
        let m = FrontalMetricsCalculator.compute(FrontalMetricsTests.symmetricSet())
        let result = Comparator.compare(baseline: m, current: m, registration: nil, angle: .frontal)
        XCTAssertTrue(result.flags.contains(.registrationResidualHigh))
        XCTAssertNil(result.registration)
    }

    func testExtraFlagsFromCapturesAreUnioned() {
        let m = FrontalMetricsCalculator.compute(FrontalMetricsTests.symmetricSet())
        let s = FrontalMetricsTests.symmetricSet()
        let result = Comparator.compare(baseline: m, current: m, registration: Registration.register(s, to: s),
                                        angle: .frontal, captureFlags: [.lowImageQuality, .qualityOverridden, .lowImageQuality])
        XCTAssertEqual(result.flags.filter { $0 == .lowImageQuality }.count, 1)
        XCTAssertTrue(result.flags.contains(.qualityOverridden))
        XCTAssertTrue(result.isReliable == false)
    }

    func testComparisonResultRoundTripsThroughJSON() throws {
        let m = FrontalMetricsCalculator.compute(FrontalMetricsTests.symmetricSet())
        let s = FrontalMetricsTests.symmetricSet()
        let result = Comparator.compare(baseline: m, current: m, registration: Registration.register(s, to: s), angle: .frontal)
        let back = try JSONDecoder().decode(CaptureComparison.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(back, result)
    }
}
