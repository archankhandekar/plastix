import UIKit
import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// The practice camera over the fixture patient, with injected image bytes: each file name
/// maps to its own UTF-8 bytes, so a capture says exactly which render it returned.
@MainActor
final class VirtualCameraSourceTests: XCTestCase {
    private let patient = DemoFixture.patient(stages: 4)

    nonisolated private static func bytes(_ name: String) -> Data { Data(name.utf8) }

    private func makeSource(setIndex: Int, angle: ViewAngle = .frontal,
                            imageData: @escaping (String) -> Data? = { VirtualCameraSourceTests.bytes($0) }) -> VirtualCameraSource {
        VirtualCameraSource(patient: patient, setIndex: setIndex, angle: angle, imageData: imageData)
    }

    func testStageIndexIsClampedToTheRenderedStages() {
        XCTAssertEqual(makeSource(setIndex: 1).stageIndex, 1)
        XCTAssertEqual(makeSource(setIndex: 3).stageIndex, 3)
        XCTAssertEqual(makeSource(setIndex: 4).stageIndex, 4)
        XCTAssertEqual(makeSource(setIndex: 5).stageIndex, 4)
        XCTAssertEqual(makeSource(setIndex: 9).stageIndex, 4)
        XCTAssertEqual(makeSource(setIndex: 0).stageIndex, 1)
    }

    func testUsesLastStageOnlyPastTheLastRender() {
        XCTAssertFalse(makeSource(setIndex: 1).usesLastStage)
        XCTAssertFalse(makeSource(setIndex: 4).usesLastStage)
        XCTAssertTrue(makeSource(setIndex: 5).usesLastStage)
        XCTAssertTrue(makeSource(setIndex: 7).usesLastStage)

        let twoStages = VirtualCameraSource(patient: DemoFixture.patient(stages: 2), setIndex: 3, angle: .frontal,
                                            imageData: { VirtualCameraSourceTests.bytes($0) })
        XCTAssertEqual(twoStages.stageIndex, 2)
        XCTAssertTrue(twoStages.usesLastStage)
    }

    func testDriftIsZeroWhenStatic() {
        for t in stride(from: 0.0, through: 60, by: 0.37) {
            let d = VirtualCameraSource.drift(at: t, staticMotion: true)
            XCTAssertEqual(d.offset, .zero)
            XCTAssertEqual(d.rollDegrees, 0)
        }
    }

    func testDriftIsBoundedAndMoves() {
        var maxX = 0.0, maxY = 0.0, maxRoll = 0.0
        for t in stride(from: 0.0, through: 154, by: 0.05) {
            let d = VirtualCameraSource.drift(at: t, staticMotion: false)
            XCTAssertLessThanOrEqual(abs(d.offset.width), 6 + 1e-9)
            XCTAssertLessThanOrEqual(abs(d.offset.height), 4 + 1e-9)
            XCTAssertLessThanOrEqual(abs(d.rollDegrees), 1.5 + 1e-9)
            maxX = max(maxX, abs(d.offset.width))
            maxY = max(maxY, abs(d.offset.height))
            maxRoll = max(maxRoll, abs(d.rollDegrees))
        }
        // It really drifts: close to each bound somewhere in two full periods.
        XCTAssertGreaterThan(maxX, 5.9)
        XCTAssertGreaterThan(maxY, 3.9)
        XCTAssertGreaterThan(maxRoll, 1.49)

        // The defined sinusoids at a sample time.
        let d = VirtualCameraSource.drift(at: 2, staticMotion: false)
        XCTAssertEqual(d.offset.width, 6 * sin(2 * Double.pi * 2 / 7), accuracy: 1e-9)
        XCTAssertEqual(d.offset.height, 4 * sin(2 * Double.pi * 2 / 11), accuracy: 1e-9)
        XCTAssertEqual(d.rollDegrees, 1.5 * sin(2 * Double.pi * 2 / 11 + 1), accuracy: 1e-9)
    }

    func testSharpCaptureReturnsTheRenderAndTheDriftRoll() throws {
        let source = makeSource(setIndex: 2)
        let shot = try source.capture(at: 3, staticMotion: false)
        XCTAssertEqual(shot.data, Self.bytes("vp-s2-frontal.jpg"))
        XCTAssertEqual(shot.tiltDegrees, VirtualCameraSource.drift(at: 3, staticMotion: false).rollDegrees, accuracy: 1e-12)
        XCTAssertEqual(shot.key, DemoAssetKey(stageIndex: 2, angle: .frontal, variant: .sharp))

        let still = try source.capture(at: 3, staticMotion: true)
        XCTAssertEqual(still.tiltDegrees, 0)
    }

