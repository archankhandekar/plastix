import Foundation
import SymmetryCore
import SymmetryModels

/// The pure wizard logic every session-level screen derives its state from.
///
/// One value computes the four step states and exactly one next action from the model and
/// the UI-only flags. It never touches SwiftUI, never registers landmarks and never builds a
/// report: "measured" means the frontal photo has all six points and its metrics could be
/// normalized, nothing more.
struct SessionWizard {
    enum Step: Int, CaseIterable, Identifiable {
        case takePhotos = 1, markPoints, seeSides, export

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .takePhotos: return "Take photos"
            case .markPoints: return "Mark points"
            case .seeSides: return "See left and right"
            case .export: return "Export"
            }
        }
    }

    enum StepState: Equatable {
        case done(String), current(String), upcoming(String)

        var status: String {
            switch self {
            case .done(let s), .current(let s), .upcoming(let s): return s
            }
        }
    }

    enum Action {
        case newSet(suggestedStage: OperativeStage, previousPositioning: Positioning?, previousSetIndex: Int?, title: String, detail: String)
        case captureMissing(set: CaptureSet, index: Int, angles: [ViewAngle], title: String, detail: String)
        case markPoints(set: CaptureSet, index: Int, capture: Capture, title: String, detail: String)
        case viewSymmetry(set: CaptureSet, index: Int, title: String, detail: String)
        case acrossStages(title: String, detail: String)
        case export(title: String, detail: String)

        var title: String {
            switch self {
            case .newSet(_, _, _, let title, _),
                 .captureMissing(_, _, _, let title, _),
                 .markPoints(_, _, _, let title, _),
                 .viewSymmetry(_, _, let title, _),
                 .acrossStages(let title, _),
                 .export(let title, _):
                return title
            }
        }

        var detail: String {
            switch self {
            case .newSet(_, _, _, _, let detail),
                 .captureMissing(_, _, _, _, let detail),
                 .markPoints(_, _, _, _, let detail),
                 .viewSymmetry(_, _, _, let detail),
                 .acrossStages(_, let detail),
                 .export(_, let detail):
                return detail
            }
        }

        var step: Step {
            switch self {
            case .newSet, .captureMissing: return .takePhotos
            case .markPoints: return .markPoints
            case .viewSymmetry, .acrossStages: return .seeSides
            case .export: return .export
            }
        }

        /// The route that performs this action. Taking photos has no route: session home
        /// performs `newSet` and `captureMissing` itself.
        func route(_ ref: SessionRef) -> AppRoute? {
            switch self {
            case .newSet, .captureMissing:
                return nil
            case .markPoints(let set, _, let capture, _, _):
                return .markPoints(ref, setID: set.id, captureID: capture.id)
            case .viewSymmetry(let set, _, _, _):
                return .symmetry(ref, setID: set.id)
            case .acrossStages:
                return .acrossStages(ref)
            case .export:
                return .export(ref)
            }
        }
    }

    let kind: SessionKind
    let states: [Step: StepState]
    let currentStep: Step
    let next: Action
    /// Sets whose frontal photo has all six points and whose metrics could be normalized.
    let measuredSets: [CaptureSet]
    let measuredIndexed: [(index: Int, set: CaptureSet)]
    let firstIncomplete: (index: Int, set: CaptureSet)?
    /// The newest measured set, else the newest set; nil for an empty session.
    let focusSet: (index: Int, set: CaptureSet)?
    /// "2 photo sets. Next: Mark the points on set 2."
    let summaryLine: String
    let viewedSetIDs: Set<UUID>
    let hasOpenedStages: Bool

    private let completeSetsWithFrontal: [(index: Int, set: CaptureSet)]

    /// Reads the UI-only flags from `UIFlags`.
    init(session: StudySession, settings: ReportSettings, kind: SessionKind = .study) {
        self.init(session: session, settings: settings, kind: kind,
                  viewedSetIDs: UIFlags.viewedSetIDs(in: session),
                  hasOpenedStages: UIFlags.hasOpenedStages(sessionID: session.id))
    }

    init(session: StudySession, settings: ReportSettings, kind: SessionKind = .study,
         viewedSetIDs: Set<UUID>, hasOpenedStages: Bool) {
        self.kind = kind
        self.viewedSetIDs = viewedSetIDs
        self.hasOpenedStages = hasOpenedStages
        let sigma = settings.landmarkSigmaRatio
        let indexed = session.orderedCaptureSets.enumerated().map { (index: $0.offset + 1, set: $0.element) }

        let firstIncomplete = indexed.first { !$0.set.isComplete }
        self.firstIncomplete = firstIncomplete

        let completeWithFrontal = indexed.filter { $0.set.isComplete && $0.set.frontal != nil }
        self.completeSetsWithFrontal = completeWithFrontal

        let measuredIndexed = indexed.filter { SessionWizard.isMeasured($0.set, sigma: sigma) }
        self.measuredIndexed = measuredIndexed
        let measured = measuredIndexed.map(\.set)
        self.measuredSets = measured
        self.focusSet = measuredIndexed.last ?? indexed.last

        let firstUnviewed = measuredIndexed.first { !viewedSetIDs.contains($0.set.id) }

        // Exactly one next action, first matching rule wins.
        let next: Action
        if let incomplete = firstIncomplete {
            let angles = incomplete.set.missingAngles
            let i = incomplete.index
            next = .captureMissing(set: incomplete.set, index: i, angles: angles,
                                   title: angles.count == 1 ? "Take the missing photo for set \(i)" : "Take the missing photos for set \(i)",
                                   detail: SessionWizard.missingDetail(index: i, angles: angles))
        } else if let unmarked = indexed.first(where: { $0.set.frontal != nil && $0.set.frontal?.landmarks?.isComplete != true }),
                  let frontal = unmarked.set.frontal {
            next = .markPoints(set: unmarked.set, index: unmarked.index, capture: frontal,
                               title: "Mark the points on set \(unmarked.index)",
                               detail: SessionWizard.markPointsDetail(index: unmarked.index, set: unmarked.set))
        } else if let coincident = completeWithFrontal.first(where: { SessionWizard.hasCoincidentMidline($0.set, sigma: sigma) }),
                  let frontal = coincident.set.frontal {
            // All six points are placed but the two midline points sit on one spot, so the
            // set cannot be measured. Fixing it comes before anything else.
            next = .markPoints(set: coincident.set, index: coincident.index, capture: frontal,
                               title: "Move the midline points apart on set \(coincident.index)",
                               detail: SessionWizard.coincidentMidlineDetail(index: coincident.index))
        } else if indexed.isEmpty {
            next = SessionWizard.firstSetAction
        } else if let unviewed = firstUnviewed {
            next = .viewSymmetry(set: unviewed.set, index: unviewed.index,
                                 title: "See left and right for set \(unviewed.index)",
                                 detail: SessionWizard.measuredDetail(index: unviewed.index, set: unviewed.set))
        } else if measured.count < 2, let last = indexed.last {
            let suggested = SessionWizard.suggestedStage(after: last.set.stage)
            next = .newSet(suggestedStage: suggested,
                           previousPositioning: last.set.positioning, previousSetIndex: last.index,
                           title: "Take 3 photos at the next stage",
                           detail: "Suggested stage: \(suggested.label).")
        } else if !hasOpenedStages {
            next = .acrossStages(title: "See how each difference changed across stages",
                                 detail: "\(measured.count) sets have all 6 points placed.")
        } else if kind == .practice {
            next = .export(title: "See what a report would contain", detail: "Practice sessions are not exported.")
        } else {
            // Rule 6 guarantees at least two measured sets here.
            next = .export(title: "Export the report", detail: "\(measured.count) measured sets.")
        }
        self.next = next
        self.currentStep = next.step

        // Step status strings.
        let takePhotosStatus: String
        if indexed.isEmpty {
            takePhotosStatus = "Not started"
        } else if let incomplete = firstIncomplete {
            takePhotosStatus = "\(incomplete.set.orderedCaptures.count) of 3 photos taken in set \(incomplete.index)"
        } else {
            takePhotosStatus = indexed.count == 1 ? "1 set complete" : "\(indexed.count) sets complete"
        }

        let markPointsStatus: String
        if completeWithFrontal.isEmpty {
            // An incomplete set can already have points on its frontal photo; say so
            // instead of hiding the work.
            let total = LandmarkType.allCases.count
            let placed = firstIncomplete.map { SessionWizard.pointsMarked(on: $0.set.frontal) } ?? 0
            if let incomplete = firstIncomplete, incomplete.set.frontal != nil, placed > 0 {
                markPointsStatus = placed == total
                    ? "Set \(incomplete.index) placed, photos still missing"
                    : "\(placed) of \(total) points placed on set \(incomplete.index), photos still missing"
            } else {
                markPointsStatus = "Needs photos first"
            }
        } else if let unmarked = completeWithFrontal.first(where: { $0.set.frontal?.landmarks?.isComplete != true }) {
            let placed = SessionWizard.pointsMarked(on: unmarked.set.frontal)
            markPointsStatus = "\(placed) of 6 points placed on set \(unmarked.index)"
        } else if let coincident = completeWithFrontal.first(where: { SessionWizard.hasCoincidentMidline($0.set, sigma: sigma) }) {
            markPointsStatus = "Midline points on top of each other on set \(coincident.index)"
        } else if measuredIndexed.count == 1, let only = measuredIndexed.first {
            markPointsStatus = "Set \(only.index) measured"
        } else {
            markPointsStatus = "\(measuredIndexed.count) sets measured"
        }

        let seeSidesStatus: String
        if measuredIndexed.isEmpty {
            seeSidesStatus = "Needs a set with all 6 points"
        } else if let unviewed = firstUnviewed {
            seeSidesStatus = "Ready for set \(unviewed.index)"
        } else if measuredIndexed.count == 1, let only = measuredIndexed.first {
            seeSidesStatus = "Seen for set \(only.index)"
        } else {
            seeSidesStatus = "Seen for all \(measuredIndexed.count) measured sets"
        }

        let exportStatus: String
        if kind == .practice {
            exportStatus = "Not available for practice sessions"
        } else {
            exportStatus = measured.isEmpty ? "Needs at least one measured set" : "Ready"
        }

        let completed: [Step: Bool] = [
            .takePhotos: !indexed.isEmpty && firstIncomplete == nil,
            .markPoints: !completeWithFrontal.isEmpty
                && completeWithFrontal.allSatisfy { SessionWizard.isMeasured($0.set, sigma: sigma) },
            .seeSides: !measuredIndexed.isEmpty && firstUnviewed == nil,
            .export: false,
        ]
        let statuses: [Step: String] = [
            .takePhotos: takePhotosStatus,
            .markPoints: markPointsStatus,
            .seeSides: seeSidesStatus,
            .export: exportStatus,
        ]
        var states: [Step: StepState] = [:]
        for step in Step.allCases {
            let status = statuses[step] ?? ""
            if step == next.step {
                states[step] = .current(status)
            } else if completed[step] == true {
                states[step] = .done(status)
            } else {
                states[step] = .upcoming(status)
            }
        }
        self.states = states

        let n = indexed.count
        self.summaryLine = n == 1
            ? "1 photo set. Next: \(next.title)."
            : "\(n) photo sets. Next: \(next.title)."
    }

    /// Whether tapping a step row does anything. An upcoming step's status line already says why not.
    func isActionable(_ step: Step) -> Bool {
        switch step {
        case .takePhotos: return true
        case .markPoints: return !completeSetsWithFrontal.isEmpty
        case .seeSides: return measuredSets.count >= 1
        case .export: return measuredSets.count >= 1
        }
    }

    // MARK: - Shared rules

    /// 1-based position of the set in `session.orderedCaptureSets`; 0 when the set is not in the session.
    static func index(of set: CaptureSet, in session: StudySession) -> Int {
        (session.orderedCaptureSets.firstIndex { $0.id == set.id } ?? -1) + 1
    }

    /// "Set 2, after mastectomy or resection"
    static func title(of set: CaptureSet, in session: StudySession) -> String {
        title(index: index(of: set, in: session), stage: set.stage)
    }

    /// "Set 2, after mastectomy or resection", from an index and a stage.
    static func title(index: Int, stage: OperativeStage) -> String {
        "Set \(index), \(stageInSentence(stage))"
    }

    /// A preset label with its first letter lowercased; a custom label unchanged.
    static func stageInSentence(_ stage: OperativeStage) -> String {
        if case .custom(let text) = stage { return text }
        let label = stage.label
        guard let first = label.first else { return label }
        return first.lowercased() + label.dropFirst()
    }

    /// The stage to pre-select for a new set: the preset after the previous set's stage,
    /// clamped to the last preset; a custom stage suggests the same custom text.
    static func suggestedStage(after previous: OperativeStage?) -> OperativeStage {
        let presets = OperativeStage.presets
        guard let previous else { return presets[0] }
        guard let i = presets.firstIndex(of: previous) else { return previous }
        return presets[min(i + 1, presets.count - 1)]
    }

    static let firstSetAction: Action = .newSet(
        suggestedStage: OperativeStage.presets[0], previousPositioning: nil, previousSetIndex: nil,
        title: "Take the first 3 photos",
        detail: "Preoperative marking. Frontal, then left oblique, then right oblique. About one minute.")

    /// A set is measured when its frontal photo has all six points and the metrics could be
    /// normalized (the two midline points do not coincide).
    static func isMeasured(_ set: CaptureSet, sigma: Double) -> Bool {
        guard let frontal = set.frontal, frontal.landmarks?.isComplete == true,
              let metrics = frontal.frontalMetrics(sigma: sigma) else { return false }
        return !metrics.flags.contains(.degenerateMidline)
    }

    /// All six points are placed but the two midline points sit on one spot, so the set
    /// is complete yet not measured.
    static func hasCoincidentMidline(_ set: CaptureSet, sigma: Double) -> Bool {
        guard let frontal = set.frontal, frontal.landmarks?.isComplete == true,
              let metrics = frontal.frontalMetrics(sigma: sigma) else { return false }
        return metrics.flags.contains(.degenerateMidline)
    }

    /// 6 minus the missing points; 0 when there are no landmarks at all.
    static func pointsMarked(on capture: Capture?) -> Int {
        LandmarkType.allCases.count - (capture?.landmarks?.missing.count ?? LandmarkType.allCases.count)
    }

    /// "Set 1 still needs: Left oblique, Right oblique."
    static func missingDetail(index: Int, angles: [ViewAngle]) -> String {
        "Set \(index) still needs: \(angles.map(\.displayName).joined(separator: ", "))."
    }

    /// "Set 1, preoperative marking. 2 of 6 points placed."
    static func markPointsDetail(index: Int, set: CaptureSet) -> String {
        "\(title(index: index, stage: set.stage)). \(pointsMarked(on: set.frontal)) of 6 points placed."
    }

    /// "Set 1: the two midline points are on top of each other. Move one so they are apart."
    static func coincidentMidlineDetail(index: Int) -> String {
        "Set \(index): the two midline points are on top of each other. Move one so they are apart."
    }

    /// "Set 1, preoperative marking. All 6 points are placed."
    static func measuredDetail(index: Int, set: CaptureSet) -> String {
        "\(title(index: index, stage: set.stage)). All 6 points are placed."
    }
}

