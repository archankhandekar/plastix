import Foundation

/// A 2D similarity transform: `apply(p) = scale * R(rotation) * p + translation`.
public struct SimilarityTransform: Codable, Equatable, Sendable {
    public let scale: Double
    public let rotation: Double
    public let translation: Point2D

    public init(scale: Double, rotation: Double, translation: Point2D) {
        self.scale = scale
        self.rotation = rotation
        self.translation = translation
    }

    public static let identity = SimilarityTransform(scale: 1, rotation: 0, translation: .zero)

    public func apply(_ p: Point2D) -> Point2D {
        p.rotated(by: rotation) * scale + translation
    }

    public var inverse: SimilarityTransform {
        let invScale = 1 / scale
        let t = (translation * -invScale).rotated(by: -rotation)
        return SimilarityTransform(scale: invScale, rotation: -rotation, translation: t)
    }

    /// Least-squares similarity (Umeyama, 2D closed form) mapping `from[i]` onto `to[i]`.
    /// Returns nil when fewer than two correspondences exist, counts differ, or the source
    /// points are all coincident.
    public static func fit(from source: [Point2D], to target: [Point2D]) -> SimilarityTransform? {
        guard source.count == target.count, source.count >= 2 else { return nil }
        let n = Double(source.count)
        let muS = source.reduce(.zero, +) * (1 / n)
        let muT = target.reduce(.zero, +) * (1 / n)
        var dot = 0.0, cross = 0.0, normS = 0.0
        for (s, t) in zip(source, target) {
            let cs = s - muS, ct = t - muT
            dot += cs.x * ct.x + cs.y * ct.y
            cross += cs.x * ct.y - cs.y * ct.x
            normS += cs.x * cs.x + cs.y * cs.y
        }
        guard normS > 1e-12 else { return nil }
        let rotation = atan2(cross, dot)
        let scale = (dot * dot + cross * cross).squareRoot() / normS
        guard scale.isFinite, scale > 0 else { return nil }
        let translation = muT - muS.rotated(by: rotation) * scale
        return SimilarityTransform(scale: scale, rotation: rotation, translation: translation)
    }
}

/// Codable summary of a registration, stored in comparison results and reports.
public struct RegistrationSummary: Codable, Equatable, Sendable {
    public let transform: SimilarityTransform
    /// Root-mean-square landmark residual after registration, as a fraction of the
    /// baseline reference length.
    public let rmsResidualRatio: Double
    public let sharedLandmarkCount: Int
    public let maxResidualRatio: Double
    public var isReliable: Bool { rmsResidualRatio <= maxResidualRatio }

    public init(transform: SimilarityTransform, rmsResidualRatio: Double, sharedLandmarkCount: Int, maxResidualRatio: Double) {
        self.transform = transform
        self.rmsResidualRatio = rmsResidualRatio
        self.sharedLandmarkCount = sharedLandmarkCount
        self.maxResidualRatio = maxResidualRatio
    }
}

public typealias RegistrationResult = RegistrationSummary

public enum Registration {
    /// Default reliability threshold on the normalized RMS residual.
    public static let defaultMaxResidualRatio = 0.05
    public static let minimumSharedLandmarks = 3

    /// Registers `current` onto `baseline` using the point landmarks both sets share.
    /// Requires both midline landmarks in both sets and at least three shared landmarks.
    /// The transform maps current pixel coordinates into baseline pixel coordinates.
    public static func register(_ current: LandmarkSet, to baseline: LandmarkSet,
                                maxResidualRatio: Double = defaultMaxResidualRatio) -> RegistrationResult? {
        guard let baseFrame = MidlineFrame.from(baseline), MidlineFrame.from(current) != nil else { return nil }
        let shared = LandmarkType.allCases.filter { current[$0] != nil && baseline[$0] != nil }
        guard shared.count >= minimumSharedLandmarks else { return nil }
        let source = shared.map { current[$0]! }
        let target = shared.map { baseline[$0]! }
        guard let t = SimilarityTransform.fit(from: source, to: target) else { return nil }
        var sumSq = 0.0
        for (s, b) in zip(source, target) {
            let d = t.apply(s).distance(to: b)
            sumSq += d * d
        }
        let rms = (sumSq / Double(shared.count)).squareRoot() / baseFrame.referenceLength
        return RegistrationSummary(transform: t, rmsResidualRatio: rms, sharedLandmarkCount: shared.count,
                                   maxResidualRatio: maxResidualRatio)
    }
}
