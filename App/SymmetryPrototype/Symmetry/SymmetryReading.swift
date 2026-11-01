import Foundation
import SymmetryCore
import SymmetryModels

/// The constructions of the symmetry plate that can be brought forward one at a time.
enum PlateLayer: String, CaseIterable, Hashable {
    case all, nippleHeight, nippleMidline, foldHeight, outlines

    var title: String {
        switch self {
        case .all: return "All"
        case .nippleHeight: return "Nipple height"
        case .nippleMidline: return "Nipple to midline"
        case .foldHeight: return "Fold height"
        case .outlines: return "Outlines"
        }
    }
}

/// The four left-right readings of one frontal photo. Each one is a difference between the
/// patient's two sides (or, for the outlines, their overlap) and is never judged.
enum BilateralMetric: String, CaseIterable, Identifiable {
    case nippleHeight, nippleMidline, foldHeight, outlineOverlap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nippleHeight: return "Nipple height"
        case .nippleMidline: return "Nipple to midline"
        case .foldHeight: return "Fold height"
        case .outlineOverlap: return "Outline overlap"
        }
    }

    /// The metric's name in the exported report (`FrontalMetrics.namedMetrics`).
    var exportName: String {
        switch self {
        case .nippleHeight: return "Vertical nipple difference"
        case .nippleMidline: return "Nipple to midline difference"
        case .foldHeight: return "Inframammary fold height difference"
        case .outlineOverlap: return "Contour overlap"
        }
    }

    /// Scale end label on the screen-left side (patient right). Nil for the overlap.
    var patientRightEnd: String? {
        switch self {
        case .nippleHeight: return "Right lower"
        case .nippleMidline: return "Right farther"
        case .foldHeight: return "Right lower"
        case .outlineOverlap: return nil
        }
    }

    /// Scale end label on the screen-right side (patient left). Nil for the overlap.
    var patientLeftEnd: String? {
        switch self {
        case .nippleHeight: return "Left lower"
        case .nippleMidline: return "Left farther"
        case .foldHeight: return "Left lower"
        case .outlineOverlap: return nil
        }
    }

    var layer: PlateLayer {
        switch self {
        case .nippleHeight: return .nippleHeight
        case .nippleMidline: return .nippleMidline
        case .foldHeight: return .foldHeight
        case .outlineOverlap: return .outlines
        }
    }

    var zeroCaption: String {
        switch self {
        case .nippleHeight: return "Zero means both sides sit at the same height."
        case .nippleMidline: return "Zero means both nipples sit at the same distance from the midline."
        case .foldHeight: return "Zero means both sides sit at the same height."
        case .outlineOverlap: return "1 means the outlines coincide; 0 means they do not overlap."
        }
    }

    func measurement(in m: FrontalMetrics) -> MetricValue? {
        switch self {
        case .nippleHeight: return m.verticalNippleDifference
        case .nippleMidline: return m.nippleToMidlineDifference
        case .foldHeight: return m.imfHeightDifference
        case .outlineOverlap: return m.contourOverlap
        }
    }

    /// The point landmarks the metric needs. The two midline points are always needed.
    var requiredPoints: [LandmarkType] {
        switch self {
        case .nippleHeight, .nippleMidline: return [.sternalNotch, .midlineBottom, .leftNipple, .rightNipple]
        case .foldHeight: return [.sternalNotch, .midlineBottom, .leftIMF, .rightIMF]
        case .outlineOverlap: return [.sternalNotch, .midlineBottom]
        }
    }
}

/// One metric of one photo: its verbatim readout and either a sentence or a reason.
struct MetricReading: Identifiable {
    let metric: BilateralMetric
    let measurement: MetricValue?
    /// `MetricFormatter.text(measurement)`, verbatim.
    let readout: String
    /// The plain sentence for a measured value; nil when not measured.
    let sentence: String?
    /// Why the metric is not measured; nil when measured.
    let notMeasuredReason: String?
    /// |v| > u. For the overlap this is true whenever it is measured.
    let isDistinguishableFromZero: Bool

    var id: BilateralMetric { metric }
}