/// Plain-language status of one photo set for rows, the set photos screen and the export gap list.
struct SetStatus {
    let index: Int
    /// "Set 1, preoperative marking"
    let title: String
    let createdAt: Date
    let photosTaken: Int
    let missing: [ViewAngle]
    let pointsMarked: Int
    let isMeasured: Bool
    /// Captures with a quality report that did not pass.
    let warningCount: Int
    /// Captures that have no quality report at all.
    let uncheckedCount: Int
    /// "3 photos, 6 of 6 points placed."
    let line: String
    /// "3 photos, 6 of 6 points"
    let shortLine: String
    let nextAction: SessionWizard.Action?
    /// For Export: "Set 1 is missing Right oblique", "Set 2 has no points on its frontal photo",
    /// "Set 2 has 4 of 6 points on its frontal photo".
    let gapLines: [String]

    private static let photosPerSet = ViewAngle.allCases.count
    private static let pointsPerFrontal = LandmarkType.allCases.count

    init(set: CaptureSet, index: Int, sigma: Double) {
        self.index = index
        self.title = SessionWizard.title(index: index, stage: set.stage)
        self.createdAt = set.createdAt
        let photosTaken = set.orderedCaptures.count
        self.photosTaken = photosTaken
        let missing = set.missingAngles
        self.missing = missing
        let points = SessionWizard.pointsMarked(on: set.frontal)
        self.pointsMarked = points
        let measured = SessionWizard.isMeasured(set, sigma: sigma)
        self.isMeasured = measured
        let warnings = set.orderedCaptures.filter { capture in
            guard let q = capture.quality else { return false }
            return !q.passed
        }.count
        self.warningCount = warnings
        self.uncheckedCount = set.orderedCaptures.filter { $0.quality == nil }.count

        let total = SetStatus.photosPerSet
        let allPoints = SetStatus.pointsPerFrontal
        if photosTaken < total {
            self.line = points > 0
                ? "\(photosTaken) of \(total) photos, \(points) of \(allPoints) points placed."
                : "\(photosTaken) of \(total) photos, points not yet placed."
        } else if warnings > 0 {
            self.line = warnings == 1
                ? "\(total) photos, 1 photo has a warning."
                : "\(total) photos, \(warnings) photos have a warning."
        } else {
            self.line = "\(total) photos, \(points) of \(allPoints) points placed."
        }

        if photosTaken < total {
            self.shortLine = "\(photosTaken) of \(total) photos"
        } else if points == 0 {
            self.shortLine = "\(total) photos, points not yet placed"
        } else {
            self.shortLine = "\(total) photos, \(points) of \(allPoints) points"
        }

        if !missing.isEmpty {
            self.nextAction = .captureMissing(set: set, index: index, angles: missing,
                                              title: missing.count == 1 ? "Take the missing photo" : "Take the missing photos",
                                              detail: SessionWizard.missingDetail(index: index, angles: missing))
        } else if let frontal = set.frontal, frontal.landmarks?.isComplete != true {
            self.nextAction = .markPoints(set: set, index: index, capture: frontal,
                                          title: "Mark the points",
                                          detail: SessionWizard.markPointsDetail(index: index, set: set))
        } else if let frontal = set.frontal, SessionWizard.hasCoincidentMidline(set, sigma: sigma) {
            self.nextAction = .markPoints(set: set, index: index, capture: frontal,
                                          title: "Move the midline points apart",
                                          detail: SessionWizard.coincidentMidlineDetail(index: index))
        } else if measured {
            self.nextAction = .viewSymmetry(set: set, index: index, title: "See left and right",
                                            detail: SessionWizard.measuredDetail(index: index, set: set))
        } else {
            self.nextAction = nil
        }

        var gaps: [String] = []
        if !missing.isEmpty {
            gaps.append("Set \(index) is missing \(missing.map(\.displayName).joined(separator: ", "))")
        }
        if set.frontal != nil && points < allPoints {
            if points == 0 {
                gaps.append("Set \(index) has no points on its frontal photo")
            } else {
                gaps.append("Set \(index) has \(points) of \(allPoints) points on its frontal photo")
            }
        }
        if SessionWizard.hasCoincidentMidline(set, sigma: sigma) {
            gaps.append("Set \(index) has its two midline points on top of each other on its frontal photo")
        }
        self.gapLines = gaps
    }

