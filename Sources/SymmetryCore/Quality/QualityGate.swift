import Foundation

/// Thresholds for the capture quality gate. Defaults are starting guesses; they are
/// editable in Settings and should be tuned on real captures.
public struct QualityThresholds: Codable, Equatable, Sendable {
    /// Minimum variance of the 3x3 Laplacian (on the downsampled luminance image).
    public var minBlurScore: Double
    /// Maximum fraction of pixels clipped at either end of the range.
    public var maxClippedFraction: Double
    /// Maximum device tilt (combined roll and pitch away from the intended pose), degrees.
    public var maxTiltDegrees: Double

    public init(minBlurScore: Double = 60, maxClippedFraction: Double = 0.05, maxTiltDegrees: Double = 8) {
        self.minBlurScore = minBlurScore
        self.maxClippedFraction = maxClippedFraction
        self.maxTiltDegrees = maxTiltDegrees
    }
}

/// The result of the quality gate for one capture. Stored with the capture so that any
/// comparison using it can surface the failures.
public struct QualityReport: Codable, Equatable, Sendable {
    public enum Failure: String, Codable, CaseIterable, Sendable {
        case blurry, overexposed, underexposed, tilted

        public var displayText: String {
            switch self {
            case .blurry: return "Image looks blurred"
            case .overexposed: return "Highlights are clipped"
            case .underexposed: return "Shadows are clipped"
            case .tilted: return "Phone was tilted"
            }
        }
    }

    public let blurScore: Double
    public let clippedHighlightFraction: Double
    public let clippedShadowFraction: Double
    public let tiltDegrees: Double?
    public let failures: [Failure]

    public var passed: Bool { failures.isEmpty }

    public init(blurScore: Double, clippedHighlightFraction: Double, clippedShadowFraction: Double,
                tiltDegrees: Double?, failures: [Failure]) {
        self.blurScore = blurScore
        self.clippedHighlightFraction = clippedHighlightFraction
        self.clippedShadowFraction = clippedShadowFraction
        self.tiltDegrees = tiltDegrees
        self.failures = failures
    }
}

public enum QualityGate {
    /// Luminance at or above this value counts as a clipped highlight.
    public static let highlightClip: UInt8 = 250
    /// Luminance at or below this value counts as a clipped shadow.
    public static let shadowClip: UInt8 = 5

    public static func evaluate(_ image: LuminanceImage, tiltDegrees: Double?, thresholds: QualityThresholds) -> QualityReport {
        let blur = laplacianVariance(image)
        let (hi, lo) = clippedFractions(image)
        var failures: [QualityReport.Failure] = []
        if blur < thresholds.minBlurScore { failures.append(.blurry) }
        if hi > thresholds.maxClippedFraction { failures.append(.overexposed) }
        if lo > thresholds.maxClippedFraction { failures.append(.underexposed) }
        if let tilt = tiltDegrees, abs(tilt) > thresholds.maxTiltDegrees { failures.append(.tilted) }
        return QualityReport(blurScore: blur, clippedHighlightFraction: hi, clippedShadowFraction: lo,
                             tiltDegrees: tiltDegrees, failures: failures)
    }

    /// Variance of the 3x3 Laplacian over interior pixels. Higher means sharper.
    public static func laplacianVariance(_ image: LuminanceImage) -> Double {
        let w = image.width, h = image.height
        guard w >= 3, h >= 3 else { return 0 }
        var sum = 0.0, sumSq = 0.0
        let n = Double((w - 2) * (h - 2))
        image.pixels.withUnsafeBufferPointer { p in
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let c = Int(p[y * w + x])
                    let lap = 4 * c - Int(p[y * w + x - 1]) - Int(p[y * w + x + 1]) - Int(p[(y - 1) * w + x]) - Int(p[(y + 1) * w + x])
                    let d = Double(lap)
                    sum += d
                    sumSq += d * d
                }
            }
        }
        let mean = sum / n
        return max(0, sumSq / n - mean * mean)
    }

    /// Fractions of pixels clipped at the top and bottom of the range.
    public static func clippedFractions(_ image: LuminanceImage) -> (highlight: Double, shadow: Double) {
        guard !image.pixels.isEmpty else { return (0, 0) }
        var hi = 0, lo = 0
        for v in image.pixels {
            if v >= highlightClip { hi += 1 } else if v <= shadowClip { lo += 1 }
        }
        let n = Double(image.pixels.count)
        return (Double(hi) / n, Double(lo) / n)
    }
}
