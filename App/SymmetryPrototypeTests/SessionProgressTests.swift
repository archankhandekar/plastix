import XCTest
import SymmetryCore
import SymmetryModels
@testable import SymmetryPrototype

/// Pure-logic tests for the wizard: every state and next action comes from in-memory
/// fixtures, no files and no images.
final class SessionProgressTests: XCTestCase {
    private let settings = ReportSettings(landmarkSigmaRatio: FrontalMetricsCalculator.defaultLandmarkSigmaRatio,
                                          qualityThresholds: QualityThresholds(),
                                          maxResidualRatio: Registration.defaultMaxResidualRatio)

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

    private func session(_ sets: [CaptureSet]) -> StudySession {
        StudySession(studyID: "S-014", captureSets: sets)
    }

    private func progress(_ sets: [CaptureSet], hasCompared: Bool = false) -> SessionProgress {
        SessionProgress(session: session(sets), settings: settings, hasCompared: hasCompared)
    }

    // MARK: - Next action and step states

    func testEmptySessionAsksForTheFirstPhotos() {
        let p = progress([])
        XCTAssertEqual(p.next.title, "Next: Take the first 3 photos")
        XCTAssertEqual(p.next.detail, "Preoperative marking. Frontal, then left oblique, then right oblique. About one minute.")
        XCTAssertEqual(p.states[.takePhotos], .current("Not started"))
        XCTAssertEqual(p.states[.markPoints], .upcoming("Needs photos first"))
        XCTAssertEqual(p.states[.compare], .upcoming("Needs two measured sets"))
        XCTAssertEqual(p.states[.export], .upcoming("Needs at least one measured set"))
        XCTAssertEqual(p.currentStep, .takePhotos)
        XCTAssertEqual(p.summaryLine, "0 photo sets · Next: Take the first 3 photos")
        if case .newSet(let stage, let positioning, let index, _, _) = p.next {
            XCTAssertEqual(stage, .preoperativeMarking)
            XCTAssertNil(positioning)
            XCTAssertNil(index)
        } else {
            XCTFail("expected newSet, got \(p.next)")
        }
    }