    /// "Taken 10:42. 3 photos, 6 of 6 points."
    var takenLine: String {
        "Taken \(createdAt.formatted(date: .omitted, time: .shortened)). \(shortLine)."
    }

    /// "Table 30°, arms at sides, overhead light" from the non-empty fields, or "Positioning not recorded".
    func positioningLine(_ p: Positioning) -> String {
        let parts = [
            p.tableAngle.isEmpty ? nil : "Table \(p.tableAngle)",
            p.armPosition.isEmpty ? nil : "arms \(p.armPosition)",
            p.lighting.isEmpty ? nil : p.lighting,
            p.note.isEmpty ? nil : p.note,
        ].compactMap { $0 }
        return parts.isEmpty ? "Positioning not recorded" : parts.joined(separator: ", ")
    }
}

/// UI-only flags: which sets were looked at, and whether the across-stages view and the
/// obliques were opened. They are never part of the report and are not patient data.
enum UIFlags {
    /// Swapped for a wiped suite by tests and the DEBUG route harness.
    static var defaults: UserDefaults = .standard

    private static func viewedKey(_ setID: UUID) -> String { "viewed-" + setID.uuidString }
    private static func stagesKey(_ sessionID: UUID) -> String { "stages-" + sessionID.uuidString }
    private static func legacyComparedKey(_ sessionID: UUID) -> String { "compared-" + sessionID.uuidString }
    private static func obliquesKey(_ sessionID: UUID) -> String { "obliques-" + sessionID.uuidString }

