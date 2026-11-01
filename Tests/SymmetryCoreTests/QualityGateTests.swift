import XCTest
@testable import SymmetryCore

final class QualityGateTests: XCTestCase {
    private func checkerboard(size: Int, cell: Int) -> LuminanceImage {
        var px = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size { for x in 0..<size {
            px[y * size + x] = ((x / cell + y / cell) % 2 == 0) ? 40 : 215
        } }
        return LuminanceImage(width: size, height: size, pixels: px)
    }

    private func boxBlurred(_ img: LuminanceImage, radius: Int) -> LuminanceImage {
        var out = img.pixels
        for y in 0..<img.height { for x in 0..<img.width {
            var sum = 0, n = 0
            for dy in -radius...radius { for dx in -radius...radius {
                let yy = y + dy, xx = x + dx
                if yy >= 0, yy < img.height, xx >= 0, xx < img.width { sum += Int(img.pixels[yy * img.width + xx]); n += 1 }
            } }
            out[y * img.width + x] = UInt8(sum / n)
        } }
        return LuminanceImage(width: img.width, height: img.height, pixels: out)
    }

    private func uniform(_ v: UInt8, size: Int = 32) -> LuminanceImage {
        LuminanceImage(width: size, height: size, pixels: [UInt8](repeating: v, count: size * size))
    }

    func testSharpImageScoresHigherThanBlurredCopy() {
        let sharp = checkerboard(size: 64, cell: 4)
        let blurred = boxBlurred(sharp, radius: 2)
        let a = QualityGate.evaluate(sharp, tiltDegrees: nil, thresholds: QualityThresholds())
        let b = QualityGate.evaluate(blurred, tiltDegrees: nil, thresholds: QualityThresholds())
        XCTAssertGreaterThan(a.blurScore, b.blurScore * 2)
        XCTAssertFalse(a.failures.contains(.blurry))
    }

    func testUniformBrightImageIsOverexposed() {
        let r = QualityGate.evaluate(uniform(250), tiltDegrees: nil, thresholds: QualityThresholds())
        XCTAssertEqual(r.clippedHighlightFraction, 1.0, accuracy: 1e-9)
        XCTAssertTrue(r.failures.contains(.overexposed))
        XCTAssertFalse(r.passed)
    }

    func testUniformDarkImageIsUnderexposed() {
        let r = QualityGate.evaluate(uniform(3), tiltDegrees: nil, thresholds: QualityThresholds())
        XCTAssertEqual(r.clippedShadowFraction, 1.0, accuracy: 1e-9)
        XCTAssertTrue(r.failures.contains(.underexposed))
    }

    func testMidGreyUniformImageIsBlurryButNotClipped() {
        let r = QualityGate.evaluate(uniform(128), tiltDegrees: nil, thresholds: QualityThresholds())
        XCTAssertEqual(r.blurScore, 0, accuracy: 1e-9)
        XCTAssertTrue(r.failures.contains(.blurry))
        XCTAssertFalse(r.failures.contains(.overexposed))
        XCTAssertFalse(r.failures.contains(.underexposed))
    }

    func testTiltBeyondThresholdFails() {
        let img = checkerboard(size: 64, cell: 4)
        let t = QualityThresholds()
        XCTAssertTrue(QualityGate.evaluate(img, tiltDegrees: 12, thresholds: t).failures.contains(.tilted))
        XCTAssertFalse(QualityGate.evaluate(img, tiltDegrees: 4, thresholds: t).failures.contains(.tilted))
        XCTAssertFalse(QualityGate.evaluate(img, tiltDegrees: nil, thresholds: t).failures.contains(.tilted))
        XCTAssertNil(QualityGate.evaluate(img, tiltDegrees: nil, thresholds: t).tiltDegrees)
    }

    func testCustomThresholdsAreHonoured() {
        let img = checkerboard(size: 64, cell: 4)
        var t = QualityThresholds()
        t.maxTiltDegrees = 15
        XCTAssertFalse(QualityGate.evaluate(img, tiltDegrees: 12, thresholds: t).failures.contains(.tilted))
        t.minBlurScore = 1e9
        XCTAssertTrue(QualityGate.evaluate(img, tiltDegrees: 0, thresholds: t).failures.contains(.blurry))
    }

    func testTinyImagesDoNotCrash() {
        let one = LuminanceImage(width: 1, height: 1, pixels: [100])
        let r = QualityGate.evaluate(one, tiltDegrees: nil, thresholds: QualityThresholds())
        XCTAssertEqual(r.blurScore, 0)
        let empty = LuminanceImage(width: 0, height: 0, pixels: [])
        XCTAssertFalse(QualityGate.evaluate(empty, tiltDegrees: nil, thresholds: QualityThresholds()).passed)
    }

    func testReportRoundTripsThroughJSON() throws {
        let r = QualityGate.evaluate(uniform(250), tiltDegrees: 9.5, thresholds: QualityThresholds())
        let back = try JSONDecoder().decode(QualityReport.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}
