import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// Pure-logic tests for the new wizard: every state and next action comes from in-memory
/// fixtures, no files and no images. Ported from SessionProgressTests, plus the
/// see-left-and-right, across-stages, practice, route, SetStatus and tour rules.
final class SessionWizardTests: XCTestCase {
    private let settings = ReportSettings(landmarkSigmaRatio: FrontalMetricsCalculator.defaultLandmarkSigmaRatio,
                                          qualityThresholds: QualityThresholds(),
                                          maxResidualRatio: Registration.defaultMaxResidualRatio)
    private let suiteName = "SessionWizardTests"
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
        UIFlags.defaults = suite
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        UIFlags.defaults = .standard
        super.tearDown()
    }

    // MARK: - Fixtures

    private func capture(_ angle: ViewAngle, quality: QualityReport? = nil, landmarks: LandmarkSet? = nil) -> Capture {
        Capture(angle: angle, imageFilename: "\(angle.rawValue).jpg", pixelWidth: 1000, pixelHeight: 1400,
                quality: quality, tiltDegrees: nil, landmarks: landmarks)
    }

    private var passed: QualityReport {
        QualityReport(blurScore: 200, clippedHighlightFraction: 0, clippedShadowFraction: 0, tiltDegrees: 1, failures: [])
    }

    private var blurred: QualityReport {
        QualityReport(blurScore: 5, clippedHighlightFraction: 0, clippedShadowFraction: 0, tiltDegrees: 1, failures: [.blurry])
    }

    /// Six points at distinct coordinates with a non-degenerate midline.
    private var sixPoints: LandmarkSet {
        LandmarkSet(points: [
            .sternalNotch: Point2D(x: 500, y: 300),
            .midlineBottom: Point2D(x: 500, y: 900),
            .leftNipple: Point2D(x: 700, y: 600),
            .rightNipple: Point2D(x: 300, y: 610),
            .leftIMF: Point2D(x: 690, y: 800),
            .rightIMF: Point2D(x: 310, y: 790),
        ], imageSize: Point2D(x: 1000, y: 1400))
    }

    private var twoPoints: LandmarkSet {
        LandmarkSet(points: [
            .sternalNotch: Point2D(x: 500, y: 300),
            .midlineBottom: Point2D(x: 500, y: 900),
        ], imageSize: Point2D(x: 1000, y: 1400))
    }

    private var degenerate: LandmarkSet {
        var d = sixPoints
        d[.midlineBottom] = d[.sternalNotch]
        return d
    }

    private func set(stage: OperativeStage, createdAt: Date, angles: [ViewAngle] = ViewAngle.allCases,
                     frontalLandmarks: LandmarkSet? = nil, frontalQuality: QualityReport? = nil) -> CaptureSet {
        var captures: [ViewAngle: Capture] = [:]
        for angle in angles {
            captures[angle] = capture(angle, quality: angle == .frontal ? frontalQuality : nil,
                                      landmarks: angle == .frontal ? frontalLandmarks : nil)
        }
        return CaptureSet(stage: stage, positioning: Positioning(tableAngle: "30°", armPosition: "at sides"),
                          createdAt: createdAt, captures: captures)
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(3600) }
    private var t2: Date { t0.addingTimeInterval(7200) }
    private var t3: Date { t0.addingTimeInterval(10800) }

    private func session(_ sets: [CaptureSet]) -> StudySession {
        StudySession(studyID: "S-014", captureSets: sets)
    }

    /// Every set counts as viewed unless `viewed` says otherwise, so the ported scenarios keep
    /// their old next actions.
    private func wizard(_ sets: [CaptureSet], viewed: Set<UUID>? = nil, hasOpenedStages: Bool = false,
                        kind: SessionKind = .study) -> SessionWizard {
        SessionWizard(session: session(sets), settings: settings, kind: kind,
                      viewedSetIDs: viewed ?? Set(sets.map(\.id)), hasOpenedStages: hasOpenedStages)
    }

    private let ref = SessionRef(id: UUID(), kind: .study)

    // MARK: - Ported: next action and step states

    func testEmptySessionAsksForTheFirstPhotos() {
        let w = wizard([])
        XCTAssertEqual(w.next.title, "Take the first 3 photos")
        XCTAssertEqual(w.next.detail, "Preoperative marking. Frontal, then left oblique, then right oblique. About one minute.")
        XCTAssertEqual(w.states[.takePhotos], .current("Not started"))
        XCTAssertEqual(w.states[.markPoints], .upcoming("Needs photos first"))
        XCTAssertEqual(w.states[.seeSides], .upcoming("Needs a set with all 6 points"))
        XCTAssertEqual(w.states[.export], .upcoming("Needs at least one measured set"))
        XCTAssertEqual(w.currentStep, .takePhotos)
        XCTAssertEqual(w.summaryLine, "0 photo sets. Next: Take the first 3 photos.")
        XCTAssertNil(w.focusSet)
        if case .newSet(let stage, let positioning, let index, _, _) = w.next {
            XCTAssertEqual(stage, .preoperativeMarking)
            XCTAssertNil(positioning)
            XCTAssertNil(index)
        } else {
            XCTFail("expected newSet, got \(w.next)")
        }
    }

    func testIncompleteSetAsksForTheMissingPhoto() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique])])
        XCTAssertEqual(w.next.title, "Take the missing photo for set 1")
        XCTAssertEqual(w.next.detail, "Set 1 still needs: Right oblique.")
        XCTAssertEqual(w.states[.takePhotos], .current("2 of 3 photos taken in set 1"))
        XCTAssertEqual(w.states[.markPoints], .upcoming("Needs photos first"))
        XCTAssertEqual(w.firstIncomplete?.index, 1)
        XCTAssertFalse(w.isActionable(.markPoints))
    }

    func testTwoMissingPhotosUsesThePlural() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal])])
        XCTAssertEqual(w.next.title, "Take the missing photos for set 1")
        XCTAssertEqual(w.next.detail, "Set 1 still needs: Left oblique, Right oblique.")
    }

    func testIncompleteSetWithMarkedFrontalKeepsThePointsVisible() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal], frontalLandmarks: sixPoints)])
        XCTAssertEqual(w.next.title, "Take the missing photos for set 1")
        XCTAssertEqual(w.states[.takePhotos], .current("1 of 3 photos taken in set 1"))
        XCTAssertEqual(w.states[.markPoints], .upcoming("Set 1 placed, photos still missing"))
        XCTAssertFalse(w.isActionable(.markPoints))
    }

    func testIncompleteSetWithPartialFrontalPointsCountsThem() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique], frontalLandmarks: twoPoints)])
        XCTAssertEqual(w.next.title, "Take the missing photo for set 1")
        XCTAssertEqual(w.states[.markPoints], .upcoming("2 of 6 points placed on set 1, photos still missing"))
    }

    func testCompleteSetWithoutLandmarksAsksForPoints() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0)])
        XCTAssertEqual(w.next.title, "Mark the points on set 1")
        XCTAssertEqual(w.next.detail, "Set 1, preoperative marking. 0 of 6 points placed.")
        XCTAssertEqual(w.states[.takePhotos], .done("1 set complete"))
        XCTAssertEqual(w.states[.markPoints], .current("0 of 6 points placed on set 1"))
        XCTAssertTrue(w.isActionable(.markPoints))
        XCTAssertFalse(w.isActionable(.export))
        XCTAssertFalse(w.isActionable(.seeSides))
    }

    func testPartiallyMarkedFrontalCountsThePoints() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: twoPoints)])
        XCTAssertEqual(w.next.detail, "Set 1, preoperative marking. 2 of 6 points placed.")
        XCTAssertEqual(w.states[.markPoints], .current("2 of 6 points placed on set 1"))
    }

    func testOneMeasuredSetAsksForTheNextStage() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)])
        XCTAssertEqual(w.measuredSets.count, 1)
        XCTAssertEqual(w.next.title, "Take 3 photos at the next stage")
        XCTAssertEqual(w.next.detail, "Suggested stage: After mastectomy or resection.")
        XCTAssertEqual(w.states[.markPoints], .done("Set 1 measured"))
        XCTAssertEqual(w.states[.seeSides], .done("Seen for set 1"))
        XCTAssertEqual(w.states[.export], .upcoming("Ready"))
        XCTAssertTrue(w.isActionable(.export))
        XCTAssertEqual(SessionWizard.suggestedStage(after: .preoperativeMarking), .afterResection)
        if case .newSet(let stage, let positioning, let index, _, _) = w.next {
            XCTAssertEqual(stage, .afterResection)
            XCTAssertEqual(positioning?.tableAngle, "30°")
            XCTAssertEqual(index, 1)
        } else {
            XCTFail("expected newSet, got \(w.next)")
        }
    }

    func testSuggestedStageClampsAndKeepsCustom() {
        XCTAssertEqual(SessionWizard.suggestedStage(after: nil), .preoperativeMarking)
        XCTAssertEqual(SessionWizard.suggestedStage(after: .afterClosure), .afterClosure)
        XCTAssertEqual(SessionWizard.suggestedStage(after: .custom("Lateral check")), .custom("Lateral check"))
    }

    func testTwoMeasuredViewedSetsAskForAcrossStages() {
        let w = wizard([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints),
        ])
        XCTAssertEqual(w.next.title, "See how each difference changed across stages")
        XCTAssertEqual(w.next.detail, "2 sets have all 6 points placed.")
        XCTAssertEqual(w.states[.takePhotos], .done("2 sets complete"))
        XCTAssertEqual(w.states[.markPoints], .done("2 sets measured"))
        XCTAssertEqual(w.states[.seeSides], .current("Seen for all 2 measured sets"))
        XCTAssertEqual(w.states[.export], .upcoming("Ready"))
        XCTAssertEqual(w.currentStep, .seeSides)
        XCTAssertTrue(w.isActionable(.seeSides))
        if case .acrossStages = w.next {} else { XCTFail("expected acrossStages, got \(w.next)") }
    }

    func testAfterOpeningStagesTheNextStepIsExport() {
        let w = wizard([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints),
        ], hasOpenedStages: true)
        XCTAssertEqual(w.next.title, "Export the report")
        XCTAssertEqual(w.next.detail, "2 measured sets.")
        XCTAssertEqual(w.states[.seeSides], .done("Seen for all 2 measured sets"))
        XCTAssertEqual(w.states[.export], .current("Ready"))
        XCTAssertEqual(w.currentStep, .export)
    }

    func testSummaryLineCountsSetsAndNamesTheNextAction() {
        let w = wizard([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1),
        ])
        XCTAssertEqual(w.summaryLine, "2 photo sets. Next: Mark the points on set 2.")
        XCTAssertEqual(w.next.detail, "Set 2, after closure. 0 of 6 points placed.")
        XCTAssertEqual(wizard([set(stage: .preoperativeMarking, createdAt: t0)]).summaryLine,
                       "1 photo set. Next: Mark the points on set 1.")
    }

    func testDegenerateMidlineIsNotMeasured() {
        let w = wizard([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: degenerate)])
        XCTAssertTrue(w.measuredSets.isEmpty)
        XCTAssertEqual(w.states[.export], .upcoming("Needs at least one measured set"))
        XCTAssertFalse(w.isActionable(.seeSides))
    }

    func testCoincidentMidlineRoutesBackToMarkPoints() {
        let only = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: degenerate)
        let w = wizard([only])
        XCTAssertEqual(w.next.title, "Move the midline points apart on set 1")
        XCTAssertEqual(w.next.detail, "Set 1: the two midline points are on top of each other. Move one so they are apart.")
        XCTAssertEqual(w.currentStep, .markPoints)
        XCTAssertEqual(w.states[.markPoints], .current("Midline points on top of each other on set 1"))
        XCTAssertEqual(w.states[.seeSides], .upcoming("Needs a set with all 6 points"))
        if case .markPoints(let set, let index, let capture, _, _) = w.next {
            XCTAssertEqual(set.id, only.id)
            XCTAssertEqual(index, 1)
            XCTAssertEqual(capture.angle, .frontal)
        } else {
            XCTFail("expected markPoints, got \(w.next)")
        }

        let status = SetStatus(set: only, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertFalse(status.isMeasured)
        XCTAssertEqual(status.nextAction?.title, "Move the midline points apart")
        XCTAssertEqual(status.gapLines, ["Set 1 has its two midline points on top of each other on its frontal photo"])
    }

    func testCoincidentMidlineOnALaterSetComesBeforeANewStage() {
        let w = wizard([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: degenerate),
        ])
        XCTAssertEqual(w.measuredSets.count, 1)
        XCTAssertEqual(w.next.title, "Move the midline points apart on set 2")
        XCTAssertEqual(w.next.detail, "Set 2: the two midline points are on top of each other. Move one so they are apart.")
        XCTAssertEqual(w.states[.markPoints], .current("Midline points on top of each other on set 2"))
    }

    func testIndexAndTitleOfSet() {
        let a = set(stage: .preoperativeMarking, createdAt: t0)
        let b = set(stage: .afterResection, createdAt: t1)
        let s = session([b, a])   // stored out of order; ordering is by createdAt
        XCTAssertEqual(SessionWizard.index(of: a, in: s), 1)
        XCTAssertEqual(SessionWizard.index(of: b, in: s), 2)
        XCTAssertEqual(SessionWizard.title(of: b, in: s), "Set 2, after mastectomy or resection")
        XCTAssertEqual(SessionWizard.title(of: a, in: s), "Set 1, preoperative marking")
        let custom = set(stage: .custom("Lateral check"), createdAt: t2)
        XCTAssertEqual(SessionWizard.title(of: custom, in: session([a, b, custom])), "Set 3, Lateral check")
        XCTAssertEqual(SessionWizard.index(of: custom, in: s), 0)
    }

    func testPointsMarkedCountsPlacedPoints() {
        XCTAssertEqual(SessionWizard.pointsMarked(on: nil), 0)
        XCTAssertEqual(SessionWizard.pointsMarked(on: capture(.frontal)), 0)
        XCTAssertEqual(SessionWizard.pointsMarked(on: capture(.frontal, landmarks: twoPoints)), 2)
        XCTAssertEqual(SessionWizard.pointsMarked(on: capture(.frontal, landmarks: sixPoints)), 6)
    }

    // MARK: - New rules

    func testViewSymmetryPicksTheEarliestUnviewedMeasuredSet() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let b = set(stage: .afterResection, createdAt: t1, frontalLandmarks: sixPoints)
        let c = set(stage: .afterClosure, createdAt: t2, frontalLandmarks: sixPoints)
        let w = wizard([c, a, b], viewed: [a.id])
        XCTAssertEqual(w.next.title, "See left and right for set 2")
        XCTAssertEqual(w.next.detail, "Set 2, after mastectomy or resection. All 6 points are placed.")
        XCTAssertEqual(w.states[.seeSides], .current("Ready for set 2"))
        XCTAssertEqual(w.currentStep, .seeSides)
        if case .viewSymmetry(let s, let index, _, _) = w.next {
            XCTAssertEqual(s.id, b.id)
            XCTAssertEqual(index, 2)
        } else {
            XCTFail("expected viewSymmetry, got \(w.next)")
        }

        let none = wizard([a, b, c], viewed: [])
        XCTAssertEqual(none.next.title, "See left and right for set 1")
        XCTAssertEqual(none.states[.seeSides], .current("Ready for set 1"))
    }

    func testOneMeasuredUnviewedSetAsksToSeeItFirst() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let w = wizard([a], viewed: [])
        XCTAssertEqual(w.next.title, "See left and right for set 1")
        XCTAssertEqual(w.summaryLine, "1 photo set. Next: See left and right for set 1.")
        XCTAssertEqual(w.states[.markPoints], .done("Set 1 measured"))
    }

    func testAllViewedWithFewerThanTwoMeasuredIsNewSet() {
        let a = set(stage: .afterResection, createdAt: t0, frontalLandmarks: sixPoints)
        let w = wizard([a], viewed: [a.id])
        if case .newSet(let stage, _, let index, _, _) = w.next {
            XCTAssertEqual(stage, .afterImplantOrExpander)
            XCTAssertEqual(index, 1)
        } else {
            XCTFail("expected newSet, got \(w.next)")
        }
        XCTAssertEqual(w.next.detail, "Suggested stage: After implant or expander placement.")
        XCTAssertEqual(w.currentStep, .takePhotos)
    }

    func testSeeingAnUnviewedSetComesBeforeMarkingAnotherSet() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let b = set(stage: .afterResection, createdAt: t1)
        let w = wizard([a, b], viewed: [])
        XCTAssertEqual(w.next.title, "See left and right for set 1")
        XCTAssertEqual(w.currentStep, .seeSides)
        // Once set 1 has been seen, marking set 2 is next.
        XCTAssertEqual(wizard([a, b], viewed: [a.id]).next.title, "Mark the points on set 2")
    }

    func testPracticeExportTitleAndStatus() {
        let sets = [
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints),
        ]
        let w = wizard(sets, hasOpenedStages: true, kind: .practice)
        XCTAssertEqual(w.kind, .practice)
        XCTAssertEqual(w.next.title, "See what a report would contain")
        XCTAssertEqual(w.next.detail, "Practice sessions are not exported.")
        XCTAssertEqual(w.states[.export], .current("Not available for practice sessions"))
        XCTAssertEqual(wizard([], kind: .practice).states[.export], .upcoming("Not available for practice sessions"))
    }

    func testSeeSidesStatuses() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let b = set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints)
        XCTAssertEqual(wizard([]).states[.seeSides]?.status, "Needs a set with all 6 points")
        XCTAssertEqual(wizard([a], viewed: []).states[.seeSides]?.status, "Ready for set 1")
        XCTAssertEqual(wizard([a], viewed: [a.id]).states[.seeSides]?.status, "Seen for set 1")
        XCTAssertEqual(wizard([a, b], viewed: [a.id]).states[.seeSides]?.status, "Ready for set 2")
        XCTAssertEqual(wizard([a, b], viewed: [a.id, b.id]).states[.seeSides]?.status, "Seen for all 2 measured sets")
        // Completion: done only when every measured set is viewed.
        XCTAssertEqual(wizard([a, b], viewed: [a.id, b.id], hasOpenedStages: true).states[.seeSides], .done("Seen for all 2 measured sets"))
        let partial = wizard([a, b, set(stage: .afterClosure, createdAt: t2)], viewed: [a.id])
        XCTAssertEqual(partial.states[.seeSides], .current("Ready for set 2"))
    }

    func testIsActionable() {
        let empty = wizard([])
        XCTAssertTrue(empty.isActionable(.takePhotos))
        XCTAssertFalse(empty.isActionable(.markPoints))
        XCTAssertFalse(empty.isActionable(.seeSides))
        XCTAssertFalse(empty.isActionable(.export))

        let unmarked = wizard([set(stage: .preoperativeMarking, createdAt: t0)])
        XCTAssertTrue(unmarked.isActionable(.markPoints))
        XCTAssertFalse(unmarked.isActionable(.seeSides))
        XCTAssertFalse(unmarked.isActionable(.export))

        let measured = wizard([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)])
        XCTAssertTrue(measured.isActionable(.markPoints))
        XCTAssertTrue(measured.isActionable(.seeSides))
        XCTAssertTrue(measured.isActionable(.export))
    }

    func testRouteMapping() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let frontal = a.frontal!
        let mark = SessionWizard.Action.markPoints(set: a, index: 1, capture: frontal, title: "", detail: "")
        XCTAssertEqual(mark.route(ref), .markPoints(ref, setID: a.id, captureID: frontal.id, showTruth: false))
        let view = SessionWizard.Action.viewSymmetry(set: a, index: 1, title: "", detail: "")
        XCTAssertEqual(view.route(ref), .symmetry(ref, setID: a.id, tab: .frontal, focus: .all, obliqueMode: .sideBySide))
        XCTAssertEqual(SessionWizard.Action.acrossStages(title: "", detail: "").route(ref), .acrossStages(ref))
        XCTAssertEqual(SessionWizard.Action.export(title: "", detail: "").route(ref), .export(ref))
        XCTAssertNil(SessionWizard.firstSetAction.route(ref))
        let missing = SessionWizard.Action.captureMissing(set: a, index: 1, angles: [.rightOblique], title: "", detail: "")
        XCTAssertNil(missing.route(ref))

        XCTAssertEqual(mark.step, .markPoints)
        XCTAssertEqual(view.step, .seeSides)
        XCTAssertEqual(missing.step, .takePhotos)
        XCTAssertEqual(SessionWizard.Action.acrossStages(title: "", detail: "").step, .seeSides)
        XCTAssertEqual(SessionWizard.Action.export(title: "", detail: "").step, .export)
    }

    func testFocusSetIsTheNewestMeasuredElseTheNewest() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let b = set(stage: .afterResection, createdAt: t1, frontalLandmarks: sixPoints)
        let c = set(stage: .afterClosure, createdAt: t2)
        let w = wizard([a, b, c])
        XCTAssertEqual(w.focusSet?.index, 2)
        XCTAssertEqual(w.focusSet?.set.id, b.id)
        XCTAssertEqual(w.measuredIndexed.map(\.index), [1, 2])
        let unmeasured = wizard([set(stage: .preoperativeMarking, createdAt: t0), c])
        XCTAssertEqual(unmeasured.focusSet?.set.id, c.id)
    }

    func testStepTitles() {
        XCTAssertEqual(SessionWizard.Step.allCases.map(\.title), ["Take photos", "Mark points", "See left and right", "Export"])
        XCTAssertEqual(SessionWizard.Step.allCases.map(\.rawValue), [1, 2, 3, 4])
    }

    func testFlagReadingInitUsesUIFlags() {
        let a = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let b = set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints)
        let s = session([a, b])
        XCTAssertEqual(SessionWizard(session: s, settings: settings).next.title, "See left and right for set 1")
        UIFlags.markViewed(setID: a.id)
        UIFlags.markViewed(setID: b.id)
        XCTAssertEqual(SessionWizard(session: s, settings: settings).next.title, "See how each difference changed across stages")
        UIFlags.markOpenedStages(sessionID: s.id)
        let w = SessionWizard(session: s, settings: settings)
        XCTAssertEqual(w.next.title, "Export the report")
        XCTAssertTrue(w.hasOpenedStages)
        XCTAssertEqual(w.viewedSetIDs, [a.id, b.id])
    }

    // MARK: - SetStatus

    func testStatusLineWithOneWarning() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints, frontalQuality: blurred)
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos, 1 photo has a warning.")
        XCTAssertEqual(status.shortLine, "3 photos, 6 of 6 points")
        XCTAssertEqual(status.warningCount, 1)
        XCTAssertEqual(status.uncheckedCount, 2)
        XCTAssertTrue(status.isMeasured)
        XCTAssertEqual(status.nextAction?.title, "See left and right")
        if case .viewSymmetry(_, let index, _, _)? = status.nextAction { XCTAssertEqual(index, 1) } else {
            XCTFail("expected viewSymmetry")
        }
        XCTAssertTrue(status.gapLines.isEmpty)
    }

    func testStatusLineWithTwoWarnings() {
        var s = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints, frontalQuality: blurred)
        s.captures[.leftOblique] = capture(.leftOblique, quality: blurred)
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos, 2 photos have a warning.")
    }

    func testStatusLineWhenMeasured() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints, frontalQuality: passed)
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos, 6 of 6 points placed.")
        XCTAssertEqual(status.shortLine, "3 photos, 6 of 6 points")
        XCTAssertEqual(status.title, "Set 1, preoperative marking")
        XCTAssertEqual(status.warningCount, 0)
        XCTAssertEqual(status.uncheckedCount, 2)
        let time = t0.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(status.takenLine, "Taken \(time). 3 photos, 6 of 6 points.")
    }

    func testStatusLineWithMissingPhotos() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique])
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "2 of 3 photos, points not yet placed.")
        XCTAssertEqual(status.shortLine, "2 of 3 photos")
        XCTAssertEqual(status.missing, [.rightOblique])
        XCTAssertEqual(status.photosTaken, 2)
        XCTAssertEqual(status.nextAction?.title, "Take the missing photo")
        XCTAssertEqual(status.nextAction?.detail, "Set 1 still needs: Right oblique.")
        XCTAssertEqual(status.gapLines, ["Set 1 is missing Right oblique", "Set 1 has no points on its frontal photo"])

        let two = SetStatus(set: set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal]), index: 1,
                            sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(two.nextAction?.title, "Take the missing photos")
        XCTAssertEqual(two.gapLines.first, "Set 1 is missing Left oblique, Right oblique")
    }

    func testStatusLineWithMissingPhotosAndPoints() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique], frontalLandmarks: twoPoints)
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "2 of 3 photos, 2 of 6 points placed.")
        XCTAssertEqual(status.gapLines, ["Set 1 is missing Right oblique", "Set 1 has 2 of 6 points on its frontal photo"])
    }

    func testStatusLineWithPartialPoints() {
        let s = set(stage: .afterClosure, createdAt: t0, frontalLandmarks: twoPoints)
        let status = SetStatus(set: s, index: 2, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos, 2 of 6 points placed.")
        XCTAssertEqual(status.shortLine, "3 photos, 2 of 6 points")
        XCTAssertEqual(status.pointsMarked, 2)
        XCTAssertFalse(status.isMeasured)
        XCTAssertEqual(status.nextAction?.title, "Mark the points")
        XCTAssertEqual(status.nextAction?.detail, "Set 2, after closure. 2 of 6 points placed.")
        XCTAssertEqual(status.gapLines, ["Set 2 has 2 of 6 points on its frontal photo"])
    }

    func testStatusLineWithUnmarkedFrontal() {
        let s = set(stage: .afterClosure, createdAt: t0)
        let status = SetStatus(set: s, index: 2, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos, 0 of 6 points placed.")
        XCTAssertEqual(status.shortLine, "3 photos, points not yet placed")
        XCTAssertEqual(status.gapLines, ["Set 2 has no points on its frontal photo"])
        if case .markPoints(_, let index, let capture, _, _)? = status.nextAction {
            XCTAssertEqual(index, 2)
            XCTAssertEqual(capture.angle, .frontal)
        } else {
            XCTFail("expected markPoints")
        }
    }

    func testPositioningLine() {
        let s = set(stage: .preoperativeMarking, createdAt: t0)
        let status = SetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.positioningLine(Positioning(tableAngle: "30°", armPosition: "at sides", lighting: "overhead light")),
                       "Table 30°, arms at sides, overhead light")
        XCTAssertEqual(status.positioningLine(Positioning()), "Positioning not recorded")
    }

    // MARK: - Practice tour

    func testPracticeTourTitles() {
        XCTAssertEqual(PracticeTourTask.allCases.map(\.title), [
            "Read the left and right result for set 1.",
            "Look at the obliques side by side.",
            "Mark the points on set 3.",
            "Take set 4 with the virtual camera.",
            "See how each difference changed across stages.",
        ])
        XCTAssertEqual(PracticeTourTask.allCases.map(\.rawValue), [1, 2, 3, 4, 5])
    }

    func testPracticeTourDoneRules() {
        let s1 = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)
        let s2 = set(stage: .afterResection, createdAt: t1, frontalLandmarks: sixPoints)
        let s3 = set(stage: .afterFatGrafting, createdAt: t2)
        var s = StudySession(studyID: "DEMO-VP1", captureSets: [s1, s2, s3])
        let sigma = settings.landmarkSigmaRatio

        var tour = PracticeTour(session: s, sigma: sigma)
        XCTAssertEqual(tour.items.map(\.isDone), [false, false, false, false, false])
        XCTAssertEqual(tour.nextTask, .readSet1)

        UIFlags.markViewed(setID: s1.id)
        tour = PracticeTour(session: s, sigma: sigma)
        XCTAssertEqual(tour.items.map(\.isDone), [true, false, false, false, false])
        XCTAssertEqual(tour.nextTask, .lookAtObliques)

        UIFlags.markSeenObliques(sessionID: s.id)
        var marked = s3
        marked.captures[.frontal]?.landmarks = sixPoints
        s.update(marked)
        tour = PracticeTour(session: s, sigma: sigma)
        XCTAssertEqual(tour.items.map(\.isDone), [true, true, true, false, false])
        XCTAssertEqual(tour.nextTask, .takeSet4)

        // An incomplete set 4 does not tick the task; a complete one does.
        s.update(set(stage: .afterClosure, createdAt: t3, angles: [.frontal]))
        XCTAssertFalse(PracticeTour(session: s, sigma: sigma).items[3].isDone)
        let set4 = set(stage: .afterClosure, createdAt: t3)
        s.captureSets.removeLast()
        s.update(set4)
        tour = PracticeTour(session: s, sigma: sigma)
        XCTAssertEqual(tour.items.map(\.isDone), [true, true, true, true, false])
        XCTAssertEqual(tour.nextTask, .acrossStages)

        UIFlags.markOpenedStages(sessionID: s.id)
        tour = PracticeTour(session: s, sigma: sigma)
        XCTAssertEqual(tour.items.map(\.isDone), [true, true, true, true, true])
        XCTAssertNil(tour.nextTask)
        XCTAssertEqual(tour.items.map(\.id), [1, 2, 3, 4, 5])
    }

    func testPracticeTourCountsALegacyCompareAsStages() {
        let s = StudySession(studyID: "DEMO-VP1", captureSets: [])
        UIFlags.defaults.set(true, forKey: "compared-" + s.id.uuidString)
        let tour = PracticeTour(session: s, sigma: settings.landmarkSigmaRatio)
        XCTAssertTrue(tour.items[4].isDone)
        XCTAssertFalse(tour.items[0].isDone)
    }
}
