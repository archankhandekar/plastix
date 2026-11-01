import Foundation
import SymmetryCore

/// One photograph at one view angle, with everything derived from it.
public struct Capture: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var angle: ViewAngle
    /// File name of the JPEG inside the session directory.
    public let imageFilename: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let capturedAt: Date
    public var quality: QualityReport?
    /// Phone roll at capture time, degrees from level. Describes the phone, not the camera's
    /// pose relative to the patient.
    public let tiltDegrees: Double?
    /// True when the user kept the image despite a failed quality check.
    public var qualityOverridden: Bool
    public var landmarks: LandmarkSet?

    public init(id: UUID = UUID(), angle: ViewAngle, imageFilename: String, pixelWidth: Int, pixelHeight: Int,
                capturedAt: Date = Date(), quality: QualityReport?, tiltDegrees: Double?,
                qualityOverridden: Bool = false, landmarks: LandmarkSet? = nil) {
        self.id = id
        self.angle = angle
        self.imageFilename = imageFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capturedAt = capturedAt
        self.quality = quality
        self.tiltDegrees = tiltDegrees
        self.qualityOverridden = qualityOverridden
        self.landmarks = landmarks
    }

    public var imageSize: Point2D { Point2D(x: Double(pixelWidth), y: Double(pixelHeight)) }

    /// Frontal metrics, when this is a frontal capture with landmarks.
    public func frontalMetrics(sigma: Double) -> FrontalMetrics? {
        guard angle == .frontal, let landmarks else { return nil }
        return FrontalMetricsCalculator.compute(landmarks, landmarkSigmaRatio: sigma)
    }

    /// Flags this capture contributes to any comparison that uses it.
    public var reliabilityFlags: [ReliabilityFlag] {
        var flags: [ReliabilityFlag] = []
        if let q = quality, !q.passed {
            flags.append(.lowImageQuality)
            if q.failures.contains(.tilted) { flags.append(.excessiveTilt) }
        }
        if qualityOverridden { flags.append(.qualityOverridden) }
        return flags
    }

    public func summary(sigma: Double) -> CaptureSummary {
        CaptureSummary(angle: angle, capturedAt: capturedAt, quality: quality, qualityOverridden: qualityOverridden,
                       landmarks: landmarks, frontalMetrics: frontalMetrics(sigma: sigma))
    }
}