    static func hasViewed(setID: UUID) -> Bool {
        defaults.bool(forKey: viewedKey(setID))
    }

    static func markViewed(setID: UUID) {
        defaults.set(true, forKey: viewedKey(setID))
    }

    static func viewedSetIDs(in session: StudySession) -> Set<UUID> {
        Set(session.captureSets.map(\.id).filter { hasViewed(setID: $0) })
    }

    /// True after the across-stages view was opened, or the legacy Compare screen was.
    static func hasOpenedStages(sessionID: UUID) -> Bool {
        defaults.bool(forKey: stagesKey(sessionID)) || defaults.bool(forKey: legacyComparedKey(sessionID))
    }

    static func markOpenedStages(sessionID: UUID) {
        defaults.set(true, forKey: stagesKey(sessionID))
    }

    static func hasSeenObliques(sessionID: UUID) -> Bool {
        defaults.bool(forKey: obliquesKey(sessionID))
    }

    static func markSeenObliques(sessionID: UUID) {
        defaults.set(true, forKey: obliquesKey(sessionID))
    }

    /// Removes every flag of the session and its sets.
    static func clear(session: StudySession) {
        for set in session.captureSets { defaults.removeObject(forKey: viewedKey(set.id)) }
        defaults.removeObject(forKey: stagesKey(session.id))
        defaults.removeObject(forKey: legacyComparedKey(session.id))
        defaults.removeObject(forKey: obliquesKey(session.id))
    }
}

