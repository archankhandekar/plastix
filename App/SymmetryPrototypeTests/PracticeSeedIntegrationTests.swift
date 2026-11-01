import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// The virtual patient seeded from the real bundled renders and ground truth (Bundle.main is
/// the host app), into a temporary root. Also the DEBUG route harness's seeding.
///
/// Seed choice: these tests use `PracticeStore.defaultRNGSeed`, the seed `seed()` uses when
/// called with no argument, which is how SessionListView, session home and Settings start
/// and reset the virtual patient. If a new render breaks the designed sign pattern, change
/// that one constant in PracticeStore.
@MainActor
final class PracticeSeedIntegrationTests: XCTestCase {
    private var roots: [URL] = []
    private let suiteName = "PracticeSeedIntegrationTests"
    private let sigma = FrontalMetricsCalculator.defaultLandmarkSigmaRatio

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        UIFlags.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        UserDefaults().removePersistentDomain(forName: suiteName)
        UserDefaults().removePersistentDomain(forName: RouteHarness.suiteName)
        UIFlags.defaults = .standard
        super.tearDown()
    }

    private func makeStore() throws -> PracticeStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeSeedIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        let patient = try XCTUnwrap(DemoPatient.loadBundled(), "the bundled virtual patient did not load")
        return PracticeStore(root: root, patient: patient)
    }

    private func metrics(_ set: CaptureSet) throws -> FrontalMetrics {
        try XCTUnwrap(set.frontal?.frontalMetrics(sigma: sigma), "set has no frontal metrics")
    }

    // MARK: - Seeding from the bundle

    func testSeededSetsKeepTheDesignedSignPattern() throws {
        let store = try makeStore()
        let session = try store.seed()
        let sets = session.orderedCaptureSets
        XCTAssertEqual(sets.count, 3)

        let m1 = try metrics(sets[0]), m2 = try metrics(sets[1])
        let v1 = try XCTUnwrap(m1.verticalNippleDifference)
        let v2 = try XCTUnwrap(m2.verticalNippleDifference)
        let f1 = try XCTUnwrap(m1.imfHeightDifference)
        XCTAssertGreaterThan(v1.value, v1.uncertainty, "set 1 nipple height: patient left lower, beyond its ±")
        XCTAssertLessThan(v2.value, -v2.uncertainty, "set 2 nipple height: patient right lower, beyond its ±")
        XCTAssertGreaterThan(f1.value, f1.uncertainty, "set 1 fold height: patient left lower, beyond its ±")
        XCTAssertNotNil(m1.contourOverlap)
        XCTAssertNotNil(m2.contourOverlap)

        // Set 3 is taken but not marked.
        XCTAssertNotNil(sets[2].frontal)
        XCTAssertNil(sets[2].frontal?.landmarks)
    }

    func testThePatternHoldsForTheSeedTheAppUses() throws {
        // seed() with no argument must be the same seed as defaultRNGSeed.
        let a = try makeStore(), b = try makeStore()
        let s1 = try a.seed()
        let s2 = try b.seed(rngSeed: PracticeStore.defaultRNGSeed)
        let p1 = s1.orderedCaptureSets[0].frontal?.landmarks?.points[.leftNipple]
        let p2 = s2.orderedCaptureSets[0].frontal?.landmarks?.points[.leftNipple]
        XCTAssertEqual(p1, p2)
    }

    func testOutlinesHave48PointsEach() throws {
        let store = try makeStore()
        let session = try store.seed()
        for set in session.orderedCaptureSets.prefix(2) {
            let landmarks = try XCTUnwrap(set.frontal?.landmarks)
            XCTAssertEqual(landmarks.leftContour.count, 48)
            XCTAssertEqual(landmarks.rightContour.count, 48)
            XCTAssertTrue(landmarks.isComplete)
        }
    }

    func testEverySeededCaptureHasItsAssetKeyAndImage() throws {
        let store = try makeStore()
        let session = try store.seed()
        for (i, set) in session.orderedCaptureSets.enumerated() {
            XCTAssertEqual(set.captures.count, 3)
            for capture in set.orderedCaptures {
                let key = try XCTUnwrap(store.assetKey(forCaptureID: capture.id), "no DemoAssetKey for set \(i + 1) \(capture.angle)")
                XCTAssertEqual(key, DemoAssetKey(stageIndex: i + 1, angle: capture.angle, variant: .sharp))
                XCTAssertNotNil(store.store.image(for: capture, in: session), "no image for set \(i + 1) \(capture.angle)")
                XCTAssertTrue(capture.quality?.passed ?? false, "the sharp render should pass the photo checks")
            }
        }
    }

    func testExportEligibilityRefusesTheSeededSession() throws {
        let store = try makeStore()
        let session = try store.seed()
        XCTAssertEqual(ExportEligibility.check(kind: .practice, studyID: session.studyID), .practiceRefused)
        // The DEMO- code alone also refuses, even if the kind were wrong.
        XCTAssertEqual(ExportEligibility.check(kind: .study, studyID: session.studyID), .practiceRefused)
    }

    // MARK: - Route harness

    func testHarnessUsesTemporaryRootsAndItsOwnSuite() throws {
        let launch = RouteHarness.makeEnvironment(try XCTUnwrap(LaunchRoute.parse(["-UIRoute", "home"])))
        roots.append(launch.studyRoot.deletingLastPathComponent())
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        XCTAssertTrue(launch.studyRoot.standardizedFileURL.path.hasPrefix(tmp))
        XCTAssertTrue(launch.practiceRoot.standardizedFileURL.path.hasPrefix(tmp))
        XCTAssertTrue(launch.studyRoot.deletingLastPathComponent().lastPathComponent.hasPrefix("RouteHarness-"))
        let realStudy = try SessionRepository.defaultRoot().standardizedFileURL.path
        let realPractice = try PracticeStore.defaultRoot().standardizedFileURL.path
        for root in [launch.studyRoot, launch.practiceRoot] {
            XCTAssertNotEqual(root.standardizedFileURL.path, realStudy)
            XCTAssertNotEqual(root.standardizedFileURL.path, realPractice)
        }
        // UI flags go to the wiped RouteHarness suite, never to the standard defaults.
        let probe = UUID()
        UIFlags.markViewed(setID: probe)
        XCTAssertTrue(UserDefaults(suiteName: RouteHarness.suiteName)!.bool(forKey: "viewed-" + probe.uuidString))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "viewed-" + probe.uuidString))
        XCTAssertTrue(launch.stores.study.sessions.isEmpty)
        let practice = try XCTUnwrap(launch.stores.practice.session)
        XCTAssertEqual(launch.navigator.path, [.session(SessionRef(id: practice.id, kind: .practice))])
        XCTAssertTrue(launch.settings.researchNoticeAccepted)
    }

    func testHarnessSeedsTheStudySessionWithoutAssetKeys() throws {
        let route = try XCTUnwrap(LaunchRoute.parse(["-UIRoute", "export", "-UISeedStudy", "1", "-UIDemo", "0"]))
        let launch = RouteHarness.makeEnvironment(route)
        roots.append(launch.studyRoot.deletingLastPathComponent())
        let study = try XCTUnwrap(launch.stores.study.sessions.first)
        XCTAssertEqual(study.studyID, RouteHarness.studyHarnessID)
        XCTAssertEqual(ExportEligibility.check(kind: .study, studyID: study.studyID), .allowed)
        XCTAssertNil(launch.stores.practice.session)
        let ref = SessionRef(id: study.id, kind: .study)
        XCTAssertEqual(launch.navigator.path, [.session(ref), .export(ref)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: launch.studyRoot.appendingPathComponent("demo-keys.json").path))
        for capture in study.captureSets.flatMap(\.orderedCaptures) {
            XCTAssertNil(launch.stores.practice.assetKey(forCaptureID: capture.id))
        }
    }

    func testHarnessStagesRouteCompletesFourSets() throws {
        let launch = RouteHarness.makeEnvironment(try XCTUnwrap(LaunchRoute.parse(["-UIRoute", "stages"])))
        roots.append(launch.studyRoot.deletingLastPathComponent())
        let session = try XCTUnwrap(launch.stores.practice.session)
        XCTAssertEqual(session.orderedCaptureSets.count, 4)
        for set in session.orderedCaptureSets {
            XCTAssertTrue(set.isComplete)
            XCTAssertTrue(SessionWizard.isMeasured(set, sigma: sigma))
        }
        let ref = SessionRef(id: session.id, kind: .practice)
        XCTAssertEqual(launch.navigator.path, [.session(ref), .acrossStages(ref)])
    }

    func testHarnessStatesChangeOnlyTheTargetSet() throws {
        func frontal(_ args: [String], set index: Int) throws -> Capture {
            let launch = RouteHarness.makeEnvironment(try XCTUnwrap(LaunchRoute.parse(args)))
            roots.append(launch.studyRoot.deletingLastPathComponent())
            let session = try XCTUnwrap(launch.stores.practice.session)
            return try XCTUnwrap(session.orderedCaptureSets[index].frontal)
        }
        let missingFold = try frontal(["-UIRoute", "symmetry", "-UIStage", "2", "-UIState", "missingFold"], set: 1)
        XCTAssertNil(missingFold.landmarks?[.leftIMF])
        XCTAssertNotNil(missingFold.landmarks?[.rightIMF])

        let noOutlines = try frontal(["-UIRoute", "symmetry", "-UIStage", "2", "-UIState", "noOutlines"], set: 1)
        XCTAssertEqual(noOutlines.landmarks?.leftContour.count, 0)
        XCTAssertEqual(noOutlines.landmarks?.rightContour.count, 0)
        XCTAssertTrue(noOutlines.landmarks?.isComplete ?? false)

        let blurred = try frontal(["-UIRoute", "symmetry", "-UIStage", "1", "-UIState", "blurredKept"], set: 0)
        XCTAssertTrue(blurred.qualityOverridden)
        XCTAssertFalse(blurred.quality?.passed ?? true)
        XCTAssertTrue(blurred.landmarks?.isComplete ?? false)

        let unmarked = try frontal(["-UIRoute", "symmetry", "-UIStage", "1", "-UIState", "unmarked"], set: 0)
        XCTAssertNil(unmarked.landmarks)
    }

    func testHarnessCaptureRouteOpensANewSetAtTheStage() throws {
        let route = try XCTUnwrap(LaunchRoute.parse(["-UIRoute", "capture", "-UIStage", "4", "-UICaptureAngle", "leftOblique",
                                                     "-UIPracticeRetake", "1"]))
        let launch = RouteHarness.makeEnvironment(route)
        roots.append(launch.studyRoot.deletingLastPathComponent())
        guard case .capture(let target)? = launch.presentation else { return XCTFail("no capture cover") }
        XCTAssertEqual(target.index, 4)
        XCTAssertEqual(target.angles, [.leftOblique, .rightOblique, .frontal])
        XCTAssertTrue(target.practiceRetake)
        XCTAssertTrue(target.set.captures.isEmpty)
        XCTAssertEqual(launch.stores.practice.session?.orderedCaptureSets.count, 3)
    }
}
