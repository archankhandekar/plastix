import UIKit
import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// The practice store over temporary roots, with the fixture patient and generated JPEGs.
@MainActor
final class PracticeStoreTests: XCTestCase {
    private var roots: [URL] = []
    private let suiteName = "PracticeStoreTests"

    /// A 1200x1600 JPEG of grey noise blocks, made once.
    private static let jpeg: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 1200, height: 1600)
        var state: UInt64 = 12345
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let block: CGFloat = 8
            for y in stride(from: CGFloat(0), to: size.height, by: block) {
                for x in stride(from: CGFloat(0), to: size.width, by: block) {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    let grey = 0.2 + 0.6 * CGFloat(state >> 40) / CGFloat(1 << 24)
                    UIColor(white: grey, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: block, height: block))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.8)!
    }()

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        UIFlags.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        UserDefaults().removePersistentDomain(forName: suiteName)
        UIFlags.defaults = .standard
        super.tearDown()
    }

    private func tempRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PracticeStoreTests-\(UUID().uuidString)", isDirectory: true)
        roots.append(url)
        return url
    }

    private func makeStore(root: URL? = nil, stages: Int = 4) -> PracticeStore {
        PracticeStore(root: root ?? tempRoot(), patient: DemoFixture.patient(stages: stages), imageData: { _ in PracticeStoreTests.jpeg })
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sigma = FrontalMetricsCalculator.defaultLandmarkSigmaRatio

    // MARK: - Roots

    func testDefaultRootIsSeparateFromTheStudyRoot() throws {
        let practice = try PracticeStore.defaultRoot().standardizedFileURL.path
        let study = try SessionRepository.defaultRoot().standardizedFileURL.path
        XCTAssertNotEqual(practice, study)
        XCTAssertFalse(practice.hasPrefix(study + "/"))
        XCTAssertFalse(study.hasPrefix(practice + "/"))
        XCTAssertFalse(practice.hasPrefix(study))
        XCTAssertFalse(study.hasPrefix(practice))
        XCTAssertEqual(URL(fileURLWithPath: practice).lastPathComponent, "Practice")
        XCTAssertEqual(URL(fileURLWithPath: practice).deletingLastPathComponent().path,
                       URL(fileURLWithPath: study).deletingLastPathComponent().path)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: practice, isDirectory: &isDir) && isDir.boolValue)
    }

    // MARK: - Seeding

    func testSeedBuildsTheVirtualPatient() throws {
        let store = makeStore()
        XCTAssertTrue(store.isAvailable)
        XCTAssertNil(store.session)
        let session = try store.seed(now: now)
        XCTAssertEqual(session.studyID, "DEMO-VP1")
        XCTAssertEqual(PracticeStore.studyID, "DEMO-VP1")
        XCTAssertEqual(store.session?.id, session.id)
        XCTAssertEqual(store.store.sessions.count, 1)

        let sets = session.orderedCaptureSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.stage), [.preoperativeMarking, .afterResection, .afterFatGrafting])
        XCTAssertEqual(sets.map(\.createdAt), [now.addingTimeInterval(-160 * 60), now.addingTimeInterval(-120 * 60),
                                               now.addingTimeInterval(-80 * 60)])
        XCTAssertTrue(sets.allSatisfy(\.isComplete))
        XCTAssertEqual(sets[0].positioning.note, "Virtual patient")

        for set in sets.prefix(2) {
            XCTAssertTrue(SessionWizard.isMeasured(set, sigma: sigma))
            let lm = try XCTUnwrap(set.frontal?.landmarks)
            XCTAssertGreaterThanOrEqual(lm.leftContour.count, 8)
            XCTAssertGreaterThanOrEqual(lm.rightContour.count, 8)
            XCTAssertNotNil(set.frontal?.frontalMetrics(sigma: sigma)?.contourOverlap)
            XCTAssertNil(set.captures[.leftOblique]?.landmarks)
        }
        XCTAssertNil(sets[2].frontal?.landmarks)
        XCTAssertFalse(SessionWizard.isMeasured(sets[2], sigma: sigma))

        for capture in sets.flatMap(\.orderedCaptures) {
            XCTAssertNotNil(capture.quality)
            XCTAssertEqual(capture.tiltDegrees, 0.5)
            XCTAssertFalse(capture.qualityOverridden)
            XCTAssertEqual(capture.pixelWidth, 1200)
            XCTAssertEqual(capture.pixelHeight, 1600)
            XCTAssertTrue(capture.imageFilename.hasPrefix(capture.angle.rawValue + "-"))
            XCTAssertTrue(capture.imageFilename.hasSuffix(".jpg"))
            XCTAssertNotNil(store.store.image(for: capture, in: session))
        }

        // The seeded session is reloaded from disk by a fresh store over the same root.
        let reopened = PracticeStore(root: store.root, patient: store.patient, imageData: { _ in nil })
        XCTAssertEqual(reopened.session?.id, session.id)
        XCTAssertEqual(reopened.assetKey(forCaptureID: sets[1].frontal!.id),
                       DemoAssetKey(stageIndex: 2, angle: .frontal, variant: .sharp))
    }

    func testSeedJitterIsCloseToTheTruth() throws {
        let store = makeStore()
        let session = try store.seed(now: now)
        let truth = try XCTUnwrap(store.patient?.truth(stage: 1, angle: .frontal))
        let placed = try XCTUnwrap(session.orderedCaptureSets[0].frontal?.landmarks)
        let L = truth[.sternalNotch]!.distance(to: truth[.midlineBottom]!)
        for type in LandmarkType.allCases {
            let d = placed[type]!.distance(to: truth[type]!)
            XCTAssertLessThan(d, 6 * 0.3 * sigma * L, "\(type)")
        }
        XCTAssertNotEqual(placed.points, truth.points)
        XCTAssertEqual(placed.leftContour.count, truth.leftContour.count)
    }

    func testSeedingIsDeterministicForASeed() throws {
        let store = makeStore()
        let a = try store.seed(now: now, rngSeed: 42).orderedCaptureSets.compactMap { $0.frontal?.landmarks }
        let b = try store.seed(now: now, rngSeed: 42).orderedCaptureSets.compactMap { $0.frontal?.landmarks }
        let c = try store.seed(now: now, rngSeed: 43).orderedCaptureSets.compactMap { $0.frontal?.landmarks }
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(store.store.sessions.count, 1)
    }

    func testTruthLandmarksWithoutJitterIsTheTruth() throws {
        let store = makeStore()
        XCTAssertEqual(store.truthLandmarks(stageIndex: 2, angle: .frontal, jitterSigmaRatio: 0, seed: 1),
                       store.patient?.truth(stage: 2, angle: .frontal))
        let x = store.truthLandmarks(stageIndex: 2, angle: .frontal, jitterSigmaRatio: 0.01, seed: 1)
        let y = store.truthLandmarks(stageIndex: 2, angle: .frontal, jitterSigmaRatio: 0.01, seed: 1)
        XCTAssertEqual(x, y)
        XCTAssertNotEqual(x, store.patient?.truth(stage: 2, angle: .frontal))
        // An oblique has no midline of its own; its jitter uses the frontal L.
        XCTAssertNotNil(store.truthLandmarks(stageIndex: 1, angle: .leftOblique, jitterSigmaRatio: 0.01, seed: 1))
        XCTAssertNil(store.truthLandmarks(stageIndex: 9, angle: .frontal, jitterSigmaRatio: 0, seed: 1))
    }

    func testResetRecreates() throws {
        let store = makeStore()
        let first = try store.seed(now: now)
        let firstCapture = first.orderedCaptureSets[0].frontal!
        UIFlags.markViewed(setID: first.orderedCaptureSets[0].id)
        UIFlags.markOpenedStages(sessionID: first.id)

        let second = try store.reset()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.store.sessions.map(\.id), [second.id])
        XCTAssertEqual(second.orderedCaptureSets.count, 3)
        XCTAssertNil(store.assetKey(forCaptureID: firstCapture.id))
        XCTAssertNil(store.store.image(for: firstCapture, in: first))
        XCTAssertFalse(UIFlags.hasViewed(setID: first.orderedCaptureSets[0].id))
        XCTAssertFalse(UIFlags.hasOpenedStages(sessionID: first.id))
    }

    func testSeedWithoutAPatientThrows() {
        let store = PracticeStore(root: tempRoot(), patient: nil, imageData: { _ in PracticeStoreTests.jpeg })
        XCTAssertFalse(store.isAvailable)
        XCTAssertThrowsError(try store.seed(now: now))
        XCTAssertNil(store.session)
    }

    // MARK: - Asset keys

    func testAssetKeysAreRecorded() throws {
        let store = makeStore()
        let session = try store.seed(now: now)
        for (i, set) in session.orderedCaptureSets.enumerated() {
            for capture in set.orderedCaptures {
                XCTAssertEqual(store.assetKey(forCaptureID: capture.id),
                               DemoAssetKey(stageIndex: i + 1, angle: capture.angle, variant: .sharp))
            }
        }
        XCTAssertNil(store.assetKey(forCaptureID: UUID()))

        let blurred = try store.makeCapture(stageIndex: 4, angle: .frontal, variant: .blurred, in: session,
                                            tiltDegrees: 9, overridden: true)
        XCTAssertTrue(blurred.qualityOverridden)
        XCTAssertEqual(blurred.tiltDegrees, 9)
        XCTAssertEqual(blurred.quality?.failures.contains(.tilted), true)
        XCTAssertEqual(store.assetKey(forCaptureID: blurred.id), DemoAssetKey(stageIndex: 4, angle: .frontal, variant: .blurred))
        // Obliques have no blurred render, so the sharp one is used and recorded.
        let oblique = try store.makeCapture(stageIndex: 4, angle: .leftOblique, variant: .blurred, in: session,
                                            tiltDegrees: nil, overridden: false)
        XCTAssertEqual(store.assetKey(forCaptureID: oblique.id)?.variant, .sharp)

        let manual = UUID()
        store.recordAsset(DemoAssetKey(stageIndex: 3, angle: .rightOblique, variant: .sharp), forCaptureID: manual)
        XCTAssertEqual(store.assetKey(forCaptureID: manual)?.stageIndex, 3)

        // The sidecar sits in the root, is a plain file and does not show up as a session.
        let sidecar = store.root.appendingPathComponent("demo-keys.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        let decoded = try JSONDecoder().decode([String: DemoAssetKey].self, from: Data(contentsOf: sidecar))
        XCTAssertEqual(decoded[manual.uuidString]?.angle, .rightOblique)
        XCTAssertEqual(try SessionRepository(root: store.root).loadAll().count, 1)

        store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertNil(store.assetKey(forCaptureID: manual))
        XCTAssertNil(store.session)
    }

    func testMakeCaptureFailsForAMissingAsset() throws {
        let store = PracticeStore(root: tempRoot(), patient: DemoFixture.patient(stages: 2), imageData: { _ in nil })
        let session = StudySession(studyID: "DEMO-VP1")
        XCTAssertThrowsError(try store.makeCapture(stageIndex: 1, angle: .frontal, variant: .sharp, in: session,
                                                   tiltDegrees: nil, overridden: false))
        XCTAssertThrowsError(try makeStore().makeCapture(stageIndex: 7, angle: .frontal, variant: .sharp, in: session,
                                                         tiltDegrees: nil, overridden: false))
    }

    // MARK: - Separation from study data

    func testAStudyStoreOverAnotherRootIsUntouched() throws {
        let studyRoot = tempRoot()
        let study = SessionStore(repository: try SessionRepository(root: studyRoot))
        let real = try study.create(studyID: "S-014")
        let practice = makeStore()
        XCTAssertNotEqual(practice.root.standardizedFileURL, studyRoot.standardizedFileURL)

        try practice.seed(now: now)
        try practice.reset()
        practice.deleteAll()

        let reloaded = try SessionRepository(root: studyRoot).loadAll()
        XCTAssertEqual(reloaded.map(\.id), [real.id])
        XCTAssertEqual(study.sessions.map(\.id), [real.id])

        let stores = SessionStores(study: study, practice: practice)
        XCTAssertTrue(stores.store(for: .study) === study)
        XCTAssertTrue(stores.store(for: .practice) === practice.store)
        try practice.seed(now: now)
        stores.deleteAllData()
        XCTAssertTrue(study.sessions.isEmpty)
        XCTAssertNil(practice.session)
    }
}