    func testIncompleteSetAsksForTheMissingPhoto() {
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique])])
        XCTAssertEqual(p.next.title, "Next: Take the missing photo")
        XCTAssertEqual(p.next.detail, "Set 1 still needs: Right oblique")
        XCTAssertEqual(p.states[.takePhotos], .current("2 of 3 photos taken in set 1"))
        XCTAssertEqual(p.states[.markPoints], .upcoming("Needs photos first"))
        XCTAssertEqual(p.firstIncomplete?.index, 1)
        XCTAssertFalse(p.isActionable(.markPoints))
    }

    func testTwoMissingPhotosUsesThePlural() {
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal])])
        XCTAssertEqual(p.next.title, "Next: Take the missing photos")
        XCTAssertEqual(p.next.detail, "Set 1 still needs: Left oblique, Right oblique")
    }

    func testCompleteSetWithoutLandmarksAsksForPoints() {
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0)])
        XCTAssertEqual(p.next.title, "Next: Mark 6 points on the frontal photo")
        XCTAssertTrue(p.next.detail.hasSuffix("0 of 6 marked"), p.next.detail)
        XCTAssertEqual(p.next.detail, "Set 1 · Preoperative marking · 0 of 6 marked")
        XCTAssertEqual(p.states[.takePhotos], .done("1 set complete"))
        XCTAssertEqual(p.states[.markPoints], .current("0 of 6 points marked on set 1"))
        XCTAssertTrue(p.isActionable(.markPoints))
        XCTAssertFalse(p.isActionable(.export))
    }

    func testPartiallyMarkedFrontalCountsThePoints() {
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: twoPoints)])
        XCTAssertEqual(p.next.detail, "Set 1 · Preoperative marking · 2 of 6 marked")
        XCTAssertEqual(p.states[.markPoints], .current("2 of 6 points marked on set 1"))
    }

    func testOneMeasuredSetAsksForTheNextStage() {
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints)])
        XCTAssertEqual(p.measuredSets.count, 1)
        XCTAssertEqual(p.next.title, "Next: Take 3 photos at the next stage")
        XCTAssertEqual(p.next.detail, "You have 1 measured set. A second set at a later stage lets you compare.")
        XCTAssertEqual(p.states[.markPoints], .done("Set 1 measured"))
        XCTAssertEqual(p.states[.compare], .upcoming("Needs two measured sets"))
        XCTAssertEqual(p.states[.export], .upcoming("Ready"))
        XCTAssertTrue(p.isActionable(.export))
        XCTAssertEqual(SessionProgress.suggestedStage(after: .preoperativeMarking), .afterResection)
        if case .newSet(let stage, let positioning, let index, _, _) = p.next {
            XCTAssertEqual(stage, .afterResection)
            XCTAssertEqual(positioning?.tableAngle, "30°")
            XCTAssertEqual(index, 1)
        } else {
            XCTFail("expected newSet, got \(p.next)")
        }
    }

    func testSuggestedStageClampsAndKeepsCustom() {
        XCTAssertEqual(SessionProgress.suggestedStage(after: nil), .preoperativeMarking)
        XCTAssertEqual(SessionProgress.suggestedStage(after: .afterClosure), .afterClosure)
        XCTAssertEqual(SessionProgress.suggestedStage(after: .custom("Lateral check")), .custom("Lateral check"))
    }

    func testTwoMeasuredSetsAskToCompare() {
        let p = progress([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints),
        ])
        XCTAssertEqual(p.next.title, "Next: Compare set 1 with set 2")
        XCTAssertEqual(p.next.detail, "Both sets have all 6 points marked.")
        XCTAssertEqual(p.states[.takePhotos], .done("2 sets complete"))
        XCTAssertEqual(p.states[.markPoints], .done("2 sets measured"))
        XCTAssertEqual(p.states[.compare], .current("Ready: set 1 and set 2"))
        XCTAssertEqual(p.states[.export], .upcoming("Ready"))
        XCTAssertTrue(p.isActionable(.compare))
        if case .compare(_, let earlierIndex, _, let laterIndex, _, _) = p.next {
            XCTAssertEqual(earlierIndex, 1)
            XCTAssertEqual(laterIndex, 2)
        } else {
            XCTFail("expected compare, got \(p.next)")
        }
    }

    func testAfterComparingTheNextStepIsExport() {
        let p = progress([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: sixPoints),
        ], hasCompared: true)
        XCTAssertEqual(p.next.title, "Next: Export the report")
        XCTAssertEqual(p.next.detail, "2 measured sets, 1 comparison.")
        XCTAssertEqual(p.states[.compare], .done("Viewed"))
        XCTAssertEqual(p.states[.export], .current("Ready"))
        XCTAssertEqual(p.currentStep, .export)
    }

    func testSummaryLineCountsSetsAndNamesTheNextAction() {
        let p = progress([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1),
        ])
        XCTAssertEqual(p.summaryLine, "2 photo sets · Next: Mark 6 points on the frontal photo")
        XCTAssertEqual(p.next.detail, "Set 2 · After closure · 0 of 6 marked")
    }

    func testDegenerateMidlineIsNotMeasured() {
        var degenerate = sixPoints
        degenerate[.midlineBottom] = degenerate[.sternalNotch]
        let p = progress([set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: degenerate)])
        XCTAssertTrue(p.measuredSets.isEmpty)
        XCTAssertEqual(p.states[.export], .upcoming("Needs at least one measured set"))
    }

    func testCoincidentMidlineRoutesBackToMarkPoints() {
        var degenerate = sixPoints
        degenerate[.midlineBottom] = degenerate[.sternalNotch]
        let only = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: degenerate)
        let p = progress([only])
        XCTAssertEqual(p.next.title, "Next: Move the midline points apart on the frontal photo")
        XCTAssertEqual(p.next.detail, "Set 1 · The two midline points are on top of each other. Move one so they are apart.")
        XCTAssertEqual(p.currentStep, .markPoints)
        XCTAssertEqual(p.states[.markPoints], .current("Midline points on top of each other on set 1"))
        XCTAssertEqual(p.states[.compare], .upcoming("Needs two measured sets"))
        if case .markPoints(let set, let index, let capture, _, _) = p.next {
            XCTAssertEqual(set.id, only.id)
            XCTAssertEqual(index, 1)
            XCTAssertEqual(capture.angle, .frontal)
        } else {
            XCTFail("expected markPoints, got \(p.next)")
        }

        let status = CaptureSetStatus(set: only, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertFalse(status.isMeasured)
        XCTAssertEqual(status.nextAction?.title, "Move the midline points apart")
        XCTAssertEqual(status.gapLines, ["Set 1 has its two midline points on top of each other on its frontal photo"])
    }

    func testCoincidentMidlineOnALaterSetComesBeforeANewStage() {
        var degenerate = sixPoints
        degenerate[.midlineBottom] = degenerate[.sternalNotch]
        let p = progress([
            set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints),
            set(stage: .afterClosure, createdAt: t1, frontalLandmarks: degenerate),
        ])
        XCTAssertEqual(p.measuredSets.count, 1)
        XCTAssertEqual(p.next.title, "Next: Move the midline points apart on the frontal photo")
        XCTAssertEqual(p.next.detail, "Set 2 · The two midline points are on top of each other. Move one so they are apart.")
        XCTAssertEqual(p.states[.markPoints], .current("Midline points on top of each other on set 2"))
    }

    func testIndexAndTitleOfSet() {
        let a = set(stage: .preoperativeMarking, createdAt: t0)
        let b = set(stage: .afterClosure, createdAt: t1)
        let s = session([b, a])   // stored out of order; ordering is by createdAt
        XCTAssertEqual(SessionProgress.index(of: a, in: s), 1)
        XCTAssertEqual(SessionProgress.index(of: b, in: s), 2)
        XCTAssertEqual(SessionProgress.title(of: b, in: s), "Set 2 · After closure")
    }

    // MARK: - CaptureSetStatus

    func testStatusLineWithOneWarning() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints, frontalQuality: blurred)
        let status = CaptureSetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos · 1 photo has a warning")
        XCTAssertEqual(status.warningCount, 1)
        XCTAssertEqual(status.uncheckedCount, 2)
        XCTAssertTrue(status.isMeasured)
        XCTAssertNil(status.nextAction)
        XCTAssertTrue(status.gapLines.isEmpty)
    }

    func testStatusLineWhenMeasured() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, frontalLandmarks: sixPoints, frontalQuality: passed)
        let status = CaptureSetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos · 6 of 6 points marked")
        XCTAssertEqual(status.title, "Set 1 · Preoperative marking")
        XCTAssertEqual(status.warningCount, 0)
        XCTAssertEqual(status.uncheckedCount, 2)
    }

    func testStatusLineWithMissingPhotos() {
        let s = set(stage: .preoperativeMarking, createdAt: t0, angles: [.frontal, .leftOblique])
        let status = CaptureSetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "2 of 3 photos · points not yet marked")
        XCTAssertEqual(status.missing, [.rightOblique])
        XCTAssertEqual(status.nextAction?.title, "Take the missing photo")
        XCTAssertEqual(status.nextAction?.detail, "Set 1 still needs: Right oblique")
        XCTAssertEqual(status.gapLines, ["Set 1 is missing Right oblique", "Set 1 has no points on its frontal photo"])
    }

    func testStatusLineWithPartialPoints() {
        let s = set(stage: .afterClosure, createdAt: t0, frontalLandmarks: twoPoints)
        let status = CaptureSetStatus(set: s, index: 2, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos · 2 of 6 points marked")
        XCTAssertEqual(status.pointsMarked, 2)
        XCTAssertFalse(status.isMeasured)
        XCTAssertEqual(status.nextAction?.title, "Mark points on the frontal photo")
        XCTAssertEqual(status.gapLines, ["Set 2 has 2 of 6 points on its frontal photo"])
    }

    func testStatusLineWithUnmarkedFrontal() {
        let s = set(stage: .afterClosure, createdAt: t0)
        let status = CaptureSetStatus(set: s, index: 2, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.line, "3 photos · 0 of 6 points marked")
        XCTAssertEqual(status.gapLines, ["Set 2 has no points on its frontal photo"])
    }

    func testPositioningLine() {
        let s = set(stage: .preoperativeMarking, createdAt: t0)
        let status = CaptureSetStatus(set: s, index: 1, sigma: settings.landmarkSigmaRatio)
        XCTAssertEqual(status.positioningLine(Positioning(tableAngle: "30°", armPosition: "at sides", lighting: "overhead light")),
                       "Table 30°, arms at sides, overhead light")
        XCTAssertEqual(status.positioningLine(Positioning()), "Positioning not recorded")
    }

    // MARK: - ComparedFlag

    func testComparedFlagRoundTrips() {
        let id = UUID()
        defer { ComparedFlag.clear(sessionID: id) }
        XCTAssertFalse(ComparedFlag.isSet(sessionID: id))
        ComparedFlag.mark(sessionID: id)
        XCTAssertTrue(ComparedFlag.isSet(sessionID: id))
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "compared-" + id.uuidString), true)
        ComparedFlag.clear(sessionID: id)
        XCTAssertFalse(ComparedFlag.isSet(sessionID: id))
        XCTAssertNil(UserDefaults.standard.object(forKey: "compared-" + id.uuidString))
    }
}
