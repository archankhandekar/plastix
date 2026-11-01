import Foundation

/// One metric compared between a baseline and a current capture.
public struct MetricDelta: Codable, Equatable, Sendable {
    public let name: String
    public let baseline: MetricValue?
    public let current: MetricValue?
    /// current − baseline, nil when either side is not measured.
    public let delta: MetricValue?

    public init(name: String, baseline: MetricValue?, current: MetricValue?) {
        self.name = name
        self.baseline = baseline
        self.current = current
        if let b = baseline, let c = current { delta = c.subtracting(b) } else { delta = nil }
    }
}

/// A per-angle comparison of two capture sets. It carries every reason to distrust it.
public struct CaptureComparison: Codable, Equatable, Sendable {
    public let angle: ViewAngle
    public let deltas: [MetricDelta]
    public let registration: RegistrationSummary?
    public let flags: [ReliabilityFlag]

    /// True only when no reliability flag applies.
    public var isReliable: Bool { flags.isEmpty }

    public init(angle: ViewAngle, deltas: [MetricDelta], registration: RegistrationSummary?, flags: [ReliabilityFlag]) {
        self.angle = angle
        self.deltas = deltas
        self.registration = registration
        self.flags = flags
    }
}

public enum Comparator {
    /// Compares two frontal metric sets. `captureFlags` carries quality-related flags from
    /// either capture (low quality, tilt, overrides) so they travel with the numbers.
    public static func compare(baseline: FrontalMetrics, current: FrontalMetrics,
                               registration: RegistrationResult?, angle: ViewAngle,
                               captureFlags: [ReliabilityFlag] = []) -> CaptureComparison {
        let deltas = zip(baseline.namedMetrics, current.namedMetrics).map { b, c in
            MetricDelta(name: b.name, baseline: b.measurement, current: c.measurement)
        }
        var flags: [ReliabilityFlag] = []
        func add(_ f: ReliabilityFlag) { if !flags.contains(f) { flags.append(f) } }
        baseline.flags.forEach(add)
        current.flags.forEach(add)
        captureFlags.forEach(add)
        if let r = registration {
            if !r.isReliable { add(.registrationResidualHigh) }
        } else {
            add(.registrationResidualHigh)
        }
        return CaptureComparison(angle: angle, deltas: deltas, registration: registration, flags: flags)
    }
}
