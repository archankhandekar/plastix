import Foundation
import SymmetryCore
import SymmetryModels

/// The pure wizard logic every session-level screen derives its state from.
///
/// One value computes the four step states and exactly one next action from the existing
/// model. It never touches SwiftUI, never registers landmarks and never builds a report:
/// "measured" means the frontal photo has all six points and its metrics could be
/// normalized, nothing more.
struct SessionProgress {
    enum Step: Int, CaseIterable, Identifiable {
        case takePhotos = 1, markPoints, compare, export

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .takePhotos: return "Take photos"
            case .markPoints: return "Mark points"
            case .compare: return "Compare"
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

    enum NextAction {
        case newSet(suggestedStage: OperativeStage, previousPositioning: Positioning?, previousSetIndex: Int?, title: String, detail: String)
        case captureMissing(set: CaptureSet, index: Int, angles: [ViewAngle], title: String, detail: String)
        case markPoints(set: CaptureSet, index: Int, capture: Capture, title: String, detail: String)
        case compare(earlier: CaptureSet, earlierIndex: Int, later: CaptureSet, laterIndex: Int, title: String, detail: String)
        case export(title: String, detail: String)

        var title: String {
            switch self {
            case .newSet(_, _, _, let title, _),
                 .captureMissing(_, _, _, let title, _),
                 .markPoints(_, _, _, let title, _),
                 .compare(_, _, _, _, let title, _),
                 .export(let title, _):
                return title
            }
        }

        var detail: String {
            switch self {
            case .newSet(_, _, _, _, let detail),
                 .captureMissing(_, _, _, _, let detail),
                 .markPoints(_, _, _, _, let detail),
                 .compare(_, _, _, _, _, let detail),
                 .export(_, let detail):
                return detail
            }
        }

        var step: Step {
            switch self {
            case .newSet, .captureMissing: return .takePhotos
            case .markPoints: return .markPoints
            case .compare: return .compare
            case .export: return .export
            }
        }
    }

    let states: [Step: StepState]
    let currentStep: Step
    let next: NextAction
    /// Sets whose frontal photo has all six points and whose metrics could be normalized.
    let measuredSets: [CaptureSet]
    let firstIncomplete: (index: Int, set: CaptureSet)?
    /// "2 photo sets · Next: Mark 6 points on the frontal photo"
    let summaryLine: String
    let hasCompared: Bool

    private let completeSetsWithFrontal: [(index: Int, set: CaptureSet)]

    init(session: StudySession, settings: ReportSettings, hasCompared: Bool) {
        self.hasCompared = hasCompared
        let sigma = settings.landmarkSigmaRatio
        let ordered = session.orderedCaptureSets
        let indexed = ordered.enumerated().map { (index: $0.offset + 1, set: $0.element) }

        let firstIncomplete = indexed.first { !$0.set.isComplete }
        self.firstIncomplete = firstIncomplete

        let completeWithFrontal = indexed.filter { $0.set.isComplete && $0.set.frontal != nil }
        self.completeSetsWithFrontal = completeWithFrontal

        let measuredIndexed = indexed.filter { SessionProgress.isMeasured($0.set, sigma: sigma) }
        let measured = measuredIndexed.map(\.set)
        self.measuredSets = measured

        // Exactly one next action, first matching rule wins.
        let next: NextAction
        if let incomplete = firstIncomplete {
            let angles = incomplete.set.missingAngles
            next = .captureMissing(set: incomplete.set, index: incomplete.index, angles: angles,
                                   title: angles.count == 1 ? "Next: Take the missing photo" : "Next: Take the missing photos",
                                   detail: SessionProgress.missingDetail(index: incomplete.index, angles: angles))
        } else if let unmarked = indexed.first(where: { $0.set.frontal != nil && $0.set.frontal?.landmarks?.isComplete != true }),
                  let frontal = unmarked.set.frontal {
            next = .markPoints(set: unmarked.set, index: unmarked.index, capture: frontal,
                               title: "Next: Mark 6 points on the frontal photo",
                               detail: SessionProgress.markPointsDetail(index: unmarked.index, set: unmarked.set))
        } else if let coincident = completeWithFrontal.first(where: { SessionProgress.hasCoincidentMidline($0.set, sigma: sigma) }),
                  let frontal = coincident.set.frontal {
            // All six points are placed but the two midline points sit on one spot, so the
            // set cannot be measured. Fixing it comes before anything else.
            next = .markPoints(set: coincident.set, index: coincident.index, capture: frontal,
                               title: "Next: Move the midline points apart on the frontal photo",
                               detail: SessionProgress.coincidentMidlineDetail(index: coincident.index))
        } else if indexed.isEmpty {
            next = SessionProgress.firstSetAction
        } else if measured.count < 2, let last = indexed.last {
            let m = measured.count
            next = .newSet(suggestedStage: SessionProgress.suggestedStage(after: last.set.stage),
                           previousPositioning: last.set.positioning, previousSetIndex: last.index,
                           title: "Next: Take 3 photos at the next stage",
                           detail: "You have \(m) measured set\(m == 1 ? "" : "s"). A second set at a later stage lets you compare.")
        } else if !hasCompared, let first = measuredIndexed.first, let last = measuredIndexed.last, measured.count >= 2 {
            next = .compare(earlier: first.set, earlierIndex: first.index, later: last.set, laterIndex: last.index,
                            title: "Next: Compare set \(first.index) with set \(last.index)",
                            detail: "Both sets have all 6 points marked.")
        } else {
            let m = measured.count
            let c = m * (m - 1) / 2
            next = .export(title: "Next: Export the report",
                           detail: "\(m) measured sets, \(c) comparison\(c == 1 ? "" : "s").")
        }
        self.next = next
        self.currentStep = next.step

        // Step status strings (copy bank step1.* to step4.*).
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
            markPointsStatus = "Needs photos first"
        } else if let unmarked = completeWithFrontal.first(where: { $0.set.frontal?.landmarks?.isComplete != true }) {
            let marked = SessionProgress.pointsMarked(on: unmarked.set.frontal)
            markPointsStatus = "\(marked) of 6 points marked on set \(unmarked.index)"
        } else if let coincident = completeWithFrontal.first(where: { SessionProgress.hasCoincidentMidline($0.set, sigma: sigma) }) {
            markPointsStatus = "Midline points on top of each other on set \(coincident.index)"
        } else if measuredIndexed.count == 1, let only = measuredIndexed.first {
            markPointsStatus = "Set \(only.index) measured"
        } else {
            markPointsStatus = "\(measuredIndexed.count) sets measured"
        }