/// The five tasks of the virtual patient tour.
enum PracticeTourTask: Int, CaseIterable, Identifiable {
    case readSet1 = 1, lookAtObliques, markSet3, takeSet4, acrossStages

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .readSet1: return "Read the left and right result for set 1."
        case .lookAtObliques: return "Look at the obliques side by side."
        case .markSet3: return "Mark the points on set 3."
        case .takeSet4: return "Take set 4 with the virtual camera."
        case .acrossStages: return "See how each difference changed across stages."
        }
    }
}

/// The tour checklist, ticked from model state and `UIFlags`.
struct PracticeTour {
    struct Item: Identifiable {
        let task: PracticeTourTask
        let isDone: Bool

        var id: Int { task.rawValue }
    }

    let items: [Item]

    var nextTask: PracticeTourTask? { items.first { !$0.isDone }?.task }

    init(session: StudySession, sigma: Double) {
        let sets = session.orderedCaptureSets
        func set(_ n: Int) -> CaptureSet? { sets.count >= n ? sets[n - 1] : nil }
        self.items = PracticeTourTask.allCases.map { task in
            let done: Bool
            switch task {
            case .readSet1: done = set(1).map { UIFlags.hasViewed(setID: $0.id) } ?? false
            case .lookAtObliques: done = UIFlags.hasSeenObliques(sessionID: session.id)
            case .markSet3: done = set(3).map { SessionWizard.isMeasured($0, sigma: sigma) } ?? false
            case .takeSet4: done = set(4)?.isComplete ?? false
            case .acrossStages: done = UIFlags.hasOpenedStages(sessionID: session.id)
            }
            return Item(task: task, isDone: done)
        }
    }
}
