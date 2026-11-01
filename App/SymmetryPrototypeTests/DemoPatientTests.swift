import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// Builds ground-truth.json fixtures in the virtual_patient schema. Shared with PracticeStoreTests.
enum DemoFixture {
    static let stageKeys = ["preoperativeMarking", "afterResection", "afterFatGrafting", "afterClosure"]

    /// A 48-point-like outline around (cx, cy), as JSON number pairs.
    static func contour(cx: Double, cy: Double, r: Double, n: Int = 16) -> [[Double]] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * Double.pi
            return [cx + r * cos(a), cy + r * sin(a)]
        }
    }

    static func stage(_ index: Int) -> [String: Any] {
        let dy = Double(index) * 10
        let frontal: [String: Any] = [
            "image": "vp-s\(index)-frontal.jpg",
            "blurredImage": "vp-s\(index)-frontal-blurred.jpg",
            "landmarks": [
                "sternalNotch": [600, 400],
                "midlineBottom": [600, 1000],
                "leftNipple": [760, 700 + dy],
                "rightNipple": [440, 690],
                "leftIMF": [750, 820 + dy],
                "rightIMF": [450, 810],
            ],
            "visible": ["sternalNotch": true, "midlineBottom": true, "leftNipple": true,
                        "rightNipple": true, "leftIMF": true, "rightIMF": true],
            "leftContour": contour(cx: 760, cy: 720, r: 90),
            "rightContour": contour(cx: 440, cy: 715, r: 88),
        ]
        let leftOblique: [String: Any] = [
            "image": "vp-s\(index)-leftOblique.jpg",
            "landmarks": ["sternalNotch": [520, 410], "leftNipple": [800, 700]],
            "visible": ["sternalNotch": true, "midlineBottom": false, "leftNipple": true,
                        "rightNipple": false, "leftIMF": false, "rightIMF": false],
            "leftContour": [] as [[Double]],
            "rightContour": [] as [[Double]],
        ]
        let rightOblique: [String: Any] = [
            "image": "vp-s\(index)-rightOblique.jpg",
            "landmarks": ["sternalNotch": [680, 410], "rightNipple": [400, 690]],
            "visible": ["sternalNotch": true, "midlineBottom": false, "leftNipple": false,
                        "rightNipple": true, "leftIMF": false, "rightIMF": false],
            "leftContour": [] as [[Double]],
            "rightContour": [] as [[Double]],
        ]
        return [
            "index": index,
            "stage": stageKeys[(index - 1) % stageKeys.count],
            "positioning": ["tableAngle": "0°", "armPosition": "at sides", "lighting": "overhead lights", "note": "Virtual patient"],
            "camera": ["rollDegrees": 0, "radiusMetres": 1.22, "yFovDegrees": 40],
            "params": ["penMarks": index == 1],
            "views": ["frontal": frontal, "leftOblique": leftOblique, "rightOblique": rightOblique],
            "selfCheck": ["verticalNippleDifference": [dy / 600, 0.021], "contourOverlap": [0.8, 0.01]],
            "quality": ["frontal": ["blurScore": 120, "highlight": 0.0, "shadow": 0.0]],
        ]
    }

    static func json(stages: Int) -> Data {
        let root: [String: Any] = [
            "version": 1,
            "generator": "scripts/virtual-patient render",
            "seed": 20261031,
            "imageSize": [1200, 1600],
            "midlineBottom": "umbilicus",
            "sigmaRatio": 0.015,
            "stages": (1...stages).map(stage),
        ]
        return try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    static func patient(stages: Int) -> DemoPatient {
        try! DemoPatient.decode(json(stages: stages))
    }
}

final class DemoPatientTests: XCTestCase {
    func testDecodesTheSchema() throws {
        let p = try DemoPatient.decode(DemoFixture.json(stages: 2))
        XCTAssertEqual(p.version, 1)
        XCTAssertEqual(p.imageSize, Point2D(x: 1200, y: 1600))
        XCTAssertEqual(p.sigmaRatio, 0.015)
        XCTAssertEqual(p.stageCount, 2)
        XCTAssertEqual(p.stages.map(\.index), [1, 2])
        XCTAssertEqual(DemoPatient.subdirectory, "VirtualPatient")

        let s1 = try XCTUnwrap(p.stage(1))
        XCTAssertEqual(s1.stageKey, "preoperativeMarking")
        XCTAssertEqual(s1.operativeStage, .preoperativeMarking)
        XCTAssertEqual(p.stage(2)?.operativeStage, .afterResection)
        XCTAssertNil(p.stage(3))
        XCTAssertEqual(s1.positioning, Positioning(tableAngle: "0°", armPosition: "at sides",
                                                   lighting: "overhead lights", note: "Virtual patient"))
        XCTAssertEqual(Set(s1.views.keys), Set(ViewAngle.allCases))
        XCTAssertEqual(s1.selfCheck["verticalNippleDifference"], [10.0 / 600, 0.021])
    }