        let compareStatus: String
        if measured.count < 2 {
            compareStatus = "Needs two measured sets"
        } else if hasCompared {
            compareStatus = "Viewed"
        } else if let first = measuredIndexed.first, let last = measuredIndexed.last {
            compareStatus = "Ready: set \(first.index) and set \(last.index)"
        } else {
            compareStatus = "Needs two measured sets"
        }

        let exportStatus = measured.isEmpty ? "Needs at least one measured set" : "Ready"

        let completed: [Step: Bool] = [
            .takePhotos: !indexed.isEmpty && firstIncomplete == nil,
            .markPoints: !completeWithFrontal.isEmpty
                && completeWithFrontal.allSatisfy { SessionProgress.isMeasured($0.set, sigma: sigma) },
            .compare: hasCompared && measured.count >= 2,
            .export: false,
        ]
        let statuses: [Step: String] = [
            .takePhotos: takePhotosStatus,
            .markPoints: markPointsStatus,
            .compare: compareStatus,
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
        self.summaryLine = "\(n) photo set\(n == 1 ? "" : "s") · \(next.title)"
    }

    /// Whether tapping a step row does anything. An upcoming step's status line already says why not.
    func isActionable(_ step: Step) -> Bool {
        switch step {
        case .takePhotos: return true
        case .markPoints: return !completeSetsWithFrontal.isEmpty
        case .compare: return measuredSets.count >= 2
        case .export: return measuredSets.count >= 1
        }
    }

    /// 1-based position of the set in `session.orderedCaptureSets`; 0 when the set is not in the session.
    static func index(of set: CaptureSet, in session: StudySession) -> Int {
        (session.orderedCaptureSets.firstIndex { $0.id == set.id } ?? -1) + 1
    }

    /// "Set 1 · Preoperative marking"
    static func title(of set: CaptureSet, in session: StudySession) -> String {
        "Set \(index(of: set, in: session)) · \(set.stage.label)"
    }

    /// The stage to pre-select for a new set: the preset after the previous set's stage,
    /// clamped to the last preset; a custom stage suggests the same custom text.
    static func suggestedStage(after previous: OperativeStage?) -> OperativeStage {
        let presets = OperativeStage.presets
        guard let previous else { return presets[0] }
        guard let i = presets.firstIndex(of: previous) else { return previous }
        return presets[min(i + 1, presets.count - 1)]
    }

    // MARK: - Shared rules