/// Everything the symmetry result shows for one frontal photo.
struct SetReading {
    let metrics: FrontalMetrics?
    /// Always four, in `BilateralMetric.allCases` order.
    let readings: [MetricReading]
    let leftToMidlineReadout: String
    let rightToMidlineReadout: String
    let flagSentences: [String]
    /// True when both midline points exist and are apart, so the photo can be turned upright.
    let canTurn: Bool

    init(landmarks: LandmarkSet?, sigma: Double, frontal: Capture? = nil) {
        let metrics = landmarks.map { FrontalMetricsCalculator.compute($0, landmarkSigmaRatio: sigma) }
        self.metrics = metrics
        let missing = landmarks?.missing ?? LandmarkType.allCases
        let flags = metrics?.flags ?? []
        self.readings = BilateralMetric.allCases.map { metric in
            let measurement = metrics.flatMap { metric.measurement(in: $0) }
            let distinguishable: Bool
            if let m = measurement {
                distinguishable = metric == .outlineOverlap ? true : abs(m.value) > m.uncertainty
            } else {
                distinguishable = false
            }
            return MetricReading(metric: metric,
                                 measurement: measurement,
                                 readout: MetricFormatter.text(measurement),
                                 sentence: measurement.map { ReadingCopy.sentence(for: metric, value: $0) },
                                 notMeasuredReason: measurement == nil
                                     ? ReadingCopy.notMeasuredReason(for: metric, missing: missing, flags: flags)
                                     : nil,
                                 isDistinguishableFromZero: distinguishable)
        }
        self.leftToMidlineReadout = MetricFormatter.text(metrics?.leftNippleToMidline)
        self.rightToMidlineReadout = MetricFormatter.text(metrics?.rightNippleToMidline)
        self.flagSentences = ReadingCopy.flagSentences(for: frontal)
        self.canTurn = landmarks.flatMap { MidlineFrame.from($0) } != nil
    }

    func reading(_ m: BilateralMetric) -> MetricReading {
        readings.first { $0.metric == m }!
    }

    /// The plate's accessibility label: each title, readout and sentence or reason, in order.
    var accessibilitySummary: String {
        readings.flatMap { r -> [String] in
            [r.metric.title, r.readout, r.sentence ?? r.notMeasuredReason].compactMap { $0 }
        }
        .joined(separator: " ")
    }
}

/// Every sentence the symmetry result says, as whole literals the copy guard can see.
enum ReadingCopy {
    /// The sentence for a measured value, chosen by sign and by whether |v| exceeds its ±.
    static func sentence(for metric: BilateralMetric, value: MetricValue) -> String {
        let v = value.value, u = value.uncertainty
        switch metric {
        case .nippleHeight:
            if v > u { return "The patient's left nipple sits lower than the right." }
            if v < -u { return "The patient's right nipple sits lower than the left." }
            return "The two nipple heights cannot be told apart: the difference is smaller than its ±."
        case .nippleMidline:
            if v > u { return "The patient's left nipple sits farther from the midline than the right." }
            if v < -u { return "The patient's right nipple sits farther from the midline than the left." }
            return "The two nipple distances from the midline cannot be told apart: the difference is smaller than its ±."
        case .foldHeight:
            if v > u { return "The patient's left fold sits lower than the right." }
            if v < -u { return "The patient's right fold sits lower than the left." }
            return "The two fold heights cannot be told apart: the difference is smaller than its ±."
        case .outlineOverlap:
            return "With the right outline mirrored onto the left, this is how much the two outlines overlap. 1 means they coincide; 0 means they do not overlap."
        }
    }

    /// Why a metric is not measured. Checks run in a fixed order: the midline first, then a
    /// coincident midline, then the side points (or the outlines).
    static func notMeasuredReason(for metric: BilateralMetric, missing: [LandmarkType], flags: [ReliabilityFlag]) -> String {
        if missing.contains(.sternalNotch) || missing.contains(.midlineBottom) {
            return "Not measured: place the sternal notch and the midline bottom first."
        }
        if flags.contains(.degenerateMidline) {
            return "Not measured: the notch and the midline bottom are on the same spot. Move one of them."
        }
        switch metric {
        case .nippleHeight, .nippleMidline:
            let left = missing.contains(.leftNipple), right = missing.contains(.rightNipple)
            if left && !right { return "Not measured: place the patient left nipple." }
            if right && !left { return "Not measured: place the patient right nipple." }
            return "Not measured: place both nipples."
        case .foldHeight:
            let left = missing.contains(.leftIMF), right = missing.contains(.rightIMF)
            if left && !right { return "Not measured: place the patient left fold." }
            if right && !left { return "Not measured: place the patient right fold." }
            return "Not measured: place both folds."
        case .outlineOverlap:
            return "Not measured: draw both outlines with at least 8 points each."
        }
    }