    func testPracticeRetakeReturnsTheBlurredFrontalOnceThenResets() throws {
        let source = makeSource(setIndex: 1)
        source.practiceRetake = true

        let blurred = try source.capture(at: 5, staticMotion: false)
        XCTAssertEqual(blurred.data, Self.bytes("vp-s1-frontal-blurred.jpg"))
        XCTAssertEqual(blurred.tiltDegrees, 9)
        XCTAssertEqual(blurred.tiltDegrees, VirtualCameraSource.retakeTiltDegrees)
        XCTAssertEqual(blurred.key, DemoAssetKey(stageIndex: 1, angle: .frontal, variant: .blurred))
        XCTAssertFalse(source.practiceRetake)

        let next = try source.capture(at: 5, staticMotion: true)
        XCTAssertEqual(next.data, Self.bytes("vp-s1-frontal.jpg"))
        XCTAssertEqual(next.tiltDegrees, 0)
        XCTAssertEqual(next.key.variant, .sharp)
    }

    func testObliquesStaySharpWithPracticeRetakeOn() throws {
        let source = makeSource(setIndex: 3, angle: .leftOblique)
        source.practiceRetake = true

        let left = try source.capture(at: 1, staticMotion: true)
        XCTAssertEqual(left.data, Self.bytes("vp-s3-leftOblique.jpg"))
        XCTAssertEqual(left.key, DemoAssetKey(stageIndex: 3, angle: .leftOblique, variant: .sharp))
        XCTAssertEqual(left.tiltDegrees, 0)
        XCTAssertTrue(source.practiceRetake, "an oblique leaves the switch on for the next frontal")

        source.angle = .rightOblique
        let right = try source.capture(at: 1, staticMotion: true)
        XCTAssertEqual(right.data, Self.bytes("vp-s3-rightOblique.jpg"))
        XCTAssertEqual(right.key, DemoAssetKey(stageIndex: 3, angle: .rightOblique, variant: .sharp))
        XCTAssertTrue(source.practiceRetake)

        source.angle = .frontal
        let frontal = try source.capture(at: 1, staticMotion: true)
        XCTAssertEqual(frontal.key, DemoAssetKey(stageIndex: 3, angle: .frontal, variant: .blurred))
        XCTAssertFalse(source.practiceRetake)
    }

    func testAssetKeysPastTheLastStageUseTheLastRender() throws {
        let source = makeSource(setIndex: 6)
        for angle in ViewAngle.allCases {
            source.angle = angle
            let shot = try source.capture(at: 0, staticMotion: true)
            XCTAssertEqual(shot.key, DemoAssetKey(stageIndex: 4, angle: angle, variant: .sharp))
            XCTAssertEqual(shot.data, Self.bytes("vp-s4-\(angle.rawValue).jpg"))
        }
    }

    func testMissingBytesThrow() {
        let source = makeSource(setIndex: 1, imageData: { _ in nil })
        XCTAssertThrowsError(try source.capture(at: 0, staticMotion: true))
        source.practiceRetake = true
        XCTAssertThrowsError(try source.capture(at: 0, staticMotion: true))
        XCTAssertNil(source.previewImage)
    }

    func testPreviewImageIsTheSharpRenderAndIsCached() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 16), format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 16))
        }.pngData()!
        var requested: [String] = []
        let source = makeSource(setIndex: 2, angle: .rightOblique, imageData: { name in
            requested.append(name)
            return png
        })
        source.practiceRetake = true
        let first = try XCTUnwrap(source.previewImage)
        let second = try XCTUnwrap(source.previewImage)
        XCTAssertTrue(first === second)
        XCTAssertEqual(requested, ["vp-s2-rightOblique.jpg"])

        source.angle = .frontal
        XCTAssertNotNil(source.previewImage)
        // The viewfinder always shows the sharp render, even with the retake switch on.
        XCTAssertEqual(requested, ["vp-s2-rightOblique.jpg", "vp-s2-frontal.jpg"])
    }
}