    static let firstSetAction: NextAction = .newSet(
        suggestedStage: OperativeStage.presets[0], previousPositioning: nil, previousSetIndex: nil,
        title: "Next: Take the first 3 photos",
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

    /// "Set 1 · The two midline points are on top of each other. Move one so they are apart."
    static func coincidentMidlineDetail(index: Int) -> String {
        "Set \(index) · The two midline points are on top of each other. Move one so they are apart."
    }

    /// 6 minus the missing points; 0 when there are no landmarks at all.
    static func pointsMarked(on capture: Capture?) -> Int {
        LandmarkType.allCases.count - (capture?.landmarks?.missing.count ?? LandmarkType.allCases.count)
    }

    static func missingDetail(index: Int, angles: [ViewAngle]) -> String {
        "Set \(index) still needs: \(angles.map(\.displayName).joined(separator: ", "))"
    }

    static func markPointsDetail(index: Int, set: CaptureSet) -> String {
        "Set \(index) · \(set.stage.label) · \(pointsMarked(on: set.frontal)) of 6 marked"
    }
}

/// Plain-language status of one photo set for cards, the set screen and the export gap list.
struct CaptureSetStatus {
    let index: Int
    /// "Set 1 · Preoperative marking"
    let title: String
    let photosTaken: Int
    let missing: [ViewAngle]
    let pointsMarked: Int
    let isMeasured: Bool
    /// Captures with a quality report that did not pass.
    let warningCount: Int
    /// Captures that have no quality report at all.
    let uncheckedCount: Int
    let line: String
    let nextAction: SessionProgress.NextAction?
    /// For Export: "Set 1 is missing Right oblique", "Set 2 has no points on its frontal photo",
    /// "Set 2 has 4 of 6 points on its frontal photo".
    let gapLines: [String]

    private static let photosPerSet = ViewAngle.allCases.count
    private static let pointsPerFrontal = LandmarkType.allCases.count

    init(set: CaptureSet, index: Int, sigma: Double) {
        self.index = index
        self.title = "Set \(index) · \(set.stage.label)"
        let photosTaken = set.orderedCaptures.count
        self.photosTaken = photosTaken
        let missing = set.missingAngles
        self.missing = missing
        let points = SessionProgress.pointsMarked(on: set.frontal)
        self.pointsMarked = points
        self.isMeasured = SessionProgress.isMeasured(set, sigma: sigma)
        let warnings = set.orderedCaptures.filter { capture in
            guard let q = capture.quality else { return false }
            return !q.passed
        }.count
        self.warningCount = warnings
        self.uncheckedCount = set.orderedCaptures.filter { $0.quality == nil }.count

        let total = CaptureSetStatus.photosPerSet
        let allPoints = CaptureSetStatus.pointsPerFrontal
        if photosTaken < total {
            let pointsPart = points > 0 ? "\(points) of \(allPoints) points marked" : "points not yet marked"
            self.line = "\(photosTaken) of \(total) photos · \(pointsPart)"
        } else if warnings > 0 {
            self.line = "\(total) photos · \(warnings == 1 ? "1 photo has a warning" : "\(warnings) photos have a warning")"
        } else {
            self.line = "\(total) photos · \(points) of \(allPoints) points marked"
        }

        if !missing.isEmpty {
            self.nextAction = .captureMissing(set: set, index: index, angles: missing,
                                              title: missing.count == 1 ? "Take the missing photo" : "Take the missing photos",
                                              detail: SessionProgress.missingDetail(index: index, angles: missing))
        } else if let frontal = set.frontal, frontal.landmarks?.isComplete != true {
            self.nextAction = .markPoints(set: set, index: index, capture: frontal,
                                          title: "Mark points on the frontal photo",
                                          detail: SessionProgress.markPointsDetail(index: index, set: set))
        } else if let frontal = set.frontal, SessionProgress.hasCoincidentMidline(set, sigma: sigma) {
            self.nextAction = .markPoints(set: set, index: index, capture: frontal,
                                          title: "Move the midline points apart",
                                          detail: SessionProgress.coincidentMidlineDetail(index: index))
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
        if SessionProgress.hasCoincidentMidline(set, sigma: sigma) {
            gaps.append("Set \(index) has its two midline points on top of each other on its frontal photo")
        }
        self.gapLines = gaps
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

/// Remembers that the Compare screen was opened for a session. UI convenience only: it is
/// never part of the report and is simply orphaned when the session is deleted.
enum ComparedFlag {
    private static func key(_ sessionID: UUID) -> String { "compared-" + sessionID.uuidString }

    static func isSet(sessionID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(sessionID))
    }

    static func mark(sessionID: UUID) {
        UserDefaults.standard.set(true, forKey: key(sessionID))
    }

    static func clear(sessionID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(sessionID))
    }
}
