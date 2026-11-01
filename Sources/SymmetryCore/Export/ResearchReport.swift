import Foundation

/// Settings in force when a report was generated.
public struct ReportSettings: Codable, Equatable, Sendable {
    public let landmarkSigmaRatio: Double
    public let qualityThresholds: QualityThresholds
    public let maxResidualRatio: Double

    public init(landmarkSigmaRatio: Double, qualityThresholds: QualityThresholds, maxResidualRatio: Double) {
        self.landmarkSigmaRatio = landmarkSigmaRatio
        self.qualityThresholds = qualityThresholds
        self.maxResidualRatio = maxResidualRatio
    }
}

/// De-identified summary of one capture. Image data is never part of the JSON.
public struct CaptureSummary: Codable, Equatable, Sendable {
    public let angle: ViewAngle
    public let capturedAt: Date
    public let quality: QualityReport?
    public let qualityOverridden: Bool
    public let landmarks: LandmarkSet?
    public let frontalMetrics: FrontalMetrics?

    public init(angle: ViewAngle, capturedAt: Date, quality: QualityReport?, qualityOverridden: Bool,
                landmarks: LandmarkSet?, frontalMetrics: FrontalMetrics?) {
        self.angle = angle
        self.capturedAt = capturedAt
        self.quality = quality
        self.qualityOverridden = qualityOverridden
        self.landmarks = landmarks
        self.frontalMetrics = frontalMetrics
    }
}

public struct CaptureSetSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let stageLabel: String
    public let positioningNote: String
    public let capturedAt: Date
    public let captures: [CaptureSummary]

    public init(id: UUID, stageLabel: String, positioningNote: String, capturedAt: Date, captures: [CaptureSummary]) {
        self.id = id
        self.stageLabel = stageLabel
        self.positioningNote = positioningNote
        self.capturedAt = capturedAt
        self.captures = captures
    }
}

public struct ComparisonSummary: Codable, Equatable, Sendable {
    public let baselineSetID: UUID
    public let currentSetID: UUID
    public let result: CaptureComparison

    public init(baselineSetID: UUID, currentSetID: UUID, result: CaptureComparison) {
        self.baselineSetID = baselineSetID
        self.currentSetID = currentSetID
        self.result = result
    }
}

/// The exportable research report. Contains no identifiers beyond the study ID and no
/// images; images are exported separately and only on request.
public struct ResearchReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let researchNotice =
        "Research prototype output. Values are normalized image geometry from hand-placed landmarks, " +
        "not clinically validated, with no physical calibration. They carry the stated uncertainty and flags " +
        "and must not inform any surgical decision."

    public let schemaVersion: Int
    public let studyID: String
    public let generatedAt: Date
    public let notice: String
    public let settings: ReportSettings
    public let captureSets: [CaptureSetSummary]
    public let comparisons: [ComparisonSummary]

    public init(studyID: String, generatedAt: Date, settings: ReportSettings,
                captureSets: [CaptureSetSummary], comparisons: [ComparisonSummary]) {
        self.schemaVersion = ResearchReport.currentSchemaVersion
        self.studyID = studyID
        self.generatedAt = generatedAt
        self.notice = ResearchReport.researchNotice
        self.settings = settings
        self.captureSets = captureSets
        self.comparisons = comparisons
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    public func jsonData() throws -> Data { try ResearchReport.encoder().encode(self) }

    public static func decode(from data: Data) throws -> ResearchReport {
        try decoder().decode(ResearchReport.self, from: data)
    }
}
