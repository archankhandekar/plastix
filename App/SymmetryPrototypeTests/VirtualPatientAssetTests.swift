import XCTest
import UIKit
import SymmetryCore
@testable import SymmetryPrototype

/// Checks the bundled virtual-patient renders and their ground truth (made by
/// scripts/virtual-patient). Reads the JSON with JSONSerialization only, so these tests
/// do not depend on the app's own decoder. Bundle.main is the host app.
final class VirtualPatientAssetTests: XCTestCase {
    private let subdirectory = "VirtualPatient"
    private let imageWidth = 1200.0
    private let imageHeight = 1600.0
    private let sigma = 0.015
    private let views = ["frontal", "leftOblique", "rightOblique"]
    private let metricKeys = ["verticalNippleDifference", "leftNippleToMidline", "rightNippleToMidline",
                              "nippleToMidlineDifference", "imfHeightDifference", "contourOverlap"]

    // MARK: - Loading

    private func url(_ name: String) -> URL? {
        let ns = name as NSString
        return Bundle.main.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension, subdirectory: subdirectory)
    }

    private func root() throws -> [String: Any] {
        let u = try XCTUnwrap(url("ground-truth.json"), "ground-truth.json is not in the VirtualPatient folder")
        let data = try Data(contentsOf: u)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func stages() throws -> [[String: Any]] {
        try XCTUnwrap(try root()["stages"] as? [[String: Any]])
    }

    private func view(_ stage: [String: Any], _ name: String) throws -> [String: Any] {
        let views = try XCTUnwrap(stage["views"] as? [String: Any])
        return try XCTUnwrap(views[name] as? [String: Any], "missing view \(name)")
    }

    private func point(_ any: Any?) -> Point2D? {
        guard let a = any as? [Double], a.count == 2 else { return nil }
        return Point2D(x: a[0], y: a[1])
    }

    private func contour(_ v: [String: Any], _ key: String) throws -> [Point2D] {
        let raw = try XCTUnwrap(v[key] as? [Any], "missing \(key)")
        return try raw.map { try XCTUnwrap(point($0), "bad point in \(key)") }
    }

    private func landmarks(_ v: [String: Any]) throws -> [LandmarkType: Point2D] {
        let raw = try XCTUnwrap(v["landmarks"] as? [String: Any])
        var out: [LandmarkType: Point2D] = [:]
        for (k, value) in raw {
            let type = try XCTUnwrap(LandmarkType(rawValue: k), "unknown landmark \(k)")
            out[type] = try XCTUnwrap(point(value), "bad point for \(k)")
        }
        return out
    }

    private func frontalSet(_ stage: [String: Any]) throws -> LandmarkSet {
        let v = try view(stage, "frontal")
        return LandmarkSet(points: try landmarks(v), leftContour: try contour(v, "leftContour"),
                           rightContour: try contour(v, "rightContour"), imageSize: Point2D(x: imageWidth, y: imageHeight))
    }

    private func metrics(_ stage: [String: Any]) throws -> FrontalMetrics {
        FrontalMetricsCalculator.compute(try frontalSet(stage), landmarkSigmaRatio: sigma)
    }

    private func imageNames(_ stage: [String: Any]) throws -> [(name: String, blurred: Bool)] {
        var out: [(name: String, blurred: Bool)] = []
        for name in views {
            let v = try view(stage, name)
            out.append((name: try XCTUnwrap(v["image"] as? String), blurred: false))
            if let b = v["blurredImage"] as? String { out.append((name: b, blurred: true)) }
        }
        return out
    }

    // MARK: - Tests

    func testSchemaHeaderAndStageKeys() throws {
        let r = try root()
        XCTAssertEqual(r["version"] as? Int, 1)
        XCTAssertEqual(r["imageSize"] as? [Int], [1200, 1600])
        XCTAssertEqual(r["midlineBottom"] as? String, "umbilicus")
        XCTAssertEqual(r["sigmaRatio"] as? Double, sigma)
        let s = try stages()
        XCTAssertEqual(s.compactMap { $0["stage"] as? String },
                       ["preoperativeMarking", "afterResection", "afterFatGrafting", "afterClosure"])
        XCTAssertEqual(s.compactMap { $0["index"] as? Int }, [1, 2, 3, 4])
        for stage in s {
            XCTAssertNotNil(try view(stage, "frontal")["blurredImage"] as? String)
            let visible = try XCTUnwrap(try view(stage, "frontal")["visible"] as? [String: Bool])
            XCTAssertEqual(Set(visible.keys), Set(LandmarkType.allCases.map(\.rawValue)))
        }
    }

    func testEveryNamedImageExists() throws {
        for stage in try stages() {
            for (name, _) in try imageNames(stage) {
                XCTAssertNotNil(url(name), "\(name) is not in the VirtualPatient folder")
            }
        }
    }

    func testEveryPointLiesInsideTheImage() throws {
        let xs = 0...imageWidth, ys = 0...imageHeight
        for stage in try stages() {
            for name in views {
                let v = try view(stage, name)
                let pts = Array(try landmarks(v).values) + (try contour(v, "leftContour")) + (try contour(v, "rightContour"))
                for p in pts {
                    XCTAssertTrue(xs.contains(p.x) && ys.contains(p.y), "\(name) point \(p) is outside the image")
                }
            }
        }
    }

    func testFrontalPatientLeftIsOnTheImageRight() throws {
        for stage in try stages() {
            let lm = try landmarks(try view(stage, "frontal"))
            XCTAssertEqual(Set(lm.keys), Set(LandmarkType.allCases))
            XCTAssertGreaterThan(try XCTUnwrap(lm[.leftNipple]).x, try XCTUnwrap(lm[.rightNipple]).x)
            XCTAssertGreaterThan(try XCTUnwrap(lm[.leftIMF]).x, try XCTUnwrap(lm[.rightIMF]).x)
        }
    }

    func testFrontalContoursHave48PointsAndObliquesNone() throws {
        for stage in try stages() {
            let f = try view(stage, "frontal")
            XCTAssertEqual(try contour(f, "leftContour").count, 48)
            XCTAssertEqual(try contour(f, "rightContour").count, 48)
            for name in ["leftOblique", "rightOblique"] {
                let v = try view(stage, name)
                XCTAssertTrue(try contour(v, "leftContour").isEmpty)
                XCTAssertTrue(try contour(v, "rightContour").isEmpty)
            }
        }
    }

    func testRecomputedMetricsMatchSelfCheck() throws {
        for stage in try stages() {
            let m = try metrics(stage)
            let check = try XCTUnwrap(stage["selfCheck"] as? [String: [Double]])
            let computed: [String: MetricValue?] = [
                "verticalNippleDifference": m.verticalNippleDifference,
                "leftNippleToMidline": m.leftNippleToMidline,
                "rightNippleToMidline": m.rightNippleToMidline,
                "nippleToMidlineDifference": m.nippleToMidlineDifference,
                "imfHeightDifference": m.imfHeightDifference,
                "contourOverlap": m.contourOverlap,
            ]
            for key in metricKeys {
                let expected = try XCTUnwrap(check[key], "selfCheck has no \(key)")
                let value = try XCTUnwrap(computed[key] ?? nil, "\(key) was not computed")
                XCTAssertEqual(expected.count, 2)
                XCTAssertEqual(value.value, expected[0], accuracy: 1e-9, key)
                XCTAssertEqual(value.uncertainty, expected[1], accuracy: 1e-9, key)
            }
        }
    }

    func testStageSignPattern() throws {
        let s = try stages()
        XCTAssertEqual(s.count, 4)
        let m = try s.map { try metrics($0) }
        let u = sigma * 2.0.squareRoot()
        func v(_ i: Int, _ k: KeyPath<FrontalMetrics, MetricValue?>) throws -> MetricValue { try XCTUnwrap(m[i][keyPath: k]) }
        let vert = \FrontalMetrics.verticalNippleDifference
        let mid = \FrontalMetrics.nippleToMidlineDifference
        let fold = \FrontalMetrics.imfHeightDifference

        XCTAssertGreaterThan(try v(0, vert).value, u)
        XCTAssertGreaterThan(try v(0, mid).value, u)
        XCTAssertGreaterThan(try v(0, fold).value, u)

        XCTAssertLessThan(try v(1, vert).value, -u)
        XCTAssertLessThanOrEqual(abs(try v(1, mid).value), u)
        XCTAssertLessThanOrEqual(abs(try v(1, fold).value), u)

        XCTAssertLessThanOrEqual(abs(try v(2, vert).value), u)
        XCTAssertLessThan(try v(2, mid).value, -u)
        XCTAssertGreaterThan(try v(2, fold).value, u)

        for k in [vert, mid, fold] {
            let a = try v(2, k), b = try v(3, k)
            let tol = (a.uncertainty * a.uncertainty + b.uncertainty * b.uncertainty).squareRoot()
            XCTAssertLessThanOrEqual(abs(a.value - b.value), tol)
        }
        let o3 = try v(2, \.contourOverlap), o4 = try v(3, \.contourOverlap)
        XCTAssertLessThanOrEqual(abs(o3.value - o4.value), 0.03)
    }

    func testAppQualityGatePassesSharpAndFlagsBlurred() throws {
        for stage in try stages() {
            for (name, blurred) in try imageNames(stage) {
                let data = try Data(contentsOf: try XCTUnwrap(url(name)))
                let processed = try XCTUnwrap(ImageBridge.process(data, tiltDegrees: nil, thresholds: QualityThresholds()),
                                              "\(name) did not decode")
                XCTAssertEqual(processed.width, 1200, name)
                XCTAssertEqual(processed.height, 1600, name)
                if blurred {
                    XCTAssertTrue(processed.quality.failures.contains(.blurry), "\(name) should read as blurred")
                } else {
                    XCTAssertTrue(processed.quality.passed, "\(name) failed: \(processed.quality.failures)")
                }
            }
        }
    }

    func testStageCameraRollIsRecordedForTheLevelReadout() throws {
        // Set 4 is rendered with the camera rolled 4 degrees. Ground truth records the roll
        // a level sensor would have reported (MotionLevelService convention), so the app can
        // report it instead of calling a leaning photo level.
        let expected: [Int: (roll: Double, level: Double)] = [1: (0, 0), 2: (0, 0), 3: (0, 0), 4: (4, -4)]
        for stage in try stages() {
            let index = try XCTUnwrap(stage["index"] as? Int)
            let camera = try XCTUnwrap(stage["camera"] as? [String: Any])
            let want = try XCTUnwrap(expected[index])
            XCTAssertEqual(try XCTUnwrap(camera["rollDegrees"] as? Double), want.roll, "stage \(index)")
            XCTAssertEqual(try XCTUnwrap(camera["levelRollDegrees"] as? Double), want.level, "stage \(index)")
        }
    }

    func testClosureLinesFollowTheStageStory() throws {
        // Set 1 is preoperative (pen marks, no incision); every later set carries the closed
        // incision on the patient-left breast.
        for stage in try stages() {
            let index = try XCTUnwrap(stage["index"] as? Int)
            let params = try XCTUnwrap(stage["params"] as? [String: Any])
            XCTAssertEqual(params["penMarks"] as? Bool, index == 1, "stage \(index)")
            XCTAssertEqual(params["closureLines"] as? Bool, index > 1, "stage \(index)")
        }
    }

    func testBackdropIsNeutralCharcoal() throws {
        // The construction lines are blue and the marks violet, so the backdrop must be a
        // neutral charcoal (#23292D), not a teal that swallows them. The top corners of every
        // render are backdrop.
        for stage in try stages() {
            for (name, _) in try imageNames(stage) {
                let data = try Data(contentsOf: try XCTUnwrap(url(name)))
                let image = try XCTUnwrap(UIImage(data: data)?.cgImage, name)
                for corner in [CGRect(x: 8, y: 8, width: 32, height: 32), CGRect(x: 1160, y: 8, width: 32, height: 32)] {
                    let mean = try meanRGB(image, corner)
                    XCTAssertEqual(mean.r, 0x23, accuracy: 8, "\(name) red")
                    XCTAssertEqual(mean.g, 0x29, accuracy: 8, "\(name) green")
                    XCTAssertEqual(mean.b, 0x2D, accuracy: 8, "\(name) blue")
                }
            }
        }
    }

    /// Mean sRGB of a rectangle (top-left origin) of the image, 0 to 255 per channel.
    private func meanRGB(_ image: CGImage, _ rect: CGRect) throws -> (r: Double, g: Double, b: Double) {
        let w = Int(rect.width), h = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buf in
            let ctx = try XCTUnwrap(CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // CoreGraphics puts y = 0 at the bottom: shift the image so the rect lands at the origin.
            ctx.draw(image, in: CGRect(x: -rect.minX, y: rect.maxY - CGFloat(image.height),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(w * h) { r += Double(bytes[i * 4]); g += Double(bytes[i * 4 + 1]); b += Double(bytes[i * 4 + 2]) }
        let n = Double(w * h)
        return (r / n, g / n, b / n)
    }

    func testFolderIsUnderSizeLimit() throws {
        let folder = try XCTUnwrap(Bundle.main.url(forResource: subdirectory, withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertEqual(files.filter { $0.pathExtension == "jpg" }.count, 16)
        let total = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThan(total, 4_500_000)
    }
}