    func testViewPointsVisibleAndContours() throws {
        let p = DemoFixture.patient(stages: 2)
        let frontal = try XCTUnwrap(p.view(stage: 2, angle: .frontal))
        XCTAssertEqual(frontal.image, "vp-s2-frontal.jpg")
        XCTAssertEqual(frontal.blurredImage, "vp-s2-frontal-blurred.jpg")
        XCTAssertEqual(frontal.landmarks.count, 6)
        XCTAssertEqual(frontal.landmarks[.sternalNotch], Point2D(x: 600, y: 400))
        XCTAssertEqual(frontal.landmarks[.leftNipple], Point2D(x: 760, y: 720))
        XCTAssertEqual(frontal.landmarks[.rightIMF], Point2D(x: 450, y: 810))
        XCTAssertEqual(frontal.visible.count, 6)
        XCTAssertTrue(frontal.visible.values.allSatisfy { $0 })
        XCTAssertEqual(frontal.leftContour.count, 16)
        XCTAssertEqual(frontal.rightContour.count, 16)
        XCTAssertEqual(frontal.leftContour[0].x, 850, accuracy: 1e-9)
        XCTAssertEqual(frontal.leftContour[0].y, 720, accuracy: 1e-9)

        let oblique = try XCTUnwrap(p.view(stage: 1, angle: .leftOblique))
        XCTAssertNil(oblique.blurredImage)
        XCTAssertEqual(Set(oblique.landmarks.keys), [.sternalNotch, .leftNipple])
        XCTAssertEqual(oblique.visible[.midlineBottom], false)
        XCTAssertEqual(oblique.visible[.leftNipple], true)
        XCTAssertTrue(oblique.leftContour.isEmpty)
        XCTAssertNil(p.view(stage: 5, angle: .frontal))
    }

    func testTruthLandmarkSet() throws {
        let p = DemoFixture.patient(stages: 2)
        let truth = try XCTUnwrap(p.truth(stage: 1, angle: .frontal))
        XCTAssertTrue(truth.isComplete)
        XCTAssertEqual(truth.imageSize, Point2D(x: 1200, y: 1600))
        XCTAssertEqual(truth.leftContour.count, 16)
        XCTAssertEqual(truth[.midlineBottom], Point2D(x: 600, y: 1000))
        let metrics = FrontalMetricsCalculator.compute(truth)
        XCTAssertNotNil(metrics.contourOverlap)
        // Left nipple at y 710, right at 690, L = 600 px.
        XCTAssertEqual(metrics.verticalNippleDifference?.value ?? .nan, 20.0 / 600, accuracy: 1e-9)

        let oblique = try XCTUnwrap(p.truth(stage: 1, angle: .rightOblique))
        XCTAssertFalse(oblique.isComplete)
        XCTAssertEqual(oblique.missing, [.midlineBottom, .leftNipple, .leftIMF, .rightIMF])
        XCTAssertNil(p.truth(stage: 9, angle: .frontal))
    }

    func testOperativeStageMapping() throws {
        func stage(_ key: String) throws -> OperativeStage {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoFixture.json(stages: 1)) as? [String: Any])
            var s = DemoFixture.stage(1)
            s["stage"] = key
            root["stages"] = [s]
            let data = try JSONSerialization.data(withJSONObject: root)
            return try XCTUnwrap(DemoPatient.decode(data).stage(1)).operativeStage
        }
        XCTAssertEqual(try stage("preoperativeMarking"), .preoperativeMarking)
        XCTAssertEqual(try stage("afterResection"), .afterResection)
        XCTAssertEqual(try stage("afterImplantOrExpander"), .afterImplantOrExpander)
        XCTAssertEqual(try stage("afterFatGrafting"), .afterFatGrafting)
        XCTAssertEqual(try stage("afterClosure"), .afterClosure)
        XCTAssertEqual(try stage("somethingElse"), .custom("somethingElse"))
    }

    func testRejectsAMalformedPoint() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoFixture.json(stages: 1)) as? [String: Any])
        root["imageSize"] = [1200]
        let data = try JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try DemoPatient.decode(data))
    }

    func testDemoAssetKeyRoundTrips() throws {
        let key = DemoAssetKey(stageIndex: 2, angle: .leftOblique, variant: .blurred)
        let data = try JSONEncoder().encode([UUID().uuidString: key])
        let back = try JSONDecoder().decode([String: DemoAssetKey].self, from: data)
        XCTAssertEqual(back.values.first, key)
    }
}