    /// One caution sentence per photo-check issue of the frontal photo. A photo without a
    /// check report says so; a passed, not overridden photo has none.
    static func flagSentences(for capture: Capture?) -> [String] {
        guard let capture else { return [] }
        guard let quality = capture.quality else {
            return ["This photo was not checked for blur, light or tilt."]
        }
        guard capture.qualityOverridden || !quality.passed else { return [] }
        return quality.failures.map { failure in
            switch failure {
            case .blurry: return "This photo was kept with a blur warning. Treat its points with care."
            case .overexposed: return "This photo was kept with a too-bright warning. Treat its points with care."
            case .underexposed: return "This photo was kept with a too-dark warning. Treat its points with care."
            case .tilted: return "This photo was kept with a tilt warning. Treat its points with care."
            }
        }
    }

    static let photoTurnedCaption = "Photo turned so the midline runs straight down."
    static let cannotTurnCaption = "Place the sternal notch and the midline bottom to turn the photo upright."
    static let referenceCaption = "L is the distance from the sternal notch to the midline bottom in this photo. Every value is a share of L."
    static let practiceMidlineCaption = "On the virtual patient the midline bottom is the umbilicus."
    static let overlapLegend: [String] = [
        "Patient left outline",
        "Patient right outline, mirrored onto the left side",
        "Where the outlines overlap",
        "Only inside the left outline",
        "Only inside the mirrored right outline",
    ]
    static let obliquesCaption = "Right oblique, flipped so both sides face the same way."
    static let obliquesNote = "Nothing is measured on oblique photos. Look at them side by side."
}

/// The readings of every set with a frontal photo, for the across-stages view.
struct StageSeries {
    struct Entry: Identifiable {
        let id: UUID
        let index: Int
        /// "Set 1, preoperative marking"
        let title: String
        let reading: SetReading
    }

    struct Row: Identifiable, Hashable {
        /// The set index.
        let id: Int
        /// "Set 1"
        let label: String
        let measurement: MetricValue?
    }

    let entries: [Entry]
    private let measuredIDs: Set<UUID>

    init(session: StudySession, sigma: Double) {
        var entries: [Entry] = []
        var measured: Set<UUID> = []
        for (offset, set) in session.orderedCaptureSets.enumerated() {
            guard let frontal = set.frontal else { continue }
            let index = offset + 1
            entries.append(Entry(id: set.id, index: index,
                                 title: SessionWizard.title(index: index, stage: set.stage),
                                 reading: SetReading(landmarks: frontal.landmarks, sigma: sigma, frontal: frontal)))
            if SessionWizard.isMeasured(set, sigma: sigma) { measured.insert(set.id) }
        }
        self.entries = entries
        self.measuredIDs = measured
    }

    /// Sets whose frontal photo has all six points and could be normalized.
    var measuredCount: Int { entries.filter { measuredIDs.contains($0.id) }.count }

    /// One row per set with a frontal photo; `measurement` is nil when not measured.
    func rows(for metric: BilateralMetric) -> [Row] {
        entries.map { entry in
            Row(id: entry.index, label: "Set \(entry.index)", measurement: entry.reading.reading(metric).measurement)
        }
    }

    /// "Set 1, preoperative marking: +0.071 ± 0.021 L", or the title and the reason.
    func readoutLines(for metric: BilateralMetric) -> [String] {
        entries.map { entry in
            let r = entry.reading.reading(metric)
            if r.measurement != nil {
                return "\(entry.title): \(r.readout)"
            }
            return "\(entry.title). \(r.notMeasuredReason ?? r.readout)"
        }
    }
}
